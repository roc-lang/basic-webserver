//! A small synchronous admission gate for hosted effects.
//!
//! Hosted effects are called from blocking Roc handler threads, so this uses a
//! condition variable instead of an async semaphore. Both active and waiting
//! work are explicitly bounded.

use std::sync::{Condvar, Mutex};
use std::time::Instant;

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
        self.gate.available.notify_one();
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
}
