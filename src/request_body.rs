//! Request-scoped, bounded transport between Hyper's asynchronous body stream
//! and a synchronous Roc request worker.
//!
//! The opaque Roc body capability directly owns [`BodyState`]. A server-held
//! ARC reference expires it when the handler returns; hosted reads consume
//! temporary ARC references supplied by Roc. Delivered chunks move into
//! self-describing seamless allocations whose final Roc release drops the
//! original [`Bytes`] owner.

use crate::abi::{
    body_error, body_read_all_error, body_read_all_ok, body_read_chunk, body_read_end,
    body_read_error, roc_host, BodyReadAllResult, BodyReadError, BodyReadErrorTag, BodyReadResult,
    BodyTooLarge,
};
use crate::roc_alloc::{self, AllocationKind};
use crate::roc_platform_abi::{decref_box_with, incref_box, RocBox, RocHost, RocListWith, RocStr};
use bytes::Bytes;
use futures::{Stream, StreamExt};
use std::sync::atomic::{AtomicIsize, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Mutex, TryLockError};
use std::time::Duration;
use tokio::sync::{mpsc, watch};

const REQUEST_BODY_TOKEN: u64 = 0x5245_5142_4f44_5931;
const SEAMLESS_SLICE_TAG: usize = 1;

static RETAINED_PAYLOAD_BYTES: AtomicUsize = AtomicUsize::new(0);
static SHARED_PAYLOAD_BYTES: AtomicUsize = AtomicUsize::new(0);
static COPIED_PAYLOAD_BYTES: AtomicUsize = AtomicUsize::new(0);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct BodyMetrics {
    pub active_bodies: usize,
    pub body_high_water: usize,
    pub active_backings: usize,
    pub backing_high_water: usize,
    pub retained_payload_bytes: usize,
    pub shared_payload_bytes: usize,
    pub copied_payload_bytes: usize,
}

pub(crate) fn metrics() -> BodyMetrics {
    let allocations = roc_alloc::counts();
    BodyMetrics {
        active_bodies: allocations.active_request_bodies,
        body_high_water: allocations.request_body_high_water,
        active_backings: allocations.active_seamless_backings,
        backing_high_water: allocations.seamless_backing_high_water,
        retained_payload_bytes: RETAINED_PAYLOAD_BYTES.load(Ordering::Acquire),
        shared_payload_bytes: SHARED_PAYLOAD_BYTES.load(Ordering::Acquire),
        copied_payload_bytes: COPIED_PAYLOAD_BYTES.load(Ordering::Acquire),
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
    Timeout,
    ClientDisconnected,
    InvalidBody(String),
    RequestFinished,
    ConcurrentRead,
    Cancelled,
}

#[derive(Debug, Eq, PartialEq)]
pub(crate) enum ReadResult {
    Chunk(Bytes),
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
    declared_length: Option<u64>,
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
                    return Ok(ReadResult::Chunk(bytes));
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

    fn read_all(
        &self,
        requested_limit: u64,
        host: &RocHost,
    ) -> Result<RocListWith<u8, false>, BodyError> {
        let mut receiver = self.lock_reader()?;
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
        let remaining_limit = effective_limit - already_delivered;
        let capacity_hint = self
            .declared_length
            .map(|length| length.saturating_sub(already_delivered))
            .unwrap_or(0)
            .min(remaining_limit);
        let mut output = RocBytesBuilder::new(capacity_hint, remaining_limit, host);

        loop {
            match self.receive_with_limit(&mut receiver, requested_limit)? {
                ReadResult::Chunk(chunk) => output.extend(&chunk)?,
                ReadResult::End => return Ok(output.finish()),
            }
        }
    }
}

/// The producer half of one request body. Move this value into the Tokio task
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
    pub(crate) async fn run<S>(mut self, stream: S, chunk_size: usize, idle_timeout: Duration)
    where
        S: Stream<Item = Result<Bytes, PumpError>>,
    {
        assert!(chunk_size > 0, "request body chunk size must be nonzero");
        assert!(
            !idle_timeout.is_zero(),
            "request body timeout must be nonzero"
        );
        futures::pin_mut!(stream);
        let mut received = 0u64;
        let mut deadline = tokio::time::Instant::now() + idle_timeout;

        loop {
            let next = tokio::select! {
                biased;
                changed = self.cancelled.changed() => {
                    let _ = changed;
                    return;
                }
                next = tokio::time::timeout_at(deadline, stream.next()) => {
                    match next {
                        Ok(next) => next,
                        Err(_) => {
                            self.send(PumpMessage::Error(BodyError::Timeout)).await;
                            return;
                        }
                    }
                },
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
                    // Time spent backpressured on the bounded Roc channel is
                    // application consumption time, not peer idleness.
                    deadline = tokio::time::Instant::now() + idle_timeout;
                }
            }
        }
    }
}

