//! Fixed-worker execution domain with an explicitly bounded ingress ring.
//!
//! The executor owns exactly `workers` threads. At most `workers + waiting`
//! jobs can be admitted at once; the ring is allocated to that complete bound
//! at startup and does not allocate while submitting work.

use std::collections::VecDeque;
use std::io;
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum AdmissionClass {
    Active,
    Queued,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum SubmitError {
    Full,
    Stopping,
}

struct State<T> {
    queue: VecDeque<Entry<T>>,
    outstanding: usize,
    next_ticket: u64,
    stopping: bool,
}

struct Entry<T> {
    ticket: QueueTicket,
    class: AdmissionClass,
    job: T,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct QueueTicket(u64);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct Submission {
    pub(crate) class: AdmissionClass,
    pub(crate) ticket: QueueTicket,
}

struct Inner<T: Send + 'static> {
    state: Mutex<State<T>>,
    available: Condvar,
    workers: usize,
    capacity: usize,
    execute: fn(T, JobRetirement<T>),
}

/// One admitted job's executor capacity.
///
/// Execution functions may retire the job before publishing its result. This
/// matters when the result's consumer immediately submits follow-up work to a
/// zero-waiting executor. Dropping the guard is the panic-safe fallback.
pub(crate) struct JobRetirement<T: Send + 'static> {
    inner: Option<Arc<Inner<T>>>,
}

impl<T: Send + 'static> JobRetirement<T> {
    fn new(inner: Arc<Inner<T>>) -> Self {
        Self { inner: Some(inner) }
    }

    pub(crate) fn retire(mut self) {
        retire_job(
            self.inner
                .take()
                .expect("fixed executor job is retired exactly once"),
        );
    }
}

impl<T: Send + 'static> Drop for JobRetirement<T> {
    fn drop(&mut self) {
        if let Some(inner) = self.inner.take() {
            retire_job(inner);
        }
    }
}

pub(crate) struct FixedExecutor<T: Send + 'static> {
    handle: FixedExecutorHandle<T>,
    workers: Vec<JoinHandle<()>>,
}

pub(crate) struct FixedExecutorHandle<T: Send + 'static> {
    inner: Arc<Inner<T>>,
}

impl<T: Send + 'static> Clone for FixedExecutorHandle<T> {
    fn clone(&self) -> Self {
        Self {
            inner: Arc::clone(&self.inner),
        }
    }
}

impl<T: Send + 'static> FixedExecutor<T> {
    pub(crate) fn new(
        thread_name: &str,
        workers: usize,
        waiting: usize,
        execute: fn(T, JobRetirement<T>),
    ) -> io::Result<Self> {
        assert!(workers > 0, "fixed executor requires at least one worker");
        let capacity = workers
            .checked_add(waiting)
            .expect("fixed executor capacity overflow");
        let inner = Arc::new(Inner {
            state: Mutex::new(State {
                queue: VecDeque::with_capacity(capacity),
                outstanding: 0,
                next_ticket: 0,
                stopping: false,
            }),
            available: Condvar::new(),
            workers,
            capacity,
            execute,
        });
        let mut worker_handles = Vec::with_capacity(workers);
        for index in 0..workers {
            let worker_inner = Arc::clone(&inner);
            match thread::Builder::new()
                .name(format!("{thread_name}-{index}"))
                .spawn(move || worker_loop(worker_inner))
            {
                Ok(worker) => worker_handles.push(worker),
                Err(error) => {
                    stop(&inner);
                    for worker in worker_handles {
                        let _ = worker.join();
                    }
                    return Err(error);
                }
            }
        }
        Ok(Self {
            handle: FixedExecutorHandle { inner },
            workers: worker_handles,
        })
    }

    pub(crate) fn handle(&self) -> FixedExecutorHandle<T> {
        self.handle.clone()
    }

    /// Stop admission, drain every accepted job, and join every worker.
    pub(crate) fn shutdown(self) {
        stop(&self.handle.inner);
        for worker in self.workers {
            worker.join().expect("fixed executor worker panicked");
        }
    }
}

