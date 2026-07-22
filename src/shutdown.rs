//! Graceful-shutdown coordination shared by the listener and request tasks.

#![allow(dead_code)] // Fully wired into the server after Roc ABI regeneration.

use std::sync::{Arc, Mutex};
use tokio::sync::{watch, Notify};

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum ShutdownReason {
    ApplicationRequested { exit_code: i64 },
    Interrupt,
    Terminate,
    StartupFailed(String),
    RuntimeFailed(String),
}

impl ShutdownReason {
    pub(crate) fn default_exit_code(&self) -> i32 {
        match self {
            Self::ApplicationRequested { exit_code } => exit_code_to_i32(*exit_code),
            Self::Interrupt => 130,
            Self::Terminate => 143,
            Self::StartupFailed(_) | Self::RuntimeFailed(_) => 1,
        }
    }
}

fn exit_code_to_i32(code: i64) -> i32 {
    i32::try_from(code).unwrap_or(if code < 0 { i32::MIN } else { i32::MAX })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ShutdownRequest {
    Started,
    AlreadyDraining,
}

struct ShutdownInner {
    reason: Mutex<Option<ShutdownReason>>,
    sender: watch::Sender<Option<ShutdownReason>>,
}

/// First-cause-wins shutdown signal. Clones refer to the same lifecycle.
#[derive(Clone)]
pub(crate) struct ShutdownController {
    inner: Arc<ShutdownInner>,
}

impl ShutdownController {
    pub(crate) fn new() -> Self {
        let (sender, _) = watch::channel(None);
        Self {
            inner: Arc::new(ShutdownInner {
                reason: Mutex::new(None),
                sender,
            }),
        }
    }

    pub(crate) fn request(&self, reason: ShutdownReason) -> ShutdownRequest {
        let mut current = self
            .inner
            .reason
            .lock()
            .expect("shutdown reason mutex poisoned");
        if current.is_some() {
            return ShutdownRequest::AlreadyDraining;
        }

        *current = Some(reason.clone());
        self.inner.sender.send_replace(Some(reason));
        ShutdownRequest::Started
    }

    pub(crate) fn reason(&self) -> Option<ShutdownReason> {
        self.inner
            .reason
            .lock()
            .expect("shutdown reason mutex poisoned")
            .clone()
    }

    pub(crate) async fn requested(&self) -> ShutdownReason {
        if let Some(reason) = self.reason() {
            return reason;
        }

        let mut receiver = self.inner.sender.subscribe();
        loop {
            if let Some(reason) = receiver.borrow_and_update().clone() {
                return reason;
            }
            receiver
                .changed()
                .await
                .expect("shutdown controller sender unexpectedly dropped");
        }
    }
}

#[derive(Default)]
struct RequestCount {
    accepting: bool,
    active: usize,
}

struct RequestTrackerInner {
    count: Mutex<RequestCount>,
    idle: Notify,
}

/// Counts request callbacks until draining is complete.
#[derive(Clone)]
pub(crate) struct RequestTracker {
    inner: Arc<RequestTrackerInner>,
}

impl RequestTracker {
    pub(crate) fn new() -> Self {
        Self {
            inner: Arc::new(RequestTrackerInner {
                count: Mutex::new(RequestCount {
                    accepting: true,
                    active: 0,
                }),
                idle: Notify::new(),
            }),
        }
    }

    /// Begin tracking a request, or reject it once draining has started.
    pub(crate) fn begin(&self) -> Option<ActiveRequest> {
        let mut count = self
            .inner
            .count
            .lock()
            .expect("request tracker mutex poisoned");
        if !count.accepting {
            return None;
        }
        count.active += 1;
        Some(ActiveRequest {
            tracker: self.clone(),
        })
    }

    /// Prevent new request callbacks. Existing guards remain tracked.
    pub(crate) fn begin_draining(&self) {
        let mut count = self
            .inner
            .count
            .lock()
            .expect("request tracker mutex poisoned");
        count.accepting = false;
        if count.active == 0 {
            self.inner.idle.notify_waiters();
        }
    }

    pub(crate) fn active(&self) -> usize {
        self.inner
            .count
            .lock()
            .expect("request tracker mutex poisoned")
            .active
    }

    pub(crate) async fn wait_for_idle(&self) {
        loop {
            // Register before checking the count to avoid missing the last
            // guard's notification between the check and the await.
            let idle = self.inner.idle.notified();
            if self.active() == 0 {
                return;
            }
            idle.await;
        }
    }
}

pub(crate) struct ActiveRequest {
    tracker: RequestTracker,
}

impl Drop for ActiveRequest {
    fn drop(&mut self) {
        let mut count = self
            .tracker
            .inner
            .count
            .lock()
            .expect("request tracker mutex poisoned");
        debug_assert!(count.active > 0);
        count.active -= 1;
        if count.active == 0 {
            self.tracker.inner.idle.notify_waiters();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn first_shutdown_reason_wins() {
        let shutdown = ShutdownController::new();
        assert_eq!(
            shutdown.request(ShutdownReason::ApplicationRequested { exit_code: 7 }),
            ShutdownRequest::Started
        );
        assert_eq!(
            shutdown.request(ShutdownReason::Terminate),
            ShutdownRequest::AlreadyDraining
        );
        assert_eq!(
            shutdown.requested().await,
            ShutdownReason::ApplicationRequested { exit_code: 7 }
        );
    }

    #[tokio::test]
    async fn requested_waits_for_first_cause() {
        let shutdown = ShutdownController::new();
        let waiter = {
            let shutdown = shutdown.clone();
            tokio::spawn(async move { shutdown.requested().await })
        };
        tokio::task::yield_now().await;
        shutdown.request(ShutdownReason::Interrupt);

        assert_eq!(waiter.await.unwrap(), ShutdownReason::Interrupt);
    }

    #[tokio::test]
    async fn request_tracker_drains_existing_requests_and_rejects_new_ones() {
        let tracker = RequestTracker::new();
        let first = tracker.begin().unwrap();
        let second = tracker.begin().unwrap();
        assert_eq!(tracker.active(), 2);

        tracker.begin_draining();
        assert!(tracker.begin().is_none());

        let waiter = {
            let tracker = tracker.clone();
            tokio::spawn(async move { tracker.wait_for_idle().await })
        };
        drop(first);
        assert!(!waiter.is_finished());
        drop(second);
        tokio::time::timeout(Duration::from_secs(1), waiter)
            .await
            .expect("request tracker did not become idle")
            .unwrap();
    }

    #[test]
    fn exit_codes_are_deterministic_and_saturating() {
        assert_eq!(ShutdownReason::Interrupt.default_exit_code(), 130);
        assert_eq!(ShutdownReason::Terminate.default_exit_code(), 143);
        assert_eq!(
            ShutdownReason::ApplicationRequested {
                exit_code: i64::MAX
            }
            .default_exit_code(),
            i32::MAX
        );
    }
}
