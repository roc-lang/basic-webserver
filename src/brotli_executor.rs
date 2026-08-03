//! Fixed-capacity executor for incremental SSE Brotli operations.
//!
//! A compressed stream leases one lane for its lifetime. Submitting a finite
//! PROCESS, FLUSH, or FINISH operation consumes the lane and returns it only in
//! the completion. Dropping an in-flight job marks it cancelled; queued work is
//! skipped and running work destroys the encoder without FINISH before the
//! lane becomes available again.

use crate::compression::{BrotliEncoderStep, ResumableBrotli};
use crate::response_body::ResponseFrameReservation;
use bytes::Bytes;
use std::future::Future;
use std::io;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender, TrySendError};
#[cfg(test)]
use std::sync::Barrier;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};
use std::thread::{self, JoinHandle};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum BrotliProfile {
    Scale,
    #[cfg(test)]
    Compression,
}

impl BrotliProfile {
    fn encoder(self) -> ResumableBrotli {
        match self {
            Self::Scale => ResumableBrotli::new_recycled(1, 11, 256 * 1024),
            #[cfg(test)]
            Self::Compression => ResumableBrotli::new(3, 12),
        }
    }
}

#[cfg(test)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct BrotliExecutorStats {
    pub(crate) lanes: usize,
    pub(crate) available_lanes: usize,
    pub(crate) active_lanes: usize,
    pub(crate) queued_operations: usize,
    pub(crate) running_operations: usize,
    pub(crate) lane_high_water: usize,
    pub(crate) queue_high_water: usize,
    pub(crate) running_high_water: usize,
}

struct Counters {
    active: AtomicUsize,
    queued: AtomicUsize,
    running: AtomicUsize,
    lane_high_water: AtomicUsize,
    queue_high_water: AtomicUsize,
    running_high_water: AtomicUsize,
}

impl Counters {
    fn new() -> Self {
        Self {
            active: AtomicUsize::new(0),
            queued: AtomicUsize::new(0),
            running: AtomicUsize::new(0),
            lane_high_water: AtomicUsize::new(0),
            queue_high_water: AtomicUsize::new(0),
            running_high_water: AtomicUsize::new(0),
        }
    }
}

fn increment_with_high_water(value: &AtomicUsize, high_water: &AtomicUsize) -> usize {
    let current = value.fetch_add(1, Ordering::AcqRel) + 1;
    high_water.fetch_max(current, Ordering::AcqRel);
    current
}

struct LaneCell {
    result: Mutex<Option<JobResult>>,
    waker: Mutex<Option<Waker>>,
    cancelled: AtomicBool,
}

impl LaneCell {
    fn new() -> Self {
        Self {
            result: Mutex::new(None),
            waker: Mutex::new(None),
            cancelled: AtomicBool::new(false),
        }
    }

    fn publish(&self, result: JobResult) {
        let mut result_slot = self.result.lock().expect("Brotli lane result poisoned");
        // Cancellation and publication must meet under the result lock. An
        // atomic check before this lock would leave a window in which the job
        // can be dropped after the worker's check but before it publishes,
        // stranding the completion and its lane forever.
        if self.cancelled.load(Ordering::Acquire) {
            drop(result_slot);
            drop(result);
            return;
        }
        *result_slot = Some(result);
        drop(result_slot);
        let waker = self
            .waker
            .lock()
            .expect("Brotli lane waker poisoned")
            .take();
        if let Some(waker) = waker {
            waker.wake();
        }
    }
}

struct LaneSlot {
    id: usize,
    cell: LaneCell,
    encoder: Mutex<Option<ResumableBrotli>>,
}

enum Message {
    Run(Work),
    Stop,
}

struct ExecutorCore {
    sender: SyncSender<Message>,
    available: Mutex<Vec<usize>>,
    lanes: Vec<Arc<LaneSlot>>,
    counters: Counters,
    #[cfg(test)]
    before_publish: Mutex<Option<Arc<Barrier>>>,
}