#[repr(C)]
struct BodyPayload {
    token: u64,
    state: BodyState,
}

fn body_box_header_bytes() -> usize {
    core::mem::size_of::<usize>().max(core::mem::align_of::<u64>())
}

unsafe fn body_payload_from_base(base: *mut u8) -> *mut BodyPayload {
    unsafe { base.add(body_box_header_bytes()).cast() }
}

unsafe fn drop_body_allocation(base: *mut u8) {
    let payload = unsafe { body_payload_from_base(base) };
    if unsafe { (*payload).token } != REQUEST_BODY_TOKEN {
        eprintln!("fatal: request-body allocation token was overwritten");
        std::process::abort();
    }
    let payload_ptr = payload.cast::<u8>();
    let refcount = unsafe {
        payload_ptr
            .sub(core::mem::size_of::<isize>())
            .cast::<AtomicIsize>()
    };
    if !roc_alloc::is_finalized_roc_refcount(unsafe { (*refcount).load(Ordering::Acquire) }) {
        eprintln!("fatal: request-body finalizer ran before final Roc ARC release");
        std::process::abort();
    }
    unsafe {
        (*payload).state.stop(Terminal::Error(BodyError::Cancelled));
        payload.drop_in_place();
    }
}

unsafe fn body_state_from_handle(handle: *mut u64) -> &'static BodyState {
    if handle.is_null() || !(handle as usize).is_multiple_of(core::mem::align_of::<u64>()) {
        eprintln!("fatal: invalid request-body capability");
        std::process::abort();
    }
    let base = unsafe { handle.cast::<u8>().sub(body_box_header_bytes()) };
    unsafe {
        roc_alloc::validate_host_owned(
            base,
            AllocationKind::RequestBody,
            body_box_header_bytes() + core::mem::size_of::<BodyPayload>(),
            core::mem::align_of::<BodyPayload>(),
        );
    }
    let payload = handle.cast::<BodyPayload>();
    if unsafe { (*payload).token } != REQUEST_BODY_TOKEN {
        eprintln!("fatal: invalid request-body capability token");
        std::process::abort();
    }
    let refcount = unsafe {
        handle
            .cast::<u8>()
            .sub(core::mem::size_of::<isize>())
            .cast::<AtomicIsize>()
    };
    if unsafe { (*refcount).load(Ordering::Acquire) } <= 0 {
        eprintln!("fatal: stale request-body capability");
        std::process::abort();
    }
    unsafe { &(*payload).state }
}

/// One owned native reference to a request-scoped body capability.
pub(crate) struct BodyHandle {
    raw: *mut u64,
    host: *const RocHost,
}

// SAFETY: the allocation has atomic Roc ARC, and BodyState synchronizes every
// field that may be accessed by the pump and synchronous reader threads.
unsafe impl Send for BodyHandle {}
unsafe impl Sync for BodyHandle {}

impl Clone for BodyHandle {
    fn clone(&self) -> Self {
        unsafe { incref_box(self.raw.cast(), 1) };
        Self {
            raw: self.raw,
            host: self.host,
        }
    }
}

impl BodyHandle {
    fn state(&self) -> &BodyState {
        unsafe { body_state_from_handle(self.raw) }
    }

    /// Retain and transfer one independent Roc reference into Server.Request.
    pub(crate) fn retain_for_roc(&self) -> *mut u64 {
        unsafe { incref_box(self.raw.cast(), 1) };
        self.raw
    }

    pub(crate) fn expire(&self) {
        self.state()
            .stop(Terminal::Error(BodyError::RequestFinished));
    }

    #[cfg(test)]
    fn cancel(&self) {
        self.state().stop(Terminal::Error(BodyError::Cancelled));
    }

    #[cfg(test)]
    fn read(&self, requested_limit: u64) -> Result<ReadResult, BodyError> {
        self.state().read(requested_limit)
    }

    #[cfg(test)]
    fn read_all(&self, requested_limit: u64) -> Result<RocListWith<u8, false>, BodyError> {
        self.state()
            .read_all(requested_limit, unsafe { &*self.host })
    }
}

impl Drop for BodyHandle {
    fn drop(&mut self) {
        unsafe {
            decref_box_with(
                self.raw.cast() as RocBox,
                core::mem::align_of::<u64>(),
                false,
                None,
                &*self.host,
            );
        }
    }
}

pub(crate) struct BodyRegistration {
    pub(crate) handle: BodyHandle,
    pub(crate) pump: BodyPump,
}

