//! Serialized application-state transitions for concurrent request handlers.
//!
//! Request workers send owned actions to this coordinator and wait for an
//! owned result. Only the application's pure transition function runs on the
//! coordinator thread; request body reads and other effects remain concurrent.

use crate::abi::{state_apply_ok, state_apply_stopping, ServerTransition, StateApplyResult};
use crate::roc_platform_abi::{roc_transition_for_host, RocBox};
use std::fmt;
use std::sync::mpsc::{self, Receiver, SyncSender};
use std::sync::{Mutex, OnceLock};
use std::thread::{self, JoinHandle};

enum Command<Action, Reply> {
    Apply {
        action: Action,
        reply: SyncSender<Reply>,
    },
    Stop,
}

/// An inexpensive, cloneable capability for applying state transitions.
pub(crate) struct StateClient<Action, Reply> {
    sender: SyncSender<Command<Action, Reply>>,
}

impl<Action, Reply> Clone for StateClient<Action, Reply> {
    fn clone(&self) -> Self {
        Self {
            sender: self.sender.clone(),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ApplyError {
    ServerStopping,
}

impl fmt::Display for ApplyError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ServerStopping => formatter.write_str("server is stopping"),
        }
    }
}

impl<Action, Reply> StateClient<Action, Reply> {
    /// Apply one linearizable transition and wait for its result.
    ///
    /// A bounded command queue intentionally backpressures request workers. The
    /// state coordinator never performs request I/O, so a healthy transition
    /// should release capacity quickly.
    pub(crate) fn apply(&self, action: Action) -> Result<Reply, ApplyError> {
        let (reply, result) = mpsc::sync_channel(1);
        self.sender
            .send(Command::Apply { action, reply })
            .map_err(|_| ApplyError::ServerStopping)?;
        result.recv().map_err(|_| ApplyError::ServerStopping)
    }
}

/// Owns the coordinator thread and the final application model.
pub(crate) struct StateRuntime<Model, Action, Reply> {
    client: Option<StateClient<Action, Reply>>,
    coordinator: Option<JoinHandle<Model>>,
}

impl<Model, Action, Reply> StateRuntime<Model, Action, Reply>
where
    Model: Send + 'static,
    Action: Send + 'static,
    Reply: Send + 'static,
{
    pub(crate) fn start(
        initial_model: Model,
        queue_capacity: usize,
        transition: impl Fn(Action, Model) -> (Model, Reply) + Send + 'static,
    ) -> Self {
        assert!(queue_capacity > 0, "state queue capacity must be non-zero");

        let (sender, receiver) = mpsc::sync_channel(queue_capacity);
        let coordinator = thread::Builder::new()
            .name("roc-state".to_owned())
            .spawn(move || run_coordinator(initial_model, receiver, transition))
            .expect("failed to start Roc state coordinator");

        Self {
            client: Some(StateClient { sender }),
            coordinator: Some(coordinator),
        }
    }

    pub(crate) fn client(&self) -> StateClient<Action, Reply> {
        self.client
            .as_ref()
            .expect("state runtime is already stopping")
            .clone()
    }

    /// Close the action queue, drain actions already accepted, and recover the
    /// final model for the application's shutdown hook.
    pub(crate) fn stop(mut self) -> Model {
        if let Some(client) = self.client.take() {
            // Active requests have drained before lifecycle shutdown reaches
            // this point, so Stop follows every legitimate state action.
            let _ = client.sender.send(Command::Stop);
        }
        self.coordinator
            .take()
            .expect("state coordinator is missing")
            .join()
            .unwrap_or_else(|_| panic!("Roc state coordinator panicked"))
    }
}

fn run_coordinator<Model, Action, Reply>(
    mut model: Model,
    receiver: Receiver<Command<Action, Reply>>,
    transition: impl Fn(Action, Model) -> (Model, Reply),
) -> Model {
    while let Ok(command) = receiver.recv() {
        match command {
            Command::Apply { action, reply } => {
                let (next_model, result) = transition(action, model);
                model = next_model;
                // A request can disappear while its transition is running. The
                // state update remains committed and the unobserved result drops.
                let _ = reply.send(result);
            }
            Command::Stop => break,
        }
    }
    model
}

/// Exclusive ownership of a generic Roc box while it crosses a Rust thread.
/// The pointer itself is never dereferenced by Rust; Roc's generated wrappers
/// consume it on the coordinator or request-worker side.
#[derive(Debug)]
pub(crate) struct RocValueBox(pub(crate) RocBox);