impl ExecutorCore {
    fn release_lane(&self, id: usize) {
        self.lanes[id]
            .encoder
            .lock()
            .expect("Brotli lane encoder poisoned")
            .take();
        let previous = self.counters.active.fetch_sub(1, Ordering::AcqRel);
        debug_assert!(previous > 0, "Brotli active lane accounting underflow");
        // Publish availability only after retiring the previous lease. If the
        // slot became visible first, a concurrent admission could increment
        // `active` before this decrement and report a false M+1 high-water.
        self.available
            .lock()
            .expect("Brotli lane pool poisoned")
            .push(id);
    }
}

struct ExecutorOwner {
    core: Arc<ExecutorCore>,
    workers: Mutex<Vec<JoinHandle<()>>>,
}

impl Drop for ExecutorOwner {
    fn drop(&mut self) {
        let workers = self.workers.get_mut().expect("Brotli worker list poisoned");
        for _ in 0..workers.len() {
            self.core
                .sender
                .send(Message::Stop)
                .expect("Brotli workers remain alive until executor drop");
        }
        for worker in workers.drain(..) {
            worker.join().expect("Brotli worker panicked");
        }
    }
}

#[derive(Clone)]
pub(crate) struct BrotliExecutor {
    owner: Arc<ExecutorOwner>,
}

impl BrotliExecutor {
    pub(crate) fn new(worker_count: usize, lane_count: usize) -> io::Result<Self> {
        if worker_count == 0 || lane_count == 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "Brotli workers and lanes must both be non-zero",
            ));
        }
        let (sender, receiver) = mpsc::sync_channel(lane_count);
        let receiver = Arc::new(Mutex::new(receiver));
        let lanes = (0..lane_count)
            .map(|id| {
                Arc::new(LaneSlot {
                    id,
                    cell: LaneCell::new(),
                    encoder: Mutex::new(None),
                })
            })
            .collect();
        let core = Arc::new(ExecutorCore {
            sender,
            available: Mutex::new((0..lane_count).rev().collect()),
            lanes,
            counters: Counters::new(),
            #[cfg(test)]
            before_publish: Mutex::new(None),
        });
        let owner = Arc::new(ExecutorOwner {
            core,
            workers: Mutex::new(Vec::with_capacity(worker_count)),
        });
        let mut workers = owner.workers.lock().expect("Brotli worker list poisoned");
        for index in 0..worker_count {
            let receiver = Arc::clone(&receiver);
            workers.push(
                thread::Builder::new()
                    .name(format!("basic-webserver-brotli-{index}"))
                    .spawn(move || worker_loop(receiver, index))?,
            );
        }
        drop(workers);
        Ok(Self { owner })
    }

    pub(crate) fn try_admit(&self, profile: BrotliProfile) -> Option<BrotliLane> {
        let id = self
            .owner
            .core
            .available
            .lock()
            .expect("Brotli lane pool poisoned")
            .pop()?;
        increment_with_high_water(
            &self.owner.core.counters.active,
            &self.owner.core.counters.lane_high_water,
        );
        let slot = Arc::clone(&self.owner.core.lanes[id]);
        debug_assert_eq!(slot.id, id);
        let previous_encoder = slot
            .encoder
            .lock()
            .expect("Brotli lane encoder poisoned")
            .replace(profile.encoder());
        debug_assert!(
            previous_encoder.is_none(),
            "reused Brotli lane retained an encoder"
        );
        slot.cell.cancelled.store(false, Ordering::Release);
        slot.cell
            .waker
            .lock()
            .expect("Brotli lane waker poisoned")
            .take();
        debug_assert!(
            slot.cell
                .result
                .lock()
                .expect("Brotli lane result poisoned")
                .is_none(),
            "reused Brotli lane retained a completion"
        );
        Some(BrotliLane {
            core: Arc::clone(&self.owner.core),
            slot,
            release_on_drop: true,
        })
    }

    #[cfg(test)]
    pub(crate) fn stats(&self) -> BrotliExecutorStats {
        BrotliExecutorStats {
            lanes: self.owner.core.lanes.len(),
            available_lanes: self
                .owner
                .core
                .available
                .lock()
                .expect("Brotli lane pool poisoned")
                .len(),
            active_lanes: self.owner.core.counters.active.load(Ordering::Acquire),
            queued_operations: self.owner.core.counters.queued.load(Ordering::Acquire),
            running_operations: self.owner.core.counters.running.load(Ordering::Acquire),
            lane_high_water: self
                .owner
                .core
                .counters
                .lane_high_water
                .load(Ordering::Acquire),
            queue_high_water: self
                .owner
                .core
                .counters
                .queue_high_water
                .load(Ordering::Acquire),
            running_high_water: self
                .owner
                .core
                .counters
                .running_high_water
                .load(Ordering::Acquire),
        }
    }

    #[cfg(test)]
    fn pause_next_completion_before_publish(&self, barrier: Arc<Barrier>) {
        *self
            .owner
            .core
            .before_publish
            .lock()
            .expect("Brotli test publication hook poisoned") = Some(barrier);
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum BrotliOperation {
    Process,
    Flush,
    Finish,
}

#[derive(Debug)]
pub(crate) enum BrotliSubmitError {
    ExecutorStopped,
    QueueInvariant,
}

pub(crate) struct BrotliLane {
    core: Arc<ExecutorCore>,
    slot: Arc<LaneSlot>,
    release_on_drop: bool,
}

impl std::fmt::Debug for BrotliLane {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BrotliLane")
            .field("id", &self.slot.id)
            .field(
                "owns_encoder",
                &self
                    .slot
                    .encoder
                    .lock()
                    .expect("Brotli lane encoder poisoned")
                    .is_some(),
            )
            .finish()
    }
}