pub(crate) fn register(
    hard_limit: u64,
    channel_capacity: usize,
    declared_length: Option<u64>,
    host: &'static RocHost,
) -> BodyRegistration {
    assert!(
        channel_capacity > 0,
        "request body channel capacity must be nonzero"
    );
    let (sender, receiver) = mpsc::channel(channel_capacity);
    let (cancel_sender, cancelled) = watch::channel(false);
    let state = BodyState {
        receiver: Mutex::new(receiver),
        wake_sender: sender.clone(),
        cancel_sender,
        terminal: Mutex::new(None),
        hard_limit,
        declared_length,
        narrow_limit: AtomicU64::new(hard_limit),
        delivered: AtomicU64::new(0),
    };

    let payload_offset = body_box_header_bytes();
    let allocation_size = payload_offset
        .checked_add(core::mem::size_of::<BodyPayload>())
        .expect("request body allocation size overflow");
    let allocation_alignment = core::mem::align_of::<BodyPayload>()
        .max(core::mem::align_of::<usize>())
        .max(core::mem::align_of::<u64>());
    let base = unsafe {
        roc_alloc::allocate_host_owned(
            allocation_size,
            allocation_alignment,
            AllocationKind::RequestBody,
            drop_body_allocation,
        )
    };
    let payload = unsafe { body_payload_from_base(base) };
    let payload_bytes = payload.cast::<u8>();
    let refcount = unsafe {
        payload_bytes
            .sub(core::mem::size_of::<isize>())
            .cast::<AtomicIsize>()
    };
    unsafe {
        refcount.write(AtomicIsize::new(1));
        payload.write(BodyPayload {
            token: REQUEST_BODY_TOKEN,
            state,
        });
    }

    BodyRegistration {
        handle: BodyHandle {
            raw: payload.cast::<u64>(),
            host,
        },
        pump: BodyPump {
            sender,
            cancelled,
            hard_limit,
        },
    }
}

struct OwnedBodyArgument {
    raw: *mut u64,
    host: &'static RocHost,
}

impl OwnedBodyArgument {
    fn new(raw: *mut u64, host: &'static RocHost) -> Self {
        // Validate immediately while this hosted argument owns a live Roc ref.
        let _ = unsafe { body_state_from_handle(raw) };
        Self { raw, host }
    }

    fn state(&self) -> &BodyState {
        unsafe { body_state_from_handle(self.raw) }
    }
}

impl Drop for OwnedBodyArgument {
    fn drop(&mut self) {
        unsafe {
            decref_box_with(
                self.raw.cast(),
                core::mem::align_of::<u64>(),
                false,
                None,
                self.host,
            );
        }
    }
}

#[repr(C)]
struct BytesBacking {
    bytes: Bytes,
    original_ptr: *const u8,
    original_len: usize,
}

unsafe fn drop_seamless_bytes(base: *mut u8) {
    let owner_ptr = unsafe { base.add(core::mem::size_of::<isize>()) };
    let refcount = base.cast::<AtomicIsize>();
    if !roc_alloc::is_finalized_roc_refcount(unsafe { (*refcount).load(Ordering::Acquire) }) {
        eprintln!("fatal: seamless Bytes finalizer ran before final Roc ARC release");
        std::process::abort();
    }
    let owner = owner_ptr.cast::<BytesBacking>();
    let retained = unsafe { (*owner).original_len };
    if unsafe { (*owner).bytes.as_ptr() } != unsafe { (*owner).original_ptr }
        || unsafe { (*owner).bytes.len() } != retained
    {
        eprintln!("fatal: immutable seamless Bytes owner metadata changed");
        std::process::abort();
    }
    unsafe { owner.drop_in_place() };
    let previous = RETAINED_PAYLOAD_BYTES.fetch_sub(retained, Ordering::AcqRel);
    if previous < retained {
        eprintln!("fatal: seamless retained-byte accounting underflow");
        std::process::abort();
    }
}

fn seamless_chunk(bytes: Bytes) -> RocListWith<u8, false> {
    if bytes.is_empty() {
        return RocListWith::empty();
    }
    assert!(
        core::mem::align_of::<BytesBacking>() <= core::mem::align_of::<usize>(),
        "Bytes backing alignment exceeds Roc ARC word alignment"
    );
    let payload_ptr = bytes.as_ptr().cast_mut();
    let payload_len = bytes.len();
    let allocation_size = core::mem::size_of::<isize>()
        .checked_add(core::mem::size_of::<BytesBacking>())
        .expect("seamless Bytes allocation size overflow");
    let base = unsafe {
        roc_alloc::allocate_host_owned(
            allocation_size,
            core::mem::align_of::<usize>(),
            AllocationKind::SeamlessBytes,
            drop_seamless_bytes,
        )
    };
    let owner_ptr = unsafe { base.add(core::mem::size_of::<isize>()) };
    unsafe {
        base.cast::<AtomicIsize>().write(AtomicIsize::new(1));
        owner_ptr.cast::<BytesBacking>().write(BytesBacking {
            bytes,
            original_ptr: payload_ptr,
            original_len: payload_len,
        });
    }
    RETAINED_PAYLOAD_BYTES.fetch_add(payload_len, Ordering::AcqRel);
    SHARED_PAYLOAD_BYTES.fetch_add(payload_len, Ordering::AcqRel);

    let result = RocListWith {
        elements: payload_ptr,
        length: payload_len,
        capacity_or_alloc_ptr: (owner_ptr as usize) | SEAMLESS_SLICE_TAG,
    };
    validate_seamless_range(&result);
    result
}

