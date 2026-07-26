//! A small synchronous admission gate for hosted effects.
//!
//! Hosted effects are called from blocking Roc handler threads, so this uses a
//! condition variable instead of an async semaphore. Both active and waiting
//! work are explicitly bounded.

use std::sync::Arc;
use std::sync::{Condvar, Mutex};
use std::time::Instant;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AcquireError {
    Saturated,
    TimedOut,
}

#[derive(Debug)]
struct State {
    active: usize,
    waiting: usize,
}

#[derive(Debug)]
pub(crate) struct BoundedGate {
    max_active: usize,
    max_waiting: usize,
    state: Mutex<State>,
    available: Condvar,
}

impl BoundedGate {
    pub(crate) const fn new(max_active: usize, max_waiting: usize) -> Self {
        Self {
            max_active,
            max_waiting,
            state: Mutex::new(State {
                active: 0,
                waiting: 0,
            }),
            available: Condvar::new(),
        }
    }

    pub(crate) fn acquire(&self, deadline: Instant) -> Result<Permit<'_>, AcquireError> {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());

        if state.active < self.max_active {
            state.active += 1;
            return Ok(Permit { gate: self });
        }
        if state.waiting >= self.max_waiting {
            return Err(AcquireError::Saturated);
        }

        state.waiting += 1;
        loop {
            let now = Instant::now();
            if now >= deadline {
                state.waiting -= 1;
                return Err(AcquireError::TimedOut);
            }

            let remaining = deadline.saturating_duration_since(now);
            let (next_state, wait_result) = self
                .available
                .wait_timeout(state, remaining)
                .unwrap_or_else(|error| error.into_inner());
            state = next_state;

            if state.active < self.max_active {
                state.waiting -= 1;
                state.active += 1;
                return Ok(Permit { gate: self });
            }
            if wait_result.timed_out() {
                state.waiting -= 1;
                return Err(AcquireError::TimedOut);
            }
        }
    }

    /// Wait until every active permit has been released, without admitting or
    /// cancelling work. Returns false when the hard shutdown deadline expires.
    pub(crate) fn wait_for_idle(&self, deadline: Instant) -> bool {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        while state.active != 0 {
            let now = Instant::now();
            if now >= deadline {
                return false;
            }
            let (next_state, wait_result) = self
                .available
                .wait_timeout(state, deadline.saturating_duration_since(now))
                .unwrap_or_else(|error| error.into_inner());
            state = next_state;
            if wait_result.timed_out() && state.active != 0 {
                return false;
            }
        }
        true
    }
}

pub(crate) struct Permit<'a> {
    gate: &'a BoundedGate,
}

impl Drop for Permit<'_> {
    fn drop(&mut self) {
        let mut state = self
            .gate
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        debug_assert!(state.active > 0);
        state.active -= 1;
        if state.active == 0 {
            self.gate.available.notify_all();
        } else {
            self.gate.available.notify_one();
        }
    }
}

/// Async admission for work whose active permit must be owned by a
/// non-cancellable blocking operation. Queued futures release their queue slot
/// when cancelled; active permits can be moved into the blocking closure.
#[derive(Clone, Debug)]
pub(crate) struct AsyncBoundedGate {
    active: Arc<Semaphore>,
    queued: Arc<Semaphore>,
    max_active: u32,
}

impl AsyncBoundedGate {
    pub(crate) fn new(max_active: usize, max_waiting: usize) -> Self {
        let max_active = u32::try_from(max_active).expect("active capacity exceeds u32");
        Self {
            active: Arc::new(Semaphore::new(max_active as usize)),
            queued: Arc::new(Semaphore::new(max_waiting)),
            max_active,
        }
    }

    pub(crate) async fn acquire(&self) -> Result<OwnedSemaphorePermit, AcquireError> {
        if let Ok(active) = Arc::clone(&self.active).try_acquire_owned() {
            return Ok(active);
        }
        let queued = Arc::clone(&self.queued)
            .try_acquire_owned()
            .map_err(|_| AcquireError::Saturated)?;
        let active = Arc::clone(&self.active)
            .acquire_owned()
            .await
            .map_err(|_| AcquireError::Saturated)?;
        drop(queued);
        Ok(active)
    }

    /// Wait until all blocking operations have returned. Cancellation-safe:
    /// dropping this wait does not affect active permits.
    pub(crate) async fn wait_for_idle(&self) {
        let all = Arc::clone(&self.active)
            .acquire_many_owned(self.max_active)
            .await
            .expect("native-work semaphore is never closed");
        drop(all);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn rejects_work_beyond_active_and_waiting_capacity() {
        let gate = std::sync::Arc::new(BoundedGate::new(1, 1));
        let first = gate
            .acquire(Instant::now() + Duration::from_secs(1))
            .unwrap();

        let queued_gate = gate.clone();
        let queued = std::thread::spawn(move || {
            queued_gate
                .acquire(Instant::now() + Duration::from_secs(1))
                .is_ok()
        });
        while gate
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .waiting
            == 0
        {
            std::thread::yield_now();
        }

        assert!(matches!(
            gate.acquire(Instant::now() + Duration::from_secs(1)),
            Err(AcquireError::Saturated)
        ));
        drop(first);
        assert!(queued.join().unwrap());
    }

    #[test]
    fn queue_wait_has_a_deadline() {
        let gate = BoundedGate::new(1, 1);
        let _first = gate
            .acquire(Instant::now() + Duration::from_secs(1))
            .unwrap();
        assert!(matches!(
            gate.acquire(Instant::now() + Duration::from_millis(1)),
            Err(AcquireError::TimedOut)
        ));
    }

    #[test]
    fn idle_wait_observes_active_permits() {
        let gate = BoundedGate::new(1, 0);
        let permit = gate
            .acquire(Instant::now() + Duration::from_secs(1))
            .unwrap();
        assert!(!gate.wait_for_idle(Instant::now() + Duration::from_millis(1)));
        drop(permit);
        assert!(gate.wait_for_idle(Instant::now() + Duration::from_secs(1)));
    }

    #[tokio::test]
    async fn async_queue_is_bounded_and_active_permit_is_owned() {
        let gate = AsyncBoundedGate::new(1, 1);
        let active = gate.acquire().await.unwrap();
        let waiting = {
            let gate = gate.clone();
            tokio::spawn(async move { gate.acquire().await })
        };
        tokio::task::yield_now().await;
        assert!(matches!(gate.acquire().await, Err(AcquireError::Saturated)));

        drop(active);
        drop(waiting.await.unwrap().unwrap());
        tokio::time::timeout(std::time::Duration::from_secs(1), gate.wait_for_idle())
            .await
            .expect("async gate did not become idle");
    }
}