impl<T: Send + 'static> FixedExecutorHandle<T> {
    /// Reject future submissions while allowing every accepted job to drain.
    pub(crate) fn stop_admission(&self) {
        stop(&self.inner);
    }

    /// Construct and enqueue one job while holding the capacity decision.
    ///
    /// `build` lets the caller embed the exact admission class in the job
    /// without a race between classification and worker pickup.
    pub(crate) fn try_submit(
        &self,
        build: impl FnOnce(AdmissionClass) -> T,
    ) -> Result<Submission, SubmitError> {
        let mut state = self
            .inner
            .state
            .lock()
            .expect("fixed executor state mutex poisoned");
        if state.stopping {
            return Err(SubmitError::Stopping);
        }
        if state.outstanding == self.inner.capacity {
            return Err(SubmitError::Full);
        }
        let class = if state.outstanding < self.inner.workers {
            AdmissionClass::Active
        } else {
            AdmissionClass::Queued
        };
        let ticket = QueueTicket(state.next_ticket);
        state.next_ticket = state.next_ticket.wrapping_add(1);
        let job = build(class);
        state.queue.push_back(Entry { ticket, class, job });
        state.outstanding += 1;
        debug_assert!(state.queue.len() <= self.inner.capacity);
        drop(state);
        self.inner.available.notify_one();
        Ok(Submission { class, ticket })
    }

    /// Remove a job which was admitted as queued but has reached its caller's
    /// deadline. `None` means a worker already claimed it.
    pub(crate) fn cancel_queued(&self, ticket: QueueTicket) -> Option<T> {
        let mut state = self
            .inner
            .state
            .lock()
            .expect("fixed executor state mutex poisoned");
        let index = state
            .queue
            .iter()
            .position(|entry| entry.ticket == ticket)?;
        assert_eq!(state.queue[index].class, AdmissionClass::Queued);
        let entry = state
            .queue
            .remove(index)
            .expect("located fixed executor entry exists");
        debug_assert!(state.outstanding > 0);
        state.outstanding -= 1;
        drop(state);
        Some(entry.job)
    }

    #[cfg(test)]
    fn outstanding(&self) -> usize {
        self.inner
            .state
            .lock()
            .expect("fixed executor state mutex poisoned")
            .outstanding
    }
}

fn stop<T: Send + 'static>(inner: &Inner<T>) {
    let mut state = inner
        .state
        .lock()
        .expect("fixed executor state mutex poisoned");
    state.stopping = true;
    drop(state);
    inner.available.notify_all();
}

fn worker_loop<T: Send + 'static>(inner: Arc<Inner<T>>) {
    loop {
        let job = {
            let mut state = inner
                .state
                .lock()
                .expect("fixed executor state mutex poisoned");
            loop {
                if let Some(entry) = state.queue.pop_front() {
                    break entry.job;
                }
                if state.stopping {
                    return;
                }
                state = inner
                    .available
                    .wait(state)
                    .expect("fixed executor state mutex poisoned");
            }
        };
        (inner.execute)(job, JobRetirement::new(Arc::clone(&inner)));
    }
}