#[cfg(test)]
pub(crate) fn seamless_chunk_for_test(bytes: Bytes) -> RocListWith<u8, false> {
    seamless_chunk(bytes)
}

fn validate_seamless_range(list: &RocListWith<u8, false>) {
    if list.is_empty() {
        return;
    }
    if !list.is_seamless_slice() {
        eprintln!("fatal: request-body chunk was not represented as a seamless list");
        std::process::abort();
    }
    let owner_address = list.capacity_or_alloc_ptr & !SEAMLESS_SLICE_TAG;
    let owner_ptr = owner_address as *mut BytesBacking;
    let base = unsafe { owner_ptr.cast::<u8>().sub(core::mem::size_of::<isize>()) };
    unsafe {
        roc_alloc::validate_host_owned(
            base,
            AllocationKind::SeamlessBytes,
            core::mem::size_of::<isize>() + core::mem::size_of::<BytesBacking>(),
            core::mem::align_of::<usize>(),
        );
    }
    let owner = unsafe { &*owner_ptr };
    let backing_start = owner.original_ptr as usize;
    let backing_end = backing_start
        .checked_add(owner.original_len)
        .unwrap_or_else(|| {
            eprintln!("fatal: seamless Bytes backing range overflow");
            std::process::abort();
        });
    let slice_start = list.elements as usize;
    let slice_end = slice_start.checked_add(list.length).unwrap_or_else(|| {
        eprintln!("fatal: seamless request-body slice range overflow");
        std::process::abort();
    });
    if slice_start < backing_start || slice_end > backing_end {
        eprintln!("fatal: seamless request-body slice escapes its Bytes backing");
        std::process::abort();
    }
}

/// Validate the allocation and bounds of a seamless byte list returned by Roc.
pub(crate) fn validate_response_body(list: &RocListWith<u8, false>) {
    if list.is_empty() || !list.is_seamless_slice() {
        return;
    }
    let allocation_ptr = (list.capacity_or_alloc_ptr & !SEAMLESS_SLICE_TAG) as *mut u8;
    let refcount = unsafe {
        &*allocation_ptr
            .sub(core::mem::size_of::<isize>())
            .cast::<AtomicIsize>()
    };
    if refcount.load(Ordering::Acquire) == 0 {
        // Roc static data is immutable for the process lifetime and does not
        // have a host allocation header to validate.
        return;
    }
    let base = unsafe { allocation_ptr.sub(core::mem::size_of::<isize>()) };
    if crate::request_parts::contains_address(base.cast()) {
        crate::request_parts::validate_seamless_range(allocation_ptr, list.elements, list.length);
        return;
    }
    match unsafe { roc_alloc::allocation_kind(base) } {
        AllocationKind::SeamlessBytes => validate_seamless_range(list),
        AllocationKind::Ordinary => unsafe {
            roc_alloc::validate_range(base, list.elements, list.length);
        },
        AllocationKind::RequestBody => {
            eprintln!("fatal: response bytes referred to a request-body capability allocation");
            std::process::abort();
        }
    }
}

struct RocBytesBuilder<'a> {
    base: *mut u8,
    length: usize,
    capacity: usize,
    maximum_capacity: usize,
    host: &'a RocHost,
}

impl<'a> RocBytesBuilder<'a> {
    fn new(capacity_hint: u64, maximum_capacity: u64, host: &'a RocHost) -> Self {
        let target_maximum = usize::try_from(maximum_capacity).unwrap_or(usize::MAX);
        let initial = usize::try_from(capacity_hint)
            .unwrap_or(usize::MAX)
            .min(target_maximum);
        let mut result = Self {
            base: core::ptr::null_mut(),
            length: 0,
            capacity: 0,
            maximum_capacity: target_maximum,
            host,
        };
        if initial != 0 {
            result.reserve_exact(initial);
        }
        result
    }

    fn reserve_exact(&mut self, capacity: usize) {
        assert!(capacity <= self.maximum_capacity);
        let header_bytes = core::mem::size_of::<isize>();
        let allocation_size = header_bytes
            .checked_add(capacity)
            .expect("Roc request-body list allocation size overflow");
        unsafe {
            if self.base.is_null() {
                self.base = self
                    .host
                    .alloc(core::mem::align_of::<usize>(), allocation_size)
                    .cast();
                self.base.cast::<AtomicIsize>().write(AtomicIsize::new(1));
            } else {
                self.base = self
                    .host
                    .realloc(
                        self.base.cast(),
                        core::mem::align_of::<usize>(),
                        allocation_size,
                    )
                    .cast();
            }
        }
        self.capacity = capacity;
    }