// SAFETY: each RocValueBox represents one owned reference and is moved, never
// shared. Values that transition shares between its model and result use Roc's
// atomic refcounts generated for provided/hosted boundaries.
unsafe impl Send for RocValueBox {}

pub(crate) type RocStateRuntime = StateRuntime<RocValueBox, RocValueBox, RocValueBox>;
type RocStateClient = StateClient<RocValueBox, RocValueBox>;

static ROC_STATE_CLIENT: OnceLock<Mutex<Option<RocStateClient>>> = OnceLock::new();

fn global_client() -> &'static Mutex<Option<RocStateClient>> {
    ROC_STATE_CLIENT.get_or_init(|| Mutex::new(None))
}

pub(crate) fn start_roc_state(initial_model: RocBox, queue_capacity: usize) -> RocStateRuntime {
    let runtime = StateRuntime::start(
        RocValueBox(initial_model),
        queue_capacity,
        |RocValueBox(action), RocValueBox(model)| {
            let ServerTransition {
                model: next_model,
                result,
            } = unsafe { roc_transition_for_host(action, model) };
            (RocValueBox(next_model), RocValueBox(result))
        },
    );
    *global_client()
        .lock()
        .expect("Roc state client mutex poisoned") = Some(runtime.client());
    runtime
}

/// Stop accepting hosted state operations before draining the coordinator.
pub(crate) fn clear_roc_state_client() {
    global_client()
        .lock()
        .expect("Roc state client mutex poisoned")
        .take();
}

#[no_mangle]
pub extern "C" fn hosted_state_apply(action: RocBox) -> StateApplyResult {
    let client = global_client()
        .lock()
        .expect("Roc state client mutex poisoned")
        .clone();

    match client.and_then(|client| client.apply(RocValueBox(action)).ok()) {
        Some(RocValueBox(result)) => state_apply_ok(result),
        None => {
            // The hosted ABI transferred this generic action to the host. Its
            // payload layout is intentionally opaque, so RustGlue cannot safely
            // deep-decref it. Legitimate State capabilities expire only after
            // requests drain, making this an exceptional stopping-path leak.
            state_apply_stopping()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier};

    #[test]
    fn applies_transitions_in_one_linearizable_order() {
        let runtime = StateRuntime::start(0_u64, 8, |delta, model| {
            let next = model + delta;
            (next, next)
        });
        let client = runtime.client();

        assert_eq!(client.apply(2), Ok(2));
        assert_eq!(client.apply(3), Ok(5));
        assert_eq!(runtime.stop(), 5);
    }

    #[test]
    fn concurrent_callers_receive_unique_committed_results() {
        const CALLERS: usize = 32;
        let runtime = StateRuntime::start(0_u64, 4, |(), model| {
            let next = model + 1;
            (next, next)
        });
        let barrier = Arc::new(Barrier::new(CALLERS));
        let mut workers = Vec::new();

        for _ in 0..CALLERS {
            let client = runtime.client();
            let barrier = Arc::clone(&barrier);
            workers.push(thread::spawn(move || {
                barrier.wait();
                client.apply(()).unwrap()
            }));
        }

        let mut results: Vec<_> = workers
            .into_iter()
            .map(|worker| worker.join().unwrap())
            .collect();
        results.sort_unstable();
        assert_eq!(results, (1..=CALLERS as u64).collect::<Vec<_>>());
        assert_eq!(runtime.stop(), CALLERS as u64);
    }

    #[test]
    fn accepted_transition_commits_when_caller_drops_result() {
        let runtime = StateRuntime::start(10_u64, 1, |delta, model| {
            let next = model + delta;
            (next, next)
        });
        let client = runtime.client();

        let (reply, _discarded_receiver) = mpsc::sync_channel(1);
        client
            .sender
            .send(Command::Apply { action: 7, reply })
            .unwrap();

        assert_eq!(runtime.stop(), 17);
    }

    #[test]
    fn applying_after_coordinator_exit_reports_stopping() {
        let (sender, receiver) = mpsc::sync_channel(1);
        drop(receiver);
        let client: StateClient<(), ()> = StateClient { sender };

        assert_eq!(client.apply(()), Err(ApplyError::ServerStopping));
    }
}