fn retire_job<T: Send + 'static>(inner: Arc<Inner<T>>) {
    let mut state = inner
        .state
        .lock()
        .expect("fixed executor state mutex poisoned");
    debug_assert!(state.outstanding > 0);
    state.outstanding -= 1;
    if state.stopping && state.outstanding == 0 {
        drop(state);
        inner.available.notify_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::mpsc;
    use std::sync::{Barrier, OnceLock};
    use std::time::{Duration, Instant};

    struct BlockingJob {
        started: Arc<Barrier>,
        release: Arc<Barrier>,
        completed: Arc<AtomicUsize>,
    }

    fn run_blocking(job: BlockingJob, _retirement: JobRetirement<BlockingJob>) {
        job.started.wait();
        job.release.wait();
        job.completed.fetch_add(1, Ordering::AcqRel);
    }

    #[test]
    fn active_and_waiting_capacity_is_exact() {
        let executor = FixedExecutor::new("bounded-test", 1, 1, run_blocking).unwrap();
        let handle = executor.handle();
        let started = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let completed = Arc::new(AtomicUsize::new(0));
        let job = || BlockingJob {
            started: Arc::clone(&started),
            release: Arc::clone(&release),
            completed: Arc::clone(&completed),
        };

        let first = handle
            .try_submit(|class| {
                assert_eq!(class, AdmissionClass::Active);
                job()
            })
            .unwrap();
        assert_eq!(first.class, AdmissionClass::Active);
        started.wait();
        let second = handle
            .try_submit(|class| {
                assert_eq!(class, AdmissionClass::Queued);
                job()
            })
            .unwrap();
        assert_eq!(second.class, AdmissionClass::Queued);
        assert_eq!(handle.try_submit(|_| job()), Err(SubmitError::Full));

        release.wait();
        while completed.load(Ordering::Acquire) != 1 {
            std::thread::yield_now();
        }
        started.wait();
        release.wait();
        executor.shutdown();
        assert_eq!(completed.load(Ordering::Acquire), 2);
    }

    #[test]
    fn zero_waiting_capacity_is_retired_before_completion_is_published() {
        struct PublishingJob(mpsc::Sender<()>);

        fn publish(job: PublishingJob, retirement: JobRetirement<PublishingJob>) {
            retirement.retire();
            job.0.send(()).unwrap();
        }

        let executor = FixedExecutor::new("handoff-test", 1, 0, publish).unwrap();
        let handle = executor.handle();
        let (completed, receiver) = mpsc::channel();

        let first = handle
            .try_submit(|_| PublishingJob(completed.clone()))
            .unwrap();
        assert_eq!(first.class, AdmissionClass::Active);
        receiver.recv().unwrap();

        // This is the ordinary-handler-to-first-SSE-transition handoff, and
        // also an immediate Wait-to-next-transition handoff. The completion
        // consumer must be able to use the same sole capacity immediately.
        let second = handle.try_submit(|_| PublishingJob(completed)).unwrap();
        assert_eq!(second.class, AdmissionClass::Active);
        receiver.recv().unwrap();

        executor.shutdown();
    }

    #[test]
    fn cancelling_waiting_work_recovers_capacity_without_dispatch() {
        let executor = FixedExecutor::new("cancel-test", 1, 1, run_blocking).unwrap();
        let handle = executor.handle();
        let started = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let completed = Arc::new(AtomicUsize::new(0));
        let job = || BlockingJob {
            started: Arc::clone(&started),
            release: Arc::clone(&release),
            completed: Arc::clone(&completed),
        };

        handle.try_submit(|_| job()).unwrap();
        started.wait();
        let waiting = handle.try_submit(|_| job()).unwrap();
        assert_eq!(waiting.class, AdmissionClass::Queued);
        drop(
            handle
                .cancel_queued(waiting.ticket)
                .expect("waiting job remains cancellable"),
        );
        let replacement = handle.try_submit(|_| job()).unwrap();
        assert_eq!(replacement.class, AdmissionClass::Queued);

        release.wait();
        while completed.load(Ordering::Acquire) != 1 {
            std::thread::yield_now();
        }
        started.wait();
        release.wait();
        executor.shutdown();
        assert_eq!(completed.load(Ordering::Acquire), 2);
    }

    #[test]
    fn shutdown_drains_accepted_jobs_and_rejects_new_work() {
        static COMPLETED: OnceLock<Arc<AtomicUsize>> = OnceLock::new();
        fn count(_: (), _retirement: JobRetirement<()>) {
            COMPLETED
                .get()
                .expect("test counter installed")
                .fetch_add(1, Ordering::AcqRel);
        }

        let completed = COMPLETED
            .get_or_init(|| Arc::new(AtomicUsize::new(0)))
            .clone();
        completed.store(0, Ordering::Release);
        let executor = FixedExecutor::new("drain-test", 2, 4, count).unwrap();
        let handle = executor.handle();
        for _ in 0..6 {
            handle.try_submit(|_| ()).unwrap();
        }
        executor.shutdown();
        assert_eq!(completed.load(Ordering::Acquire), 6);
        assert_eq!(handle.try_submit(|_| ()), Err(SubmitError::Stopping));
    }

    #[test]
    fn submission_does_not_allocate_after_construction() {
        // The process allocator is not replaced in this unit test, so exercise
        // the stronger structural property: the preallocated ring never grows.
        fn no_op(_: (), _retirement: JobRetirement<()>) {}
        let executor = FixedExecutor::new("allocation-test", 1, 3, no_op).unwrap();
        let handle = executor.handle();
        let initial_capacity = handle.inner.state.lock().unwrap().queue.capacity();
        for _ in 0..1000 {
            while handle.try_submit(|_| ()).is_err() {
                std::thread::yield_now();
            }
            let deadline = Instant::now() + Duration::from_secs(1);
            while handle.outstanding() != 0 {
                assert!(Instant::now() < deadline);
                std::thread::yield_now();
            }
        }
        assert_eq!(
            handle.inner.state.lock().unwrap().queue.capacity(),
            initial_capacity
        );
        executor.shutdown();
    }
}