    fn extend(&mut self, bytes: &[u8]) -> Result<(), BodyError> {
        let required = self
            .length
            .checked_add(bytes.len())
            .unwrap_or(self.maximum_capacity.saturating_add(1));
        if required > self.maximum_capacity {
            return Err(BodyError::TooLarge {
                limit_bytes: self.maximum_capacity as u64,
                received_at_least: required as u64,
            });
        }
        if required > self.capacity {
            let doubled = self.capacity.saturating_mul(2).max(1);
            self.reserve_exact(required.max(doubled).min(self.maximum_capacity));
        }
        unsafe {
            self.base
                .add(core::mem::size_of::<isize>() + self.length)
                .copy_from_nonoverlapping(bytes.as_ptr(), bytes.len());
        }
        self.length = required;
        COPIED_PAYLOAD_BYTES.fetch_add(bytes.len(), Ordering::AcqRel);
        Ok(())
    }

    fn finish(mut self) -> RocListWith<u8, false> {
        if self.length == 0 {
            return RocListWith::empty();
        }
        let data = unsafe { self.base.add(core::mem::size_of::<isize>()) };
        let result = RocListWith {
            elements: data,
            length: self.length,
            capacity_or_alloc_ptr: self
                .capacity
                .checked_shl(1)
                .expect("Roc list capacity does not fit shifted representation"),
        };
        self.base = core::ptr::null_mut();
        result
    }
}

impl Drop for RocBytesBuilder<'_> {
    fn drop(&mut self) {
        if !self.base.is_null() {
            unsafe {
                self.host
                    .dealloc(self.base.cast(), core::mem::align_of::<usize>());
            }
        }
    }
}

fn to_host_error(error: BodyError) -> BodyReadError {
    let host = roc_host();
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
        BodyError::Timeout => body_error(BodyReadErrorTag::Timeout, None, None),
        BodyError::ClientDisconnected => {
            body_error(BodyReadErrorTag::ClientDisconnected, None, None)
        }
        BodyError::InvalidBody(detail) => body_error(
            BodyReadErrorTag::InvalidBody,
            Some(RocStr::from_str(&detail, host)),
            None,
        ),
        BodyError::RequestFinished => body_error(BodyReadErrorTag::RequestFinished, None, None),
        BodyError::ConcurrentRead => body_error(BodyReadErrorTag::ConcurrentRead, None, None),
        BodyError::Cancelled => body_error(BodyReadErrorTag::Cancelled, None, None),
    }
}

