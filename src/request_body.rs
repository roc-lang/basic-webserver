//! Request-scoped, bounded transport between Hyper's asynchronous body stream
//! and a synchronous Roc request worker.
//!
//! This module deliberately has no generated-ABI dependencies. The hosted
//! functions can translate [`ReadResult`] and [`BodyError`] after the public
//! Roc contract is finalized.

use crate::abi::roc_host;
use crate::abi::{
    body_error, body_read_all_error, body_read_all_ok, body_read_chunk, body_read_end,
    body_read_error, BodyReadAllResult, BodyReadError, BodyReadErrorTag, BodyReadResult,
    BodyTooLarge,
};
use crate::roc_platform_abi::{RocListWith, RocStr};
use bytes::Bytes;
use futures::{Stream, StreamExt};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock, TryLockError};
use tokio::sync::{mpsc, watch};

pub(crate) type BodyId = u64;

static BODY_REGISTRY: OnceLock<Mutex<Option<Arc<BodyRegistry>>>> = OnceLock::new();

fn global_registry() -> &'static Mutex<Option<Arc<BodyRegistry>>> {
    BODY_REGISTRY.get_or_init(|| Mutex::new(None))
}

pub(crate) fn install_registry(channel_capacity: usize) -> Arc<BodyRegistry> {
    let registry = Arc::new(BodyRegistry::new(channel_capacity));
    *global_registry()
        .lock()
        .expect("request body global registry mutex poisoned") = Some(Arc::clone(&registry));
    registry
}