impl BrotliLane {
    pub(crate) fn submit(
        mut self,
        operation: BrotliOperation,
        input: Bytes,
        input_offset: usize,
        mut output: ResponseFrameReservation,
    ) -> Result<BrotliJob, (Self, BrotliSubmitError)> {
        debug_assert!(
            !output.output_mut().is_empty(),
            "Brotli output buffer must not be empty"
        );
        self.slot.cell.cancelled.store(false, Ordering::Release);
        let work = Work {
            core: Arc::clone(&self.core),
            slot: Arc::clone(&self.slot),
            operation,
            input,
            input_offset,
            output,
        };
        increment_with_high_water(
            &self.core.counters.queued,
            &self.core.counters.queue_high_water,
        );
        match self.core.sender.try_send(Message::Run(work)) {
            Ok(()) => {
                self.release_on_drop = false;
                Ok(BrotliJob {
                    slot: Arc::clone(&self.slot),
                    live: true,
                })
            }
            Err(TrySendError::Disconnected(Message::Run(_work))) => {
                self.core.counters.queued.fetch_sub(1, Ordering::AcqRel);
                Err((self, BrotliSubmitError::ExecutorStopped))
            }
            Err(TrySendError::Full(Message::Run(_work))) => {
                self.core.counters.queued.fetch_sub(1, Ordering::AcqRel);
                Err((self, BrotliSubmitError::QueueInvariant))
            }
            Err(TrySendError::Disconnected(Message::Stop) | TrySendError::Full(Message::Stop)) => {
                unreachable!("submit sends only Run messages")
            }
        }
    }
}

impl Drop for BrotliLane {
    fn drop(&mut self) {
        if self.release_on_drop {
            self.core.release_lane(self.slot.id);
            self.release_on_drop = false;
        }
    }
}

struct Work {
    core: Arc<ExecutorCore>,
    slot: Arc<LaneSlot>,
    operation: BrotliOperation,
    input: Bytes,
    input_offset: usize,
    output: ResponseFrameReservation,
}

struct CompletedWork {
    core: Arc<ExecutorCore>,
    slot: Arc<LaneSlot>,
    input: Bytes,
    input_offset: usize,
    output: Option<ResponseFrameReservation>,
    step: Option<io::Result<BrotliEncoderStep>>,
    #[cfg(test)]
    worker_index: usize,
    release_on_drop: bool,
}

impl Drop for CompletedWork {
    fn drop(&mut self) {
        if self.release_on_drop {
            self.core.release_lane(self.slot.id);
            self.release_on_drop = false;
        }
    }
}