#[no_mangle]
pub extern "C" fn hosted_request_body_read(
    handle: *mut u64,
    requested_limit: u64,
) -> BodyReadResult {
    let body = OwnedBodyArgument::new(handle, roc_host());
    match body.state().read(requested_limit) {
        Ok(ReadResult::Chunk(bytes)) => body_read_chunk(seamless_chunk(bytes)),
        Ok(ReadResult::End) => body_read_end(),
        Err(error) => body_read_error(to_host_error(error)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_request_body_read_all(
    handle: *mut u64,
    requested_limit: u64,
) -> BodyReadAllResult {
    let body = OwnedBodyArgument::new(handle, roc_host());
    match body.state().read_all(requested_limit, roc_host()) {
        Ok(bytes) => body_read_all_ok(bytes),
        Err(error) => body_read_all_error(to_host_error(error)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::roc_platform_abi::{make_roc_host, RocHost};
    use futures::stream;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::thread;
    use std::time::{Duration, Instant};

    fn test_host() -> &'static RocHost {
        let mut host = make_roc_host(core::ptr::null_mut());
        host.roc_alloc = roc_alloc::roc_alloc;
        host.roc_dealloc = roc_alloc::roc_dealloc;
        host.roc_realloc = roc_alloc::roc_realloc;
        Box::leak(Box::new(host))
    }

    fn bytes(value: &'static [u8]) -> Result<Bytes, PumpError> {
        Ok(Bytes::from_static(value))
    }

    fn test_idle_timeout() -> Duration {
        Duration::from_secs(1)
    }

    fn new_registration(hard_limit: u64, declared_length: Option<u64>) -> BodyRegistration {
        register(hard_limit, 1, declared_length, test_host())
    }

    fn wait_until_reader_is_blocking(handle: &BodyHandle) {
        let deadline = Instant::now() + Duration::from_secs(1);
        loop {
            match handle.state().receiver.try_lock() {
                Err(TryLockError::WouldBlock) => return,
                Err(TryLockError::Poisoned(_)) => panic!("reader mutex poisoned"),
                Ok(guard) => drop(guard),
            }
            assert!(
                Instant::now() < deadline,
                "reader did not begin blocking within one second"
            );
            thread::sleep(Duration::from_millis(1));
        }
    }

    fn owned_list_bytes(list: RocListWith<u8, false>, host: &RocHost) -> Vec<u8> {
        let result = list.as_slice().to_vec();
        unsafe { list.decref(host) };
        result
    }

    fn read_on_thread(handle: &BodyHandle, requested_limit: u64) -> Result<ReadResult, BodyError> {
        let handle = handle.clone();
        thread::spawn(move || handle.read(requested_limit))
            .join()
            .expect("reader thread panicked")
    }

    async fn pump_and_read_all(
        hard_limit: u64,
        requested_limit: u64,
        frames: Vec<Result<Bytes, PumpError>>,
        chunk_size: usize,
        declared_length: Option<u64>,
    ) -> Result<Vec<u8>, BodyError> {
        let registration = new_registration(hard_limit, declared_length);
        let reader_handle = registration.handle.clone();
        let reader = thread::spawn(move || {
            reader_handle
                .read_all(requested_limit)
                .map(|list| owned_list_bytes(list, unsafe { &*reader_handle.host }))
        });
        registration
            .pump
            .run(stream::iter(frames), chunk_size, test_idle_timeout())
            .await;
        reader.join().expect("reader thread panicked")
    }

    #[tokio::test(flavor = "current_thread")]
    async fn limits_and_fragmented_read_all_are_preserved() {
        assert_eq!(
            pump_and_read_all(5, 5, vec![bytes(b"abc"), bytes(b"de")], 2, Some(5),).await,
            Ok(b"abcde".to_vec())
        );
        assert_eq!(
            pump_and_read_all(5, 5, vec![bytes(b"abc"), bytes(b"def")], 8, None,).await,
            Err(BodyError::TooLarge {
                limit_bytes: 5,
                received_at_least: 6,
            })
        );
        assert_eq!(
            pump_and_read_all(0, 0, vec![], 8, None).await,
            Ok(Vec::new())
        );
        assert_eq!(
            pump_and_read_all(0, 0, vec![bytes(b"x")], 8, None).await,
            Err(BodyError::TooLarge {
                limit_bytes: 0,
                received_at_least: 1,
            })
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn narrowed_limits_and_chunk_splitting_remain_stable() {
        let registration = new_registration(100, None);
        let reader_handle = registration.handle.clone();
        let reader = thread::spawn(move || {
            assert_eq!(
                reader_handle.read(3),
                Ok(ReadResult::Chunk(Bytes::from_static(b"ab")))
            );
            reader_handle.read(100)
        });
        registration
            .pump
            .run(stream::iter(vec![bytes(b"abcd")]), 2, test_idle_timeout())
            .await;
        assert_eq!(
            reader.join().unwrap(),
            Err(BodyError::TooLarge {
                limit_bytes: 3,
                received_at_least: 4,
            })
        );

        let registration = new_registration(100, None);
        let reader_handle = registration.handle.clone();
        let reader = thread::spawn(move || {
            assert_eq!(
                reader_handle.read(100),
                Ok(ReadResult::Chunk(Bytes::from_static(b"abcdef")))
            );
            reader_handle
                .read_all(3)
                .map(|list| owned_list_bytes(list, unsafe { &*reader_handle.host }))
        });
        registration
            .pump
            .run(stream::iter(vec![bytes(b"abcdef")]), 8, test_idle_timeout())
            .await;
        assert_eq!(
            reader.join().unwrap(),
            Err(BodyError::TooLarge {
                limit_bytes: 3,
                received_at_least: 6,
            })
        );

        let registration = new_registration(100, None);
        let reader_handle = registration.handle.clone();
        let reader = thread::spawn(move || {
            let mut chunks = Vec::new();
            loop {
                match reader_handle.read(100).unwrap() {
                    ReadResult::Chunk(chunk) => chunks.push(chunk),
                    ReadResult::End => return chunks,
                }
            }
        });
        registration
            .pump
            .run(
                stream::iter(vec![bytes(b""), bytes(b"abcdefg")]),
                3,
                test_idle_timeout(),
            )
            .await;
        assert_eq!(
            reader.join().unwrap(),
            vec![
                Bytes::from_static(b"abc"),
                Bytes::from_static(b"def"),
                Bytes::from_static(b"g"),
            ]
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn partial_read_then_read_all_returns_the_remainder() {
        let registration = new_registration(100, Some(6));
        let reader_handle = registration.handle.clone();
        let reader = thread::spawn(move || {
            assert_eq!(
                reader_handle.read(100),
                Ok(ReadResult::Chunk(Bytes::from_static(b"ab")))
            );
            let list = reader_handle.read_all(100).unwrap();
            owned_list_bytes(list, unsafe { &*reader_handle.host })
        });
        registration
            .pump
            .run(stream::iter(vec![bytes(b"abcdef")]), 2, test_idle_timeout())
            .await;
        assert_eq!(reader.join().unwrap(), b"cdef");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn end_and_source_errors_are_stable() {
        let registration = new_registration(10, None);
        registration
            .pump
            .run(stream::empty(), 4, test_idle_timeout())
            .await;
        assert_eq!(
            read_on_thread(&registration.handle, 10),
            Ok(ReadResult::End)
        );
        assert_eq!(
            read_on_thread(&registration.handle, 10),
            Ok(ReadResult::End)
        );

        let registration = new_registration(10, None);
        registration
            .pump
            .run(
                stream::iter(vec![Err(PumpError::InvalidBody("bad frame".into()))]),
                4,
                test_idle_timeout(),
            )
            .await;
        let expected = Err(BodyError::InvalidBody("bad frame".into()));
        assert_eq!(read_on_thread(&registration.handle, 10), expected);
        assert_eq!(
            read_on_thread(&registration.handle, 10),
            Err(BodyError::InvalidBody("bad frame".into()))
        );

        let registration = new_registration(10, None);
        registration
            .pump
            .run(
                stream::iter(vec![Err(PumpError::ClientDisconnected)]),
                4,
                test_idle_timeout(),
            )
            .await;
        assert_eq!(
            read_on_thread(&registration.handle, 10),
            Err(BodyError::ClientDisconnected)
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn stalled_body_becomes_a_stable_typed_timeout() {
        let registration = new_registration(10, Some(1));
        let reader_handle = registration.handle.clone();
        let reader = thread::spawn(move || reader_handle.read(10));

        registration
            .pump
            .run(stream::pending(), 4, Duration::from_millis(20))
            .await;

        assert_eq!(reader.join().unwrap(), Err(BodyError::Timeout));
        assert_eq!(
            read_on_thread(&registration.handle, 10),
            Err(BodyError::Timeout)
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn nonempty_progress_resets_the_body_idle_deadline() {
        let registration = new_registration(10, Some(2));
        let reader_handle = registration.handle.clone();
        let reader = thread::spawn(move || {
            let first = reader_handle.read(10);
            let second = reader_handle.read(10);
            let end = reader_handle.read(10);
            (first, second, end)
        });
        let frames = stream::once(async {
            tokio::time::sleep(Duration::from_millis(15)).await;
            bytes(b"a")
        })
        .chain(stream::once(async {
            tokio::time::sleep(Duration::from_millis(15)).await;
            bytes(b"b")
        }));

        registration
            .pump
            .run(frames, 4, Duration::from_millis(25))
            .await;

        assert_eq!(
            reader.join().unwrap(),
            (
                Ok(ReadResult::Chunk(Bytes::from_static(b"a"))),
                Ok(ReadResult::Chunk(Bytes::from_static(b"b"))),
                Ok(ReadResult::End),
            )
        );
    }

    #[test]
    fn expiry_and_cancellation_wake_blocked_readers() {
        for (cancel, expected) in [
            (false, BodyError::RequestFinished),
            (true, BodyError::Cancelled),
        ] {
            let registration = new_registration(10, None);
            let reader_handle = registration.handle.clone();
            let reader = thread::spawn(move || reader_handle.read(10));
            wait_until_reader_is_blocking(&registration.handle);
            if cancel {
                registration.handle.cancel();
            } else {
                registration.handle.expire();
            }
            assert_eq!(reader.join().unwrap(), Err(expected));
        }
    }

    #[test]
    fn a_second_simultaneous_reader_is_rejected() {
        let registration = new_registration(10, None);
        let first_handle = registration.handle.clone();
        let first = thread::spawn(move || first_handle.read(10));
        wait_until_reader_is_blocking(&registration.handle);
        assert_eq!(registration.handle.read(10), Err(BodyError::ConcurrentRead));
        registration.handle.cancel();
        assert_eq!(first.join().unwrap(), Err(BodyError::Cancelled));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn bounded_channel_backpressures_and_cancellation_stops_the_pump() {
        let registration = new_registration(100, None);
        let handle = registration.handle;
        let pump = tokio::spawn(registration.pump.run(
            stream::iter(vec![bytes(b"a"), bytes(b"b"), bytes(b"c")]),
            1,
            test_idle_timeout(),
        ));
        tokio::time::sleep(Duration::from_millis(10)).await;
        assert!(!pump.is_finished());
        assert_eq!(
            thread::spawn({
                let handle = handle.clone();
                move || handle.read(100)
            })
            .join()
            .unwrap(),
            Ok(ReadResult::Chunk(Bytes::from_static(b"a")))
        );
        handle.cancel();
        tokio::time::timeout(Duration::from_secs(1), pump)
            .await
            .expect("cancelled pump did not stop")
            .expect("pump task panicked");

        let registration = new_registration(100, None);
        let handle = registration.handle;
        let pump = tokio::spawn(
            registration
                .pump
                .run(stream::pending(), 1, test_idle_timeout()),
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
        assert!(!pump.is_finished());
        handle.cancel();
        tokio::time::timeout(Duration::from_secs(1), pump)
            .await
            .expect("cancelled network wait did not stop")
            .expect("pump task panicked");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn concurrent_bodies_keep_independent_state() {
        let first = new_registration(100, Some(5));
        let second = new_registration(100, Some(6));
        let first_handle = first.handle.clone();
        let second_handle = second.handle.clone();
        let first_reader = thread::spawn(move || {
            owned_list_bytes(first_handle.read_all(100).unwrap(), unsafe {
                &*first_handle.host
            })
        });
        let second_reader = thread::spawn(move || {
            owned_list_bytes(second_handle.read_all(100).unwrap(), unsafe {
                &*second_handle.host
            })
        });

        tokio::join!(
            first
                .pump
                .run(stream::iter(vec![bytes(b"first")]), 2, test_idle_timeout(),),
            second
                .pump
                .run(stream::iter(vec![bytes(b"second")]), 2, test_idle_timeout(),),
        );
        assert_eq!(first_reader.join().unwrap(), b"first");
        assert_eq!(second_reader.join().unwrap(), b"second");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn split_chunk_keeps_the_original_bytes_pointer() {
        let original = Bytes::from_static(b"0123456789");
        let sliced = original.slice(3..8);
        let expected_ptr = sliced.as_ptr();
        let registration = new_registration(100, Some(5));
        let reader_handle = registration.handle.clone();
        let reader = thread::spawn(move || reader_handle.read(100).unwrap());
        registration
            .pump
            .run(stream::iter(vec![Ok(sliced)]), 100, test_idle_timeout())
            .await;
        let ReadResult::Chunk(chunk) = reader.join().unwrap() else {
            panic!("expected chunk");
        };
        assert_eq!(chunk.as_ptr(), expected_ptr);
        let list = seamless_chunk(chunk);
        assert_eq!(list.elements, expected_ptr.cast_mut());
        unsafe { list.decref(test_host()) };
    }

    struct DropOwner {
        bytes: &'static [u8],
        drops: Arc<AtomicUsize>,
    }

    impl AsRef<[u8]> for DropOwner {
        fn as_ref(&self) -> &[u8] {
            self.bytes
        }
    }

    impl Drop for DropOwner {
        fn drop(&mut self) {
            self.drops.fetch_add(1, Ordering::AcqRel);
        }
    }

    #[test]
    fn seamless_chunk_and_derived_slice_drop_owner_exactly_once() {
        let drops = Arc::new(AtomicUsize::new(0));
        let bytes = Bytes::from_owner(DropOwner {
            bytes: b"abcdef",
            drops: Arc::clone(&drops),
        });
        let list = seamless_chunk(bytes);
        unsafe { list.incref(1) };
        let derived = RocListWith {
            elements: unsafe { list.elements.add(2) },
            length: 3,
            capacity_or_alloc_ptr: list.capacity_or_alloc_ptr,
        };
        validate_seamless_range(&derived);
        unsafe { list.decref(test_host()) };
        assert_eq!(drops.load(Ordering::Acquire), 0);
        assert_eq!(derived.as_slice(), b"cde");
        unsafe { derived.decref(test_host()) };
        assert_eq!(drops.load(Ordering::Acquire), 1);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn read_all_copies_each_fragment_directly_into_the_roc_list() {
        let before = COPIED_PAYLOAD_BYTES.load(Ordering::Acquire);
        let result = pump_and_read_all(
            32,
            32,
            vec![bytes(b"abc"), bytes(b"def"), bytes(b"ghi")],
            3,
            Some(9),
        )
        .await
        .unwrap();
        assert_eq!(result, b"abcdefghi");
        assert!(
            COPIED_PAYLOAD_BYTES.load(Ordering::Acquire) >= before + result.len(),
            "instrumentation must observe each direct payload copy"
        );
    }

    #[cfg(debug_assertions)]
    #[test]
    fn partial_read_all_allocation_is_released_on_error() {
        let mut output = RocBytesBuilder::new(0, 3, test_host());
        output.extend(b"abc").unwrap();
        let allocation = output.base;
        assert!(roc_alloc::debug_is_live(allocation));
        assert_eq!(
            output.extend(b"d"),
            Err(BodyError::TooLarge {
                limit_bytes: 3,
                received_at_least: 4,
            })
        );
        drop(output);
        assert!(!roc_alloc::debug_is_live(allocation));
    }
}