pub(crate) fn clear_registry() {
    if let Some(registry) = global_registry()
        .lock()
        .expect("request body global registry mutex poisoned")
        .take()
    {
        registry.cancel_all();
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum PumpError {
    ClientDisconnected,
    InvalidBody(String),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum BodyError {
    TooLarge {
        limit_bytes: u64,
        received_at_least: u64,
    },
    ClientDisconnected,
    InvalidBody(String),
    RequestFinished,
    ConcurrentRead,
    Cancelled,
}

#[derive(Debug, Eq, PartialEq)]
pub(crate) enum ReadResult {
    Chunk(Vec<u8>),
    End,
}

#[derive(Clone, Debug)]
enum Terminal {
    End,
    Error(BodyError),
}

#[derive(Debug)]
enum PumpMessage {
    Chunk(Bytes),
    End,
    Error(BodyError),
    Wake,
}

struct BodyState {
    receiver: Mutex<mpsc::Receiver<PumpMessage>>,
    wake_sender: mpsc::Sender<PumpMessage>,
    cancel_sender: watch::Sender<bool>,
    terminal: Mutex<Option<Terminal>>,
    hard_limit: u64,
    narrow_limit: AtomicU64,
    delivered: AtomicU64,
}

impl BodyState {
    fn terminal(&self) -> Option<Terminal> {
        self.terminal
            .lock()
            .expect("request body terminal mutex poisoned")
            .clone()
    }

    fn set_terminal(&self, terminal: Terminal) {
        let mut current = self
            .terminal
            .lock()
            .expect("request body terminal mutex poisoned");
        if current.is_none() {
            *current = Some(terminal);
        }
    }

    fn stop(&self, terminal: Terminal) {
        self.set_terminal(terminal);
        let _ = self.cancel_sender.send(true);
        // If a reader is blocked on an empty channel this wakes it. A full
        // channel means the reader can already make progress and will observe
        // the terminal state immediately after receiving that message.
        let _ = self.wake_sender.try_send(PumpMessage::Wake);
    }

    fn effective_limit(&self, requested_limit: u64) -> u64 {
        let requested_limit = requested_limit.min(self.hard_limit);
        self.narrow_limit
            .fetch_min(requested_limit, Ordering::AcqRel);
        self.narrow_limit.load(Ordering::Acquire)
    }

    fn check_terminal(&self) -> Option<Result<ReadResult, BodyError>> {
        self.terminal().map(|terminal| match terminal {
            Terminal::End => Ok(ReadResult::End),
            Terminal::Error(error) => Err(error),
        })
    }

    fn receive_with_limit(
        &self,
        receiver: &mut mpsc::Receiver<PumpMessage>,
        requested_limit: u64,
    ) -> Result<ReadResult, BodyError> {
        if let Some(result) = self.check_terminal() {
            return result;
        }

        let effective_limit = self.effective_limit(requested_limit);
        let already_delivered = self.delivered.load(Ordering::Acquire);
        if already_delivered > effective_limit {
            let error = BodyError::TooLarge {
                limit_bytes: effective_limit,
                received_at_least: already_delivered,
            };
            self.stop(Terminal::Error(error.clone()));
            return Err(error);
        }

        loop {
            let message = receiver.blocking_recv();

            // Cancellation/expiry wins a race with an already-buffered chunk.
            if let Some(result) = self.check_terminal() {
                return result;
            }

            match message {
                Some(PumpMessage::Chunk(bytes)) if bytes.is_empty() => continue,
                Some(PumpMessage::Chunk(bytes)) => {
                    let previous = self.delivered.load(Ordering::Acquire);
                    let received_at_least = previous.saturating_add(bytes.len() as u64);
                    if received_at_least > effective_limit {
                        let error = BodyError::TooLarge {
                            limit_bytes: effective_limit,
                            received_at_least,
                        };
                        self.stop(Terminal::Error(error.clone()));
                        return Err(error);
                    }
                    self.delivered.store(received_at_least, Ordering::Release);
                    return Ok(ReadResult::Chunk(bytes.to_vec()));
                }
                Some(PumpMessage::End) | None => {
                    self.set_terminal(Terminal::End);
                    return Ok(ReadResult::End);
                }
                Some(PumpMessage::Error(error)) => {
                    self.stop(Terminal::Error(error.clone()));
                    return Err(error);
                }
                Some(PumpMessage::Wake) => {
                    if let Some(result) = self.check_terminal() {
                        return result;
                    }
                }
            }
        }
    }

    fn lock_reader(
        &self,
    ) -> Result<std::sync::MutexGuard<'_, mpsc::Receiver<PumpMessage>>, BodyError> {
        match self.receiver.try_lock() {
            Ok(receiver) => Ok(receiver),
            Err(TryLockError::WouldBlock) => Err(BodyError::ConcurrentRead),
            Err(TryLockError::Poisoned(_)) => Err(BodyError::RequestFinished),
        }
    }

    fn read(&self, requested_limit: u64) -> Result<ReadResult, BodyError> {
        let mut receiver = self.lock_reader()?;
        self.receive_with_limit(&mut receiver, requested_limit)
    }

    fn read_all(&self, requested_limit: u64) -> Result<Vec<u8>, BodyError> {
        let mut receiver = self.lock_reader()?;
        let mut bytes = Vec::new();
        loop {
            match self.receive_with_limit(&mut receiver, requested_limit)? {
                ReadResult::Chunk(chunk) => bytes.extend_from_slice(&chunk),
                ReadResult::End => return Ok(bytes),
            }
        }
    }
}

/// The producer half of a registered body. Move this value into the Tokio task
/// that owns `hyper::body::Incoming`.
pub(crate) struct BodyPump {
    sender: mpsc::Sender<PumpMessage>,
    cancelled: watch::Receiver<bool>,
    hard_limit: u64,
}

impl BodyPump {
    async fn send(&mut self, message: PumpMessage) -> bool {
        tokio::select! {
            biased;
            changed = self.cancelled.changed() => {
                let _ = changed;
                false
            }
            result = self.sender.send(message) => result.is_ok(),
        }
    }

    /// Pump byte frames into the bounded request channel. Frames are split so
    /// every Roc-visible chunk is at most `chunk_size` bytes.
    pub(crate) async fn run<S>(mut self, stream: S, chunk_size: usize)
    where
        S: Stream<Item = Result<Bytes, PumpError>>,
    {
        assert!(chunk_size > 0, "request body chunk size must be nonzero");
        futures::pin_mut!(stream);
        let mut received = 0u64;

        loop {
            let next = tokio::select! {
                biased;
                changed = self.cancelled.changed() => {
                    let _ = changed;
                    return;
                }
                next = stream.next() => next,
            };

            match next {
                None => {
                    self.send(PumpMessage::End).await;
                    return;
                }
                Some(Err(PumpError::ClientDisconnected)) => {
                    self.send(PumpMessage::Error(BodyError::ClientDisconnected))
                        .await;
                    return;
                }
                Some(Err(PumpError::InvalidBody(message))) => {
                    self.send(PumpMessage::Error(BodyError::InvalidBody(message)))
                        .await;
                    return;
                }
                Some(Ok(frame)) if frame.is_empty() => continue,
                Some(Ok(frame)) => {
                    let frame_end = received.saturating_add(frame.len() as u64);
                    if frame_end > self.hard_limit {
                        self.send(PumpMessage::Error(BodyError::TooLarge {
                            limit_bytes: self.hard_limit,
                            received_at_least: frame_end,
                        }))
                        .await;
                        return;
                    }
                    received = frame_end;

                    for offset in (0..frame.len()).step_by(chunk_size) {
                        let end = offset.saturating_add(chunk_size).min(frame.len());
                        if !self
                            .send(PumpMessage::Chunk(frame.slice(offset..end)))
                            .await
                        {
                            return;
                        }
                    }
                }
            }
        }
    }
}

pub(crate) struct BodyRegistration {
    pub(crate) id: BodyId,
    pub(crate) pump: BodyPump,
}

/// Owns all bodies whose Roc request handlers are still active.
pub(crate) struct BodyRegistry {
    next_id: AtomicU64,
    bodies: Mutex<HashMap<BodyId, Arc<BodyState>>>,
    channel_capacity: usize,
}

impl BodyRegistry {
    pub(crate) fn new(channel_capacity: usize) -> Self {
        assert!(
            channel_capacity > 0,
            "request body channel capacity must be nonzero"
        );
        Self {
            next_id: AtomicU64::new(1),
            bodies: Mutex::new(HashMap::new()),
            channel_capacity,
        }
    }

    pub(crate) fn register(&self, hard_limit: u64) -> BodyRegistration {
        let id = self
            .next_id
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |id| id.checked_add(1))
            .expect("request body ID space exhausted");
        let (sender, receiver) = mpsc::channel(self.channel_capacity);
        let (cancel_sender, cancelled) = watch::channel(false);
        let state = Arc::new(BodyState {
            receiver: Mutex::new(receiver),
            wake_sender: sender.clone(),
            cancel_sender,
            terminal: Mutex::new(None),
            hard_limit,
            narrow_limit: AtomicU64::new(hard_limit),
            delivered: AtomicU64::new(0),
        });
        let old = self
            .bodies
            .lock()
            .expect("request body registry mutex poisoned")
            .insert(id, state);
        debug_assert!(old.is_none());

        BodyRegistration {
            id,
            pump: BodyPump {
                sender,
                cancelled,
                hard_limit,
            },
        }
    }

    fn get(&self, id: BodyId) -> Result<Arc<BodyState>, BodyError> {
        self.bodies
            .lock()
            .expect("request body registry mutex poisoned")
            .get(&id)
            .cloned()
            .ok_or(BodyError::RequestFinished)
    }

    pub(crate) fn read(&self, id: BodyId, requested_limit: u64) -> Result<ReadResult, BodyError> {
        self.get(id)?.read(requested_limit)
    }

    pub(crate) fn read_all(&self, id: BodyId, requested_limit: u64) -> Result<Vec<u8>, BodyError> {
        self.get(id)?.read_all(requested_limit)
    }

    pub(crate) fn expire(&self, id: BodyId) {
        if let Some(state) = self
            .bodies
            .lock()
            .expect("request body registry mutex poisoned")
            .remove(&id)
        {
            state.stop(Terminal::Error(BodyError::RequestFinished));
        }
    }

    #[cfg(test)]
    pub(crate) fn cancel(&self, id: BodyId) {
        if let Some(state) = self
            .bodies
            .lock()
            .expect("request body registry mutex poisoned")
            .remove(&id)
        {
            state.stop(Terminal::Error(BodyError::Cancelled));
        }
    }

    pub(crate) fn cancel_all(&self) {
        let states: Vec<_> = self
            .bodies
            .lock()
            .expect("request body registry mutex poisoned")
            .drain()
            .map(|(_, state)| state)
            .collect();
        for state in states {
            state.stop(Terminal::Error(BodyError::Cancelled));
        }
    }

    #[cfg(test)]
    fn len(&self) -> usize {
        self.bodies
            .lock()
            .expect("request body registry mutex poisoned")
            .len()
    }
}

fn current_registry() -> Result<Arc<BodyRegistry>, BodyError> {
    global_registry()
        .lock()
        .expect("request body global registry mutex poisoned")
        .clone()
        .ok_or(BodyError::RequestFinished)
}

fn to_host_error(error: BodyError) -> BodyReadError {
    let roc_host = roc_host();
    match error {
        BodyError::TooLarge {
            limit_bytes,
            received_at_least,
        } => body_error(
            BodyReadErrorTag::TooLarge,
            None,
            Some(BodyTooLarge {
                limit_bytes,
                received_at_least,
            }),
        ),
        BodyError::ClientDisconnected => {
            body_error(BodyReadErrorTag::ClientDisconnected, None, None)
        }
        BodyError::InvalidBody(detail) => body_error(
            BodyReadErrorTag::InvalidBody,
            Some(RocStr::from_str(&detail, roc_host)),
            None,
        ),
        BodyError::RequestFinished => body_error(BodyReadErrorTag::RequestFinished, None, None),
        BodyError::ConcurrentRead => body_error(BodyReadErrorTag::ConcurrentRead, None, None),
        BodyError::Cancelled => body_error(BodyReadErrorTag::Cancelled, None, None),
    }
}

#[no_mangle]
pub extern "C" fn hosted_request_body_read(id: u64, requested_limit: u64) -> BodyReadResult {
    match current_registry().and_then(|registry| registry.read(id, requested_limit)) {
        Ok(ReadResult::Chunk(bytes)) => {
            body_read_chunk(unsafe { RocListWith::<u8, false>::from_slice(&bytes, roc_host()) })
        }
        Ok(ReadResult::End) => body_read_end(),
        Err(error) => body_read_error(to_host_error(error)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_request_body_read_all(id: u64, requested_limit: u64) -> BodyReadAllResult {
    match current_registry().and_then(|registry| registry.read_all(id, requested_limit)) {
        Ok(bytes) => {
            body_read_all_ok(unsafe { RocListWith::<u8, false>::from_slice(&bytes, roc_host()) })
        }
        Err(error) => body_read_all_error(to_host_error(error)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::stream;
    use std::thread;
    use std::time::{Duration, Instant};

    fn bytes(value: &'static [u8]) -> Result<Bytes, PumpError> {
        Ok(Bytes::from_static(value))
    }

    fn read_on_thread(
        registry: Arc<BodyRegistry>,
        id: BodyId,
        limit: u64,
    ) -> Result<ReadResult, BodyError> {
        thread::spawn(move || registry.read(id, limit))
            .join()
            .expect("reader thread panicked")
    }

    fn wait_until_reader_is_blocking(registry: &BodyRegistry, id: BodyId) {
        let state = registry.get(id).expect("registered body missing");
        let deadline = Instant::now() + Duration::from_secs(1);
        loop {
            match state.receiver.try_lock() {
                Err(TryLockError::WouldBlock) => return,
                Err(TryLockError::Poisoned(_)) => panic!("reader mutex poisoned"),
                Ok(guard) => drop(guard),
            }
            assert!(
                Instant::now() < deadline,
                "reader did not begin blocking within one second"
            );
            // Avoid repeatedly reacquiring the mutex before the new reader
            // thread gets a scheduling turn.
            thread::sleep(Duration::from_millis(1));
        }
    }

    async fn pump_and_read_all(
        hard_limit: u64,
        requested_limit: u64,
        frames: Vec<Result<Bytes, PumpError>>,
        chunk_size: usize,
    ) -> Result<Vec<u8>, BodyError> {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(hard_limit);
        let id = registration.id;
        let reader_registry = Arc::clone(&registry);
        let reader = thread::spawn(move || reader_registry.read_all(id, requested_limit));
        registration
            .pump
            .run(stream::iter(frames), chunk_size)
            .await;
        reader.join().expect("reader thread panicked")
    }

    #[tokio::test(flavor = "current_thread")]
    async fn exact_hard_limit_succeeds() {
        let result = pump_and_read_all(5, 5, vec![bytes(b"abc"), bytes(b"de")], 2).await;
        assert_eq!(result, Ok(b"abcde".to_vec()));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn one_byte_over_hard_limit_fails() {
        let result = pump_and_read_all(5, 5, vec![bytes(b"abc"), bytes(b"def")], 8).await;
        assert_eq!(
            result,
            Err(BodyError::TooLarge {
                limit_bytes: 5,
                received_at_least: 6,
            })
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn zero_limit_accepts_empty_and_rejects_any_data() {
        assert_eq!(pump_and_read_all(0, 0, vec![], 8).await, Ok(Vec::new()));
        assert_eq!(
            pump_and_read_all(0, 0, vec![bytes(b"x")], 8).await,
            Err(BodyError::TooLarge {
                limit_bytes: 0,
                received_at_least: 1,
            })
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn narrowed_limit_is_enforced_across_frames() {
        let result = pump_and_read_all(100, 4, vec![bytes(b"abc"), bytes(b"de")], 8).await;
        assert_eq!(
            result,
            Err(BodyError::TooLarge {
                limit_bytes: 4,
                received_at_least: 5,
            })
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn partial_read_then_read_all_returns_the_remainder() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(100);
        let id = registration.id;
        let reader_registry = Arc::clone(&registry);
        let reader = thread::spawn(move || {
            assert_eq!(
                reader_registry.read(id, 100),
                Ok(ReadResult::Chunk(b"ab".to_vec()))
            );
            reader_registry.read_all(id, 100)
        });
        registration
            .pump
            .run(stream::iter(vec![bytes(b"abcdef")]), 2)
            .await;
        assert_eq!(reader.join().unwrap(), Ok(b"cdef".to_vec()));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn a_limit_cannot_be_widened_after_a_narrow_read() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(100);
        let id = registration.id;
        let reader_registry = Arc::clone(&registry);
        let reader = thread::spawn(move || {
            assert_eq!(
                reader_registry.read(id, 3),
                Ok(ReadResult::Chunk(b"ab".to_vec()))
            );
            reader_registry.read(id, 100)
        });
        registration
            .pump
            .run(stream::iter(vec![bytes(b"abcd")]), 2)
            .await;
        assert_eq!(
            reader.join().unwrap(),
            Err(BodyError::TooLarge {
                limit_bytes: 3,
                received_at_least: 4,
            })
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn narrowing_below_already_delivered_bytes_fails_immediately() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(100);
        let id = registration.id;
        let reader_registry = Arc::clone(&registry);
        let reader = thread::spawn(move || {
            assert_eq!(
                reader_registry.read(id, 100),
                Ok(ReadResult::Chunk(b"abcdef".to_vec()))
            );
            reader_registry.read_all(id, 3)
        });
        registration
            .pump
            .run(stream::iter(vec![bytes(b"abcdef")]), 8)
            .await;
        assert_eq!(
            reader.join().unwrap(),
            Err(BodyError::TooLarge {
                limit_bytes: 3,
                received_at_least: 6,
            })
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn empty_frames_are_ignored_and_frames_are_split() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(100);
        let id = registration.id;
        let reader_registry = Arc::clone(&registry);
        let reader = thread::spawn(move || {
            let mut chunks = Vec::new();
            loop {
                match reader_registry.read(id, 100).unwrap() {
                    ReadResult::Chunk(chunk) => chunks.push(chunk),
                    ReadResult::End => return chunks,
                }
            }
        });
        registration
            .pump
            .run(stream::iter(vec![bytes(b""), bytes(b"abcdefg")]), 3)
            .await;
        assert_eq!(
            reader.join().unwrap(),
            vec![b"abc".to_vec(), b"def".to_vec(), b"g".to_vec()]
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn end_is_stable_across_repeated_reads() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(10);
        let id = registration.id;
        registration.pump.run(stream::empty(), 4).await;
        assert_eq!(
            read_on_thread(Arc::clone(&registry), id, 10),
            Ok(ReadResult::End)
        );
        assert_eq!(
            read_on_thread(Arc::clone(&registry), id, 10),
            Ok(ReadResult::End)
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn source_errors_are_typed_and_stable() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(10);
        let id = registration.id;
        registration
            .pump
            .run(
                stream::iter(vec![Err(PumpError::InvalidBody("bad frame".into()))]),
                4,
            )
            .await;
        let expected = Err(BodyError::InvalidBody("bad frame".into()));
        assert_eq!(read_on_thread(Arc::clone(&registry), id, 10), expected);
        let expected = Err(BodyError::InvalidBody("bad frame".into()));
        assert_eq!(read_on_thread(Arc::clone(&registry), id, 10), expected);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn client_disconnect_is_preserved() {
        let result = pump_and_read_all(10, 10, vec![Err(PumpError::ClientDisconnected)], 4).await;
        assert_eq!(result, Err(BodyError::ClientDisconnected));
    }

    #[test]
    fn stale_ids_fail_without_touching_another_body() {
        let registry = BodyRegistry::new(1);
        let first = registry.register(10);
        registry.expire(first.id);
        let second = registry.register(10);
        assert_ne!(first.id, second.id);
        assert_eq!(registry.read(first.id, 10), Err(BodyError::RequestFinished));
        registry.expire(second.id);
    }

    #[test]
    fn expiry_wakes_a_blocked_reader() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(10);
        let id = registration.id;
        let reader_registry = Arc::clone(&registry);
        let reader = thread::spawn(move || reader_registry.read(id, 10));
        wait_until_reader_is_blocking(&registry, id);
        registry.expire(id);
        assert_eq!(reader.join().unwrap(), Err(BodyError::RequestFinished));
    }

    #[test]
    fn cancellation_wakes_a_blocked_reader() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(10);
        let id = registration.id;
        let reader_registry = Arc::clone(&registry);
        let reader = thread::spawn(move || reader_registry.read(id, 10));
        wait_until_reader_is_blocking(&registry, id);
        registry.cancel(id);
        assert_eq!(reader.join().unwrap(), Err(BodyError::Cancelled));
    }

    #[test]
    fn a_second_simultaneous_reader_is_rejected() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(10);
        let id = registration.id;
        let first_registry = Arc::clone(&registry);
        let first = thread::spawn(move || first_registry.read(id, 10));
        wait_until_reader_is_blocking(&registry, id);
        assert_eq!(registry.read(id, 10), Err(BodyError::ConcurrentRead));
        registry.cancel(id);
        assert_eq!(first.join().unwrap(), Err(BodyError::Cancelled));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn bounded_channel_backpressures_the_pump() {
        let registry = Arc::new(BodyRegistry::new(1));
        let registration = registry.register(100);
        let id = registration.id;
        let pump = tokio::spawn(
            registration
                .pump
                .run(stream::iter(vec![bytes(b"a"), bytes(b"b"), bytes(b"c")]), 1),
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
        assert!(!pump.is_finished());
        assert_eq!(
            read_on_thread(Arc::clone(&registry), id, 100),
            Ok(ReadResult::Chunk(b"a".to_vec()))
        );
        registry.cancel(id);
        tokio::time::timeout(Duration::from_secs(1), pump)
            .await
            .expect("cancelled pump did not stop")
            .expect("pump task panicked");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn cancellation_stops_a_pump_waiting_for_network_input() {
        let registry = BodyRegistry::new(1);
        let registration = registry.register(100);
        let id = registration.id;
        let pump = tokio::spawn(registration.pump.run(stream::pending(), 8));
        tokio::task::yield_now().await;
        registry.cancel(id);
        tokio::time::timeout(Duration::from_secs(1), pump)
            .await
            .expect("cancelled pending pump did not stop")
            .expect("pump task panicked");
    }

    #[test]
    fn cancel_all_wakes_every_reader_and_clears_the_registry() {
        let registry = Arc::new(BodyRegistry::new(1));
        let first = registry.register(10);
        let second = registry.register(10);
        let readers: Vec<_> = [first.id, second.id]
            .into_iter()
            .map(|id| {
                let registry = Arc::clone(&registry);
                thread::spawn(move || registry.read(id, 10))
            })
            .collect();
        wait_until_reader_is_blocking(&registry, first.id);
        wait_until_reader_is_blocking(&registry, second.id);
        registry.cancel_all();
        assert_eq!(registry.len(), 0);
        for reader in readers {
            assert_eq!(reader.join().unwrap(), Err(BodyError::Cancelled));
        }
    }
}