enum JobResult {
    Completed(CompletedWork),
}

pub(crate) struct BrotliCompletion {
    pub(crate) lane: BrotliLane,
    pub(crate) input: Bytes,
    pub(crate) input_offset: usize,
    pub(crate) output: ResponseFrameReservation,
    pub(crate) step: io::Result<BrotliEncoderStep>,
    #[cfg(test)]
    pub(crate) worker_index: usize,
}

pub(crate) struct BrotliJob {
    slot: Arc<LaneSlot>,
    live: bool,
}

impl Future for BrotliJob {
    type Output = io::Result<BrotliCompletion>;

    fn poll(mut self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Self::Output> {
        let result = self
            .slot
            .cell
            .result
            .lock()
            .expect("Brotli lane result poisoned")
            .take();
        match result {
            Some(JobResult::Completed(mut work)) => {
                work.release_on_drop = false;
                let lane = BrotliLane {
                    core: Arc::clone(&work.core),
                    slot: Arc::clone(&work.slot),
                    release_on_drop: true,
                };
                self.live = false;
                Poll::Ready(Ok(BrotliCompletion {
                    lane,
                    input: std::mem::take(&mut work.input),
                    input_offset: work.input_offset,
                    output: work
                        .output
                        .take()
                        .expect("live Brotli completion owns output reservation"),
                    step: work.step.take().expect("Brotli completion owns its step"),
                    #[cfg(test)]
                    worker_index: work.worker_index,
                }))
            }
            None => {
                *self
                    .slot
                    .cell
                    .waker
                    .lock()
                    .expect("Brotli lane waker poisoned") = Some(context.waker().clone());
                // Close the publish-before-register race.
                let result_is_ready = self
                    .slot
                    .cell
                    .result
                    .lock()
                    .expect("Brotli lane result poisoned")
                    .is_some();
                if result_is_ready {
                    context.waker().wake_by_ref();
                }
                Poll::Pending
            }
        }
    }
}

impl Drop for BrotliJob {
    fn drop(&mut self) {
        if !self.live {
            return;
        }
        self.slot.cell.cancelled.store(true, Ordering::Release);
        self.slot
            .cell
            .waker
            .lock()
            .expect("Brotli lane waker poisoned")
            .take();
        if let Some(JobResult::Completed(work)) = self
            .slot
            .cell
            .result
            .lock()
            .expect("Brotli lane result poisoned")
            .take()
        {
            drop(work);
        }
        self.live = false;
    }
}

fn worker_loop(receiver: Arc<Mutex<Receiver<Message>>>, worker_index: usize) {
    #[cfg(not(test))]
    let _ = worker_index;
    loop {
        let message = receiver.lock().expect("Brotli receiver poisoned").recv();
        let Ok(message) = message else {
            return;
        };
        let Message::Run(mut work) = message else {
            return;
        };
        work.core.counters.queued.fetch_sub(1, Ordering::AcqRel);
        increment_with_high_water(
            &work.core.counters.running,
            &work.core.counters.running_high_water,
        );
        if work.slot.cell.cancelled.load(Ordering::Acquire) {
            work.core.counters.running.fetch_sub(1, Ordering::AcqRel);
            work.core.release_lane(work.slot.id);
            continue;
        }

        let step = {
            let mut encoder = work
                .slot
                .encoder
                .lock()
                .expect("Brotli lane encoder poisoned");
            let encoder = encoder
                .as_mut()
                .expect("admitted Brotli lane owns a stable encoder");
            match work.operation {
                BrotliOperation::Process => encoder.process(
                    &work.input,
                    &mut work.input_offset,
                    work.output.output_mut(),
                ),
                BrotliOperation::Flush => encoder.flush(work.output.output_mut()),
                BrotliOperation::Finish => encoder.finish(work.output.output_mut()),
            }
        };
        work.core.counters.running.fetch_sub(1, Ordering::AcqRel);

        #[cfg(test)]
        if let Some(barrier) = work
            .core
            .before_publish
            .lock()
            .expect("Brotli test publication hook poisoned")
            .take()
        {
            barrier.wait();
            barrier.wait();
        }

        work.slot.cell.publish(JobResult::Completed(CompletedWork {
            core: Arc::clone(&work.core),
            slot: Arc::clone(&work.slot),
            input: work.input,
            input_offset: work.input_offset,
            output: Some(work.output),
            step: Some(step),
            #[cfg(test)]
            worker_index,
            release_on_drop: true,
        }));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    use std::task::Poll;
    use std::time::{Duration, Instant};

    fn complete(job: BrotliJob) -> BrotliCompletion {
        futures::executor::block_on(job).expect("Brotli operation completes")
    }

    fn reserve(pool: &crate::response_body::ResponseFramePool) -> ResponseFrameReservation {
        let waker = futures::task::noop_waker();
        let context = Context::from_waker(&waker);
        match pool.poll_reserve(&context) {
            Poll::Ready(reservation) => reservation,
            Poll::Pending => panic!("released Brotli test frame must be available"),
        }
    }

    fn wait_for_all_lanes(executor: &BrotliExecutor) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while executor.stats().available_lanes != executor.stats().lanes
            && Instant::now() < deadline
        {
            thread::yield_now();
        }
        assert_eq!(executor.stats().available_lanes, executor.stats().lanes);
        assert_eq!(executor.stats().active_lanes, 0);
    }

    #[test]
    fn lane_capacity_is_exact_and_recovers() {
        let executor = BrotliExecutor::new(1, 2).unwrap();
        let first = executor.try_admit(BrotliProfile::Scale).unwrap();
        let second = executor.try_admit(BrotliProfile::Compression).unwrap();
        assert!(executor.try_admit(BrotliProfile::Scale).is_none());
        assert_eq!(executor.stats().active_lanes, 2);
        drop(first);
        assert!(executor.try_admit(BrotliProfile::Scale).is_some());
        drop(second);
        assert_eq!(executor.stats().lane_high_water, 2);
    }

    #[test]
    fn incremental_jobs_roundtrip_and_run_only_on_named_workers() {
        let executor = BrotliExecutor::new(2, 1).unwrap();
        let mut lane = executor.try_admit(BrotliProfile::Compression).unwrap();
        let input = Bytes::from("data: <div>bounded Roc SSE</div>\n\n".repeat(512));
        let mut input_offset = 0;
        let mut encoded = Vec::new();
        let pool = crate::response_body::ResponseFramePool::new(1, 7);

        while input_offset < input.len() {
            let mut completion = complete(
                lane.submit(
                    BrotliOperation::Process,
                    input.clone(),
                    input_offset,
                    reserve(&pool),
                )
                .expect("admitted lane always has queue capacity"),
            );
            assert!(completion.worker_index < 2);
            assert_eq!(completion.input.as_ptr(), input.as_ptr());
            let step = completion.step.unwrap();
            input_offset = completion.input_offset;
            encoded.extend_from_slice(&completion.output.output_mut()[..step.output_written]);
            drop(completion.output);
            lane = completion.lane;
        }
        loop {
            let mut completion = complete(
                lane.submit(BrotliOperation::Flush, Bytes::new(), 0, reserve(&pool))
                    .expect("admitted lane always has queue capacity"),
            );
            let step = completion.step.unwrap();
            encoded.extend_from_slice(&completion.output.output_mut()[..step.output_written]);
            drop(completion.output);
            lane = completion.lane;
            if step.complete {
                break;
            }
        }
        loop {
            let mut completion = complete(
                lane.submit(BrotliOperation::Finish, Bytes::new(), 0, reserve(&pool))
                    .expect("admitted lane always has queue capacity"),
            );
            let step = completion.step.unwrap();
            encoded.extend_from_slice(&completion.output.output_mut()[..step.output_written]);
            drop(completion.output);
            lane = completion.lane;
            if step.complete {
                break;
            }
        }
        drop(lane);

        let mut decoded = Vec::new();
        brotli::Decompressor::new(encoded.as_slice(), 4096)
            .read_to_end(&mut decoded)
            .unwrap();
        assert_eq!(decoded, input);
        assert_eq!(executor.stats().running_high_water, 1);
        assert_eq!(executor.stats().active_lanes, 0);
    }

    #[test]
    fn dropping_a_job_is_prompt_and_capacity_returns_after_worker_cleanup() {
        let executor = BrotliExecutor::new(1, 1).unwrap();
        let lane = executor.try_admit(BrotliProfile::Compression).unwrap();
        let pool = crate::response_body::ResponseFramePool::new(1, 7);
        let job = lane
            .submit(
                BrotliOperation::Process,
                Bytes::from(vec![b'x'; 4 * 1024 * 1024]),
                0,
                reserve(&pool),
            )
            .unwrap();
        let started = Instant::now();
        drop(job);
        assert!(started.elapsed() < Duration::from_millis(50));

        wait_for_all_lanes(&executor);
        assert!(executor.try_admit(BrotliProfile::Scale).is_some());
    }

    #[test]
    fn cancelling_between_operation_and_publication_cannot_strand_the_lane() {
        let executor = BrotliExecutor::new(1, 1).unwrap();
        let barrier = Arc::new(Barrier::new(2));
        executor.pause_next_completion_before_publish(Arc::clone(&barrier));
        let lane = executor.try_admit(BrotliProfile::Compression).unwrap();
        let pool = crate::response_body::ResponseFramePool::new(1, 64);
        let job = lane
            .submit(
                BrotliOperation::Process,
                Bytes::from_static(b"data: cancellation race\n\n"),
                0,
                reserve(&pool),
            )
            .unwrap();

        barrier.wait();
        drop(job);
        barrier.wait();

        wait_for_all_lanes(&executor);
        assert!(executor.try_admit(BrotliProfile::Scale).is_some());
    }

    #[test]
    fn cancelling_queued_work_skips_it_and_recovers_its_lane() {
        let executor = BrotliExecutor::new(1, 2).unwrap();
        let barrier = Arc::new(Barrier::new(2));
        executor.pause_next_completion_before_publish(Arc::clone(&barrier));
        let first_lane = executor.try_admit(BrotliProfile::Compression).unwrap();
        let second_lane = executor.try_admit(BrotliProfile::Compression).unwrap();
        let first_pool = crate::response_body::ResponseFramePool::new(1, 64);
        let second_pool = crate::response_body::ResponseFramePool::new(1, 64);
        let first = first_lane
            .submit(
                BrotliOperation::Process,
                Bytes::from_static(b"data: running\n\n"),
                0,
                reserve(&first_pool),
            )
            .unwrap();
        barrier.wait();
        let queued = second_lane
            .submit(
                BrotliOperation::Process,
                Bytes::from_static(b"data: queued\n\n"),
                0,
                reserve(&second_pool),
            )
            .unwrap();
        assert_eq!(executor.stats().queued_operations, 1);
        drop(queued);
        barrier.wait();

        drop(complete(first));
        wait_for_all_lanes(&executor);
        assert_eq!(executor.stats().queued_operations, 0);
    }

    #[test]
    fn executor_owner_shutdown_joins_an_in_flight_worker_from_the_owner_thread() {
        let executor = BrotliExecutor::new(1, 1).unwrap();
        let barrier = Arc::new(Barrier::new(2));
        executor.pause_next_completion_before_publish(Arc::clone(&barrier));
        let lane = executor.try_admit(BrotliProfile::Compression).unwrap();
        let pool = crate::response_body::ResponseFramePool::new(1, 64);
        let job = lane
            .submit(
                BrotliOperation::Process,
                Bytes::from_static(b"data: shutdown ordering\n\n"),
                0,
                reserve(&pool),
            )
            .unwrap();
        barrier.wait();
        drop(job);

        let (shutdown_complete, observe_shutdown) = mpsc::channel();
        let shutdown = thread::spawn(move || {
            drop(executor);
            shutdown_complete.send(()).unwrap();
        });
        assert!(observe_shutdown
            .recv_timeout(Duration::from_millis(20))
            .is_err());
        barrier.wait();
        observe_shutdown
            .recv_timeout(Duration::from_secs(5))
            .unwrap();
        shutdown.join().unwrap();
    }
}
