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
    queue: VecDeque<T>,
    outstanding: usize,
    stopping: bool,
}

struct Inner<T> {
    state: Mutex<State<T>>,
    available: Condvar,
    workers: usize,
    capacity: usize,
    execute: fn(T),
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
        execute: fn(T),
    ) -> io::Result<Self> {
        assert!(workers > 0, "fixed executor requires at least one worker");
        let capacity = workers
            .checked_add(waiting)
            .expect("fixed executor capacity overflow");
        let inner = Arc::new(Inner {
            state: Mutex::new(State {
                queue: VecDeque::with_capacity(capacity),
                outstanding: 0,
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
    /// Construct and enqueue one job while holding the capacity decision.
    ///
    /// `build` lets the caller embed the exact admission class in the job
    /// without a race between classification and worker pickup.
    pub(crate) fn try_submit(
        &self,
        build: impl FnOnce(AdmissionClass) -> T,
    ) -> Result<AdmissionClass, SubmitError> {
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
        let job = build(class);
        state.queue.push_back(job);
        state.outstanding += 1;
        debug_assert!(state.queue.len() <= self.inner.capacity);
        drop(state);
        self.inner.available.notify_one();
        Ok(class)
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

fn stop<T>(inner: &Inner<T>) {
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
                if let Some(job) = state.queue.pop_front() {
                    break job;
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
        (inner.execute)(job);
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
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Barrier, OnceLock};
    use std::time::{Duration, Instant};

    struct BlockingJob {
        started: Arc<Barrier>,
        release: Arc<Barrier>,
        completed: Arc<AtomicUsize>,
    }

    fn run_blocking(job: BlockingJob) {
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

        assert_eq!(
            handle.try_submit(|class| {
                assert_eq!(class, AdmissionClass::Active);
                job()
            }),
            Ok(AdmissionClass::Active)
        );
        started.wait();
        assert_eq!(
            handle.try_submit(|class| {
                assert_eq!(class, AdmissionClass::Queued);
                job()
            }),
            Ok(AdmissionClass::Queued)
        );
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
    fn shutdown_drains_accepted_jobs_and_rejects_new_work() {
        static COMPLETED: OnceLock<Arc<AtomicUsize>> = OnceLock::new();
        fn count(_: ()) {
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
        fn no_op(_: ()) {}
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
