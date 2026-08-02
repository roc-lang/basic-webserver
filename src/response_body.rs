//! Internal response data and fixed-capacity reusable output frames.
//!
//! Ordinary responses retain their existing `Bytes` representation. Native
//! streaming facilities can instead transfer an owned pooled frame through
//! Hyper and recover its vector from `Drop`, without allocating a per-frame
//! ownership adapter.

use crate::compression::ResumableBrotli;
use bytes::{Buf, Bytes};
use hyper::body::{Body, Frame, SizeHint};
use std::io;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};

#[derive(Debug)]
pub(crate) enum ServerData {
    Bytes(Bytes),
    Pooled(PooledResponseFrame),
}

impl ServerData {
    pub(crate) fn empty() -> Self {
        Self::Bytes(Bytes::new())
    }

    pub(crate) fn is_pooled(&self) -> bool {
        matches!(self, Self::Pooled(_))
    }

    #[cfg(test)]
    pub(crate) fn into_bytes(self) -> Result<Bytes, Self> {
        match self {
            Self::Bytes(bytes) => Ok(bytes),
            pooled => Err(pooled),
        }
    }

    pub(crate) fn split_bytes_to(&mut self, count: usize) -> Self {
        match self {
            Self::Bytes(bytes) => Self::Bytes(bytes.split_to(count)),
            Self::Pooled(_) => panic!("pooled response frames must remain owned while in flight"),
        }
    }
}

impl From<Bytes> for ServerData {
    fn from(bytes: Bytes) -> Self {
        Self::Bytes(bytes)
    }
}

impl From<PooledResponseFrame> for ServerData {
    fn from(frame: PooledResponseFrame) -> Self {
        Self::Pooled(frame)
    }
}

impl Buf for ServerData {
    fn remaining(&self) -> usize {
        match self {
            Self::Bytes(bytes) => bytes.remaining(),
            Self::Pooled(frame) => frame.remaining(),
        }
    }

    fn chunk(&self) -> &[u8] {
        match self {
            Self::Bytes(bytes) => bytes.chunk(),
            Self::Pooled(frame) => frame.chunk(),
        }
    }

    fn advance(&mut self, count: usize) {
        match self {
            Self::Bytes(bytes) => bytes.advance(count),
            Self::Pooled(frame) => frame.advance(count),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct ResponseFramePoolStats {
    pub(crate) slots: usize,
    pub(crate) frame_bytes: usize,
    pub(crate) free_slots: usize,
    pub(crate) reserved_slots: usize,
    pub(crate) transport_owned_slots: usize,
    pub(crate) in_use_slots: usize,
    pub(crate) high_water_slots: usize,
}

struct PoolState {
    free: Vec<Vec<u8>>,
    slots: usize,
    frame_bytes: usize,
    reserved: usize,
    transport_owned: usize,
    high_water: usize,
    waiter: Option<Waker>,
}

#[derive(Clone)]
pub(crate) struct ResponseFramePool {
    state: Arc<Mutex<PoolState>>,
}

impl ResponseFramePool {
    pub(crate) fn new(slots: usize, frame_bytes: usize) -> Self {
        assert!(slots > 0, "a response frame pool needs at least one slot");
        assert!(frame_bytes > 0, "response frames must not be empty");
        let mut free = Vec::with_capacity(slots);
        for _ in 0..slots {
            free.push(vec![0; frame_bytes]);
        }
        Self {
            state: Arc::new(Mutex::new(PoolState {
                free,
                slots,
                frame_bytes,
                reserved: 0,
                transport_owned: 0,
                high_water: 0,
                waiter: None,
            })),
        }
    }

    pub(crate) fn poll_reserve(&self, context: &Context<'_>) -> Poll<ResponseFrameReservation> {
        let mut state = self.state.lock().expect("response frame pool poisoned");
        let Some(buffer) = state.free.pop() else {
            state.waiter = Some(context.waker().clone());
            return Poll::Pending;
        };
        state.reserved += 1;
        state.high_water = state.high_water.max(state.reserved + state.transport_owned);
        drop(state);
        Poll::Ready(ResponseFrameReservation {
            pool: self.clone(),
            buffer: Some(buffer),
        })
    }

    pub(crate) fn stats(&self) -> ResponseFramePoolStats {
        let state = self.state.lock().expect("response frame pool poisoned");
        ResponseFramePoolStats {
            slots: state.slots,
            frame_bytes: state.frame_bytes,
            free_slots: state.free.len(),
            reserved_slots: state.reserved,
            transport_owned_slots: state.transport_owned,
            in_use_slots: state.reserved + state.transport_owned,
            high_water_slots: state.high_water,
        }
    }

    fn commit_reservation(&self) {
        let mut state = self.state.lock().expect("response frame pool poisoned");
        state.reserved -= 1;
        state.transport_owned += 1;
    }

    fn release_reservation(&self, buffer: Vec<u8>) {
        self.release(buffer, true);
    }

    fn release_transport_owned(&self, buffer: Vec<u8>) {
        self.release(buffer, false);
    }

    fn release(&self, mut buffer: Vec<u8>, reservation: bool) {
        let mut state = self.state.lock().expect("response frame pool poisoned");
        assert!(buffer.capacity() >= state.frame_bytes);
        buffer.resize(state.frame_bytes, 0);
        if reservation {
            state.reserved -= 1;
        } else {
            state.transport_owned -= 1;
        }
        state.free.push(buffer);
        let waiter = state.waiter.take();
        drop(state);
        if let Some(waiter) = waiter {
            waiter.wake();
        }
    }
}

pub(crate) struct ResponseFrameReservation {
    pool: ResponseFramePool,
    buffer: Option<Vec<u8>>,
}

impl ResponseFrameReservation {
    pub(crate) fn output_mut(&mut self) -> &mut [u8] {
        self.buffer
            .as_mut()
            .expect("live response frame reservation owns its buffer")
            .as_mut_slice()
    }

    pub(crate) fn commit(mut self, output_bytes: usize) -> PooledResponseFrame {
        let buffer = self
            .buffer
            .take()
            .expect("live response frame reservation owns its buffer");
        assert!(output_bytes <= buffer.len());
        self.pool.commit_reservation();
        PooledResponseFrame {
            pool: self.pool.clone(),
            buffer: Some(buffer),
            offset: 0,
            output_bytes,
        }
    }
}

impl Drop for ResponseFrameReservation {
    fn drop(&mut self) {
        if let Some(buffer) = self.buffer.take() {
            self.pool.release_reservation(buffer);
        }
    }
}

pub(crate) struct PooledResponseFrame {
    pool: ResponseFramePool,
    buffer: Option<Vec<u8>>,
    offset: usize,
    output_bytes: usize,
}

impl std::fmt::Debug for PooledResponseFrame {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PooledResponseFrame")
            .field("remaining", &self.remaining())
            .field("capacity", &self.buffer.as_ref().map(Vec::capacity))
            .finish()
    }
}

impl Buf for PooledResponseFrame {
    fn remaining(&self) -> usize {
        self.output_bytes - self.offset
    }

    fn chunk(&self) -> &[u8] {
        &self
            .buffer
            .as_ref()
            .expect("live pooled response frame owns its buffer")[self.offset..self.output_bytes]
    }

    fn advance(&mut self, count: usize) {
        assert!(count <= self.remaining());
        self.offset += count;
    }
}

impl Drop for PooledResponseFrame {
    fn drop(&mut self) {
        if let Some(buffer) = self.buffer.take() {
            self.pool.release_transport_owned(buffer);
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum SseCompression {
    Identity,
    Brotli {
        quality: u32,
        window_bits: u32,
    },
    RecycledBrotli {
        quality: u32,
        window_bits: u32,
        max_recycled_bytes: usize,
    },
}

/// Pull source for already validated and canonically framed SSE items.
///
/// The eventual Roc machine adapter implements this boundary. It cannot write
/// directly to the socket: the body reserves bounded host output before it
/// polls the next item or advances compression.
pub(crate) trait SseItemSource: Send {
    fn poll_item(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
    ) -> Poll<io::Result<Option<Bytes>>>;

    /// Acknowledge that the current logical item has been copied into identity
    /// frames or completely FLUSHed into Brotli frames owned by the host.
    ///
    /// A retained Roc source uses this boundary to move its returned machine
    /// from draining to parked and only then arm the declared next wake. It is
    /// never called for an item abandoned by error or cancellation.
    ///
    /// This transition must be infallible and nonblocking. Any waiter or timer
    /// capacity it needs must be admitted before the item is returned. It must
    /// not synchronously advance Roc.
    fn item_drained(self: Pin<&mut Self>);

    fn cancel(self: Pin<&mut Self>) {}
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct SseBodyStats {
    pub(crate) frames: ResponseFramePoolStats,
    pub(crate) pending_item_bytes: usize,
    pub(crate) source_ended: bool,
    pub(crate) active_encoder: bool,
    pub(crate) finished: bool,
    pub(crate) failed: bool,
    pub(crate) cancelled: bool,
}

#[derive(Default)]
struct SseLifecycle {
    pending_item_bytes: usize,
    source_ended: bool,
    active_encoder: bool,
    finished: bool,
    failed: bool,
    cancelled: bool,
}

#[derive(Clone)]
pub(crate) struct SseBodyHandle {
    pool: ResponseFramePool,
    lifecycle: Arc<Mutex<SseLifecycle>>,
}

impl SseBodyHandle {
    pub(crate) fn stats(&self) -> SseBodyStats {
        let lifecycle = self.lifecycle.lock().expect("SSE lifecycle poisoned");
        SseBodyStats {
            frames: self.pool.stats(),
            pending_item_bytes: lifecycle.pending_item_bytes,
            source_ended: lifecycle.source_ended,
            active_encoder: lifecycle.active_encoder,
            finished: lifecycle.finished,
            failed: lifecycle.failed,
            cancelled: lifecycle.cancelled,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SsePhase {
    PollSource,
    Process,
    Flush,
    Finish,
    Done,
}

/// Production-internal bounded SSE response body.
///
/// This is deliberately below the public Roc API decision. It proves the host
/// transaction: source polling, fixed frame reservation, optional resumable
/// Brotli, Hyper ownership, normal FINISH, and cancellation-without-FINISH.
pub(crate) struct SseBody {
    source: Option<Pin<Box<dyn SseItemSource>>>,
    pool: ResponseFramePool,
    max_item_bytes: usize,
    encoder: Option<ResumableBrotli>,
    reservation: Option<ResponseFrameReservation>,
    item: Bytes,
    input_offset: usize,
    phase: SsePhase,
    lifecycle: Arc<Mutex<SseLifecycle>>,
}

impl SseBody {
    pub(crate) fn new(
        source: impl SseItemSource + 'static,
        max_item_bytes: usize,
        frame_slots: usize,
        frame_bytes: usize,
        compression: SseCompression,
    ) -> (SseBodyHandle, Self) {
        assert!(
            max_item_bytes > 0,
            "SSE items must have a finite byte limit"
        );
        let pool = ResponseFramePool::new(frame_slots, frame_bytes);
        let lifecycle = Arc::new(Mutex::new(SseLifecycle {
            active_encoder: !matches!(compression, SseCompression::Identity),
            ..SseLifecycle::default()
        }));
        let encoder = match compression {
            SseCompression::Identity => None,
            SseCompression::Brotli {
                quality,
                window_bits,
            } => Some(ResumableBrotli::new(quality, window_bits)),
            SseCompression::RecycledBrotli {
                quality,
                window_bits,
                max_recycled_bytes,
            } => Some(ResumableBrotli::new_recycled(
                quality,
                window_bits,
                max_recycled_bytes,
            )),
        };
        let handle = SseBodyHandle {
            pool: pool.clone(),
            lifecycle: Arc::clone(&lifecycle),
        };
        (
            handle,
            Self {
                source: Some(Box::pin(source)),
                pool,
                max_item_bytes,
                encoder,
                reservation: None,
                item: Bytes::new(),
                input_offset: 0,
                phase: SsePhase::PollSource,
                lifecycle,
            },
        )
    }

    fn set_pending_item_bytes(&self, bytes: usize) {
        self.lifecycle
            .lock()
            .expect("SSE lifecycle poisoned")
            .pending_item_bytes = bytes;
    }

    fn finish_normally(&mut self) {
        self.encoder.take();
        self.reservation.take();
        self.source.take();
        self.item = Bytes::new();
        self.input_offset = 0;
        self.phase = SsePhase::Done;
        let mut lifecycle = self.lifecycle.lock().expect("SSE lifecycle poisoned");
        lifecycle.pending_item_bytes = 0;
        lifecycle.active_encoder = false;
        lifecycle.finished = true;
    }

    fn fail(&mut self) {
        if let Some(source) = &mut self.source {
            source.as_mut().cancel();
        }
        self.encoder.take();
        self.reservation.take();
        self.source.take();
        self.item = Bytes::new();
        self.input_offset = 0;
        self.phase = SsePhase::Done;
        let mut lifecycle = self.lifecycle.lock().expect("SSE lifecycle poisoned");
        lifecycle.pending_item_bytes = 0;
        lifecycle.active_encoder = false;
        lifecycle.failed = true;
    }

    fn cancel(&mut self) {
        if self.phase == SsePhase::Done {
            return;
        }
        if let Some(source) = &mut self.source {
            source.as_mut().cancel();
        }
        self.encoder.take();
        self.reservation.take();
        self.source.take();
        self.item = Bytes::new();
        self.input_offset = 0;
        self.phase = SsePhase::Done;
        let mut lifecycle = self.lifecycle.lock().expect("SSE lifecycle poisoned");
        lifecycle.pending_item_bytes = 0;
        lifecycle.active_encoder = false;
        lifecycle.cancelled = true;
    }

    fn reservation(&self, context: &Context<'_>) -> Poll<ResponseFrameReservation> {
        self.pool.poll_reserve(context)
    }

    fn acknowledge_item(&mut self) {
        self.item = Bytes::new();
        self.input_offset = 0;
        self.set_pending_item_bytes(0);
        self.phase = SsePhase::PollSource;
        self.source
            .as_mut()
            .expect("live SSE body has a source")
            .as_mut()
            .item_drained();
    }
}

impl Body for SseBody {
    type Data = ServerData;
    type Error = io::Error;

    fn poll_frame(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        let this = self.get_mut();
        loop {
            match this.phase {
                SsePhase::PollSource => {
                    let reservation = match this.reservation(context) {
                        Poll::Ready(reservation) => reservation,
                        Poll::Pending => return Poll::Pending,
                    };
                    let source = this.source.as_mut().expect("live SSE body has a source");
                    match source.as_mut().poll_item(context) {
                        Poll::Ready(Ok(Some(item))) => {
                            if item.len() > this.max_item_bytes {
                                drop(reservation);
                                let error = io::Error::new(
                                    io::ErrorKind::InvalidData,
                                    "framed SSE item exceeds its configured byte limit",
                                );
                                this.fail();
                                return Poll::Ready(Some(Err(error)));
                            }
                            this.reservation = Some(reservation);
                            this.item = item;
                            this.input_offset = 0;
                            this.set_pending_item_bytes(this.item.len());
                            this.phase = SsePhase::Process;
                        }
                        Poll::Ready(Ok(None)) => {
                            this.reservation = Some(reservation);
                            this.lifecycle
                                .lock()
                                .expect("SSE lifecycle poisoned")
                                .source_ended = true;
                            if this.encoder.is_some() {
                                this.phase = SsePhase::Finish;
                            } else {
                                this.finish_normally();
                            }
                        }
                        Poll::Ready(Err(error)) => {
                            drop(reservation);
                            this.fail();
                            return Poll::Ready(Some(Err(error)));
                        }
                        Poll::Pending => {
                            drop(reservation);
                            return Poll::Pending;
                        }
                    }
                }
                SsePhase::Process => {
                    let mut reservation = if let Some(reservation) = this.reservation.take() {
                        reservation
                    } else {
                        match this.reservation(context) {
                            Poll::Ready(reservation) => reservation,
                            Poll::Pending => return Poll::Pending,
                        }
                    };
                    let mut identity_complete = false;
                    let output_bytes = if let Some(encoder) = &mut this.encoder {
                        match encoder.process(
                            &this.item,
                            &mut this.input_offset,
                            reservation.output_mut(),
                        ) {
                            Ok(step) => {
                                if step.complete {
                                    this.phase = SsePhase::Flush;
                                }
                                step.output_written
                            }
                            Err(error) => {
                                drop(reservation);
                                this.fail();
                                return Poll::Ready(Some(Err(error)));
                            }
                        }
                    } else {
                        let remaining = this.item.len() - this.input_offset;
                        let count = remaining.min(reservation.output_mut().len());
                        reservation.output_mut()[..count].copy_from_slice(
                            &this.item[this.input_offset..this.input_offset + count],
                        );
                        this.input_offset += count;
                        if this.input_offset == this.item.len() {
                            identity_complete = true;
                        } else {
                            this.set_pending_item_bytes(this.item.len() - this.input_offset);
                        }
                        count
                    };
                    if output_bytes == 0 {
                        drop(reservation);
                        if identity_complete {
                            this.acknowledge_item();
                        }
                        continue;
                    }
                    if this.encoder.is_some() {
                        this.set_pending_item_bytes(this.item.len() - this.input_offset);
                    }
                    let frame = reservation.commit(output_bytes);
                    if identity_complete {
                        this.acknowledge_item();
                    }
                    return Poll::Ready(Some(Ok(Frame::data(ServerData::from(frame)))));
                }
                SsePhase::Flush => {
                    let mut reservation = match this.reservation(context) {
                        Poll::Ready(reservation) => reservation,
                        Poll::Pending => return Poll::Pending,
                    };
                    let step = match this
                        .encoder
                        .as_mut()
                        .expect("Brotli flush needs an encoder")
                        .flush(reservation.output_mut())
                    {
                        Ok(step) => step,
                        Err(error) => {
                            drop(reservation);
                            this.fail();
                            return Poll::Ready(Some(Err(error)));
                        }
                    };
                    if step.output_written == 0 {
                        drop(reservation);
                        if step.complete {
                            this.acknowledge_item();
                        }
                        continue;
                    }
                    let frame = reservation.commit(step.output_written);
                    if step.complete {
                        this.acknowledge_item();
                    }
                    return Poll::Ready(Some(Ok(Frame::data(ServerData::from(frame)))));
                }
                SsePhase::Finish => {
                    let mut reservation = if let Some(reservation) = this.reservation.take() {
                        reservation
                    } else {
                        match this.reservation(context) {
                            Poll::Ready(reservation) => reservation,
                            Poll::Pending => return Poll::Pending,
                        }
                    };
                    let step = match this
                        .encoder
                        .as_mut()
                        .expect("Brotli finish needs an encoder")
                        .finish(reservation.output_mut())
                    {
                        Ok(step) => step,
                        Err(error) => {
                            drop(reservation);
                            this.fail();
                            return Poll::Ready(Some(Err(error)));
                        }
                    };
                    if step.complete {
                        this.finish_normally();
                    }
                    if step.output_written == 0 {
                        drop(reservation);
                        continue;
                    }
                    return Poll::Ready(Some(Ok(Frame::data(ServerData::from(
                        reservation.commit(step.output_written),
                    )))));
                }
                SsePhase::Done => return Poll::Ready(None),
            }
        }
    }

    fn is_end_stream(&self) -> bool {
        self.phase == SsePhase::Done
    }

    fn size_hint(&self) -> SizeHint {
        SizeHint::new()
    }
}

impl Drop for SseBody {
    fn drop(&mut self) {
        self.cancel();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;
    use std::io::Read;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::task::{Wake, Waker};

    struct CountWake(AtomicUsize);

    impl Wake for CountWake {
        fn wake(self: Arc<Self>) {
            self.0.fetch_add(1, Ordering::Relaxed);
        }

        fn wake_by_ref(self: &Arc<Self>) {
            self.0.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn ready<T>(poll: Poll<T>) -> T {
        match poll {
            Poll::Ready(value) => value,
            Poll::Pending => panic!("reservation unexpectedly pending"),
        }
    }

    struct ScriptedSource {
        items: VecDeque<Bytes>,
        cancellations: Arc<AtomicUsize>,
        drained: Arc<AtomicUsize>,
        polls: Arc<AtomicUsize>,
    }

    impl SseItemSource for ScriptedSource {
        fn poll_item(
            mut self: Pin<&mut Self>,
            _context: &mut Context<'_>,
        ) -> Poll<io::Result<Option<Bytes>>> {
            self.polls.fetch_add(1, Ordering::Relaxed);
            Poll::Ready(Ok(self.items.pop_front()))
        }

        fn cancel(self: Pin<&mut Self>) {
            self.cancellations.fetch_add(1, Ordering::Relaxed);
        }

        fn item_drained(self: Pin<&mut Self>) {
            assert_eq!(
                self.polls.load(Ordering::Relaxed),
                self.drained.load(Ordering::Relaxed) + 1
            );
            self.drained.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn scripted_source(
        items: Vec<Bytes>,
    ) -> (
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        ScriptedSource,
    ) {
        let cancellations = Arc::new(AtomicUsize::new(0));
        let drained = Arc::new(AtomicUsize::new(0));
        let polls = Arc::new(AtomicUsize::new(0));
        (
            Arc::clone(&cancellations),
            Arc::clone(&drained),
            Arc::clone(&polls),
            ScriptedSource {
                items: items.into(),
                cancellations,
                drained,
                polls,
            },
        )
    }

    fn decode_partial(input: &[u8]) -> Vec<u8> {
        let mut decoded = Vec::new();
        let _ = brotli::Decompressor::new(input, 4096).read_to_end(&mut decoded);
        decoded
    }

    #[test]
    fn pooled_frame_returns_capacity_and_wakes_waiter() {
        let pool = ResponseFramePool::new(1, 64);
        let wake_count = Arc::new(CountWake(AtomicUsize::new(0)));
        let waker = Waker::from(Arc::clone(&wake_count));
        let context = Context::from_waker(&waker);
        let mut reservation = ready(pool.poll_reserve(&context));
        reservation.output_mut()[..7].copy_from_slice(b"encoded");
        let mut data = ServerData::from(reservation.commit(7));
        assert_eq!(pool.stats().reserved_slots, 0);
        assert_eq!(pool.stats().transport_owned_slots, 1);
        assert_eq!(data.chunk(), b"encoded");
        data.advance(3);
        assert_eq!(data.chunk(), b"oded");
        assert!(pool.poll_reserve(&context).is_pending());
        drop(data);
        assert_eq!(wake_count.0.load(Ordering::Relaxed), 1);
        assert_eq!(
            pool.stats(),
            ResponseFramePoolStats {
                slots: 1,
                frame_bytes: 64,
                free_slots: 1,
                reserved_slots: 0,
                transport_owned_slots: 0,
                in_use_slots: 0,
                high_water_slots: 1,
            }
        );
    }

    #[test]
    fn abandoned_reservation_returns_capacity() {
        let pool = ResponseFramePool::new(1, 64);
        let waker = futures::task::noop_waker();
        let context = Context::from_waker(&waker);
        drop(ready(pool.poll_reserve(&context)));
        assert_eq!(pool.stats().free_slots, 1);
        assert_eq!(pool.stats().in_use_slots, 0);
    }

    #[test]
    fn sse_body_resumes_identity_and_brotli_through_one_tiny_frame() {
        let event = Bytes::from(
            [
                b"event: datastar-patch-elements\n".as_slice(),
                b"data: selector #todos\n",
                b"data: elements <ul>",
                "<li>bounded stream</li>".repeat(2048).as_bytes(),
                b"</ul>\n\n",
            ]
            .concat(),
        );

        for compression in [
            SseCompression::Identity,
            SseCompression::Brotli {
                quality: 1,
                window_bits: 11,
            },
            SseCompression::RecycledBrotli {
                quality: 1,
                window_bits: 11,
                max_recycled_bytes: 256 * 1024,
            },
            SseCompression::Brotli {
                quality: 3,
                window_bits: 12,
            },
        ] {
            let (cancellations, drained, polls, source) = scripted_source(vec![event.clone()]);
            let (handle, mut body) = SseBody::new(source, 128 * 1024, 1, 7, compression);
            let waker = futures::task::noop_waker();
            let mut context = Context::from_waker(&waker);
            let mut output = Vec::new();
            let mut frames = 0;
            loop {
                match Pin::new(&mut body).poll_frame(&mut context) {
                    Poll::Ready(Some(Ok(frame))) => {
                        let data = frame.into_data().expect("SSE body emits data");
                        assert!(data.remaining() <= 7);
                        if handle.stats().pending_item_bytes > 0 {
                            assert_eq!(drained.load(Ordering::Relaxed), 0);
                        }
                        output.extend_from_slice(data.chunk());
                        frames += 1;
                        drop(data);
                    }
                    Poll::Ready(Some(Err(error))) => panic!("SSE body failed: {error}"),
                    Poll::Ready(None) => break,
                    Poll::Pending => panic!("ready source and released frame must progress"),
                }
            }

            assert!(frames > 1);
            let decoded = match compression {
                SseCompression::Identity => output,
                SseCompression::Brotli { .. } | SseCompression::RecycledBrotli { .. } => {
                    decode_partial(&output)
                }
            };
            assert_eq!(decoded, event);
            assert_eq!(cancellations.load(Ordering::Relaxed), 0);
            assert_eq!(drained.load(Ordering::Relaxed), 1);
            assert_eq!(polls.load(Ordering::Relaxed), 2);
            assert_eq!(
                handle.stats(),
                SseBodyStats {
                    frames: ResponseFramePoolStats {
                        slots: 1,
                        frame_bytes: 7,
                        free_slots: 1,
                        reserved_slots: 0,
                        transport_owned_slots: 0,
                        in_use_slots: 0,
                        high_water_slots: 1,
                    },
                    pending_item_bytes: 0,
                    source_ended: true,
                    active_encoder: false,
                    finished: true,
                    failed: false,
                    cancelled: false,
                }
            );
        }
    }

    #[test]
    fn dropping_backpressured_sse_body_aborts_encoder_and_releases_state() {
        let event = Bytes::from(vec![b'x'; 64 * 1024]);
        let (cancellations, drained, _polls, source) = scripted_source(vec![event]);
        let (handle, mut body) = SseBody::new(
            source,
            128 * 1024,
            1,
            7,
            SseCompression::Brotli {
                quality: 3,
                window_bits: 12,
            },
        );
        let waker = futures::task::noop_waker();
        let mut context = Context::from_waker(&waker);
        let frame = ready(Pin::new(&mut body).poll_frame(&mut context))
            .expect("body should emit one frame")
            .expect("encoding should succeed")
            .into_data()
            .expect("SSE body emits data");
        assert!(Pin::new(&mut body).poll_frame(&mut context).is_pending());
        assert_eq!(handle.stats().frames.in_use_slots, 1);
        assert_eq!(handle.stats().frames.reserved_slots, 0);
        assert_eq!(handle.stats().frames.transport_owned_slots, 1);
        assert!(handle.stats().pending_item_bytes > 0);
        assert_eq!(drained.load(Ordering::Relaxed), 0);

        drop(body);
        assert_eq!(cancellations.load(Ordering::Relaxed), 1);
        assert!(handle.stats().cancelled);
        assert!(!handle.stats().active_encoder);
        assert_eq!(handle.stats().pending_item_bytes, 0);
        assert_eq!(handle.stats().frames.in_use_slots, 1);

        drop(frame);
        assert_eq!(handle.stats().frames.in_use_slots, 0);
        assert_eq!(handle.stats().frames.free_slots, 1);
    }

    #[test]
    fn sse_body_acknowledges_each_item_before_polling_the_next() {
        let first = Bytes::from_static(b"data: first\n\n");
        let second = Bytes::from_static(b"data: second\n\n");
        let (cancellations, drained, polls, source) =
            scripted_source(vec![first.clone(), second.clone()]);
        let (_handle, mut body) = SseBody::new(source, 1024, 1, 5, SseCompression::Identity);
        let waker = futures::task::noop_waker();
        let mut context = Context::from_waker(&waker);
        let mut output = Vec::new();

        loop {
            match Pin::new(&mut body).poll_frame(&mut context) {
                Poll::Ready(Some(Ok(frame))) => {
                    let data = frame.into_data().expect("SSE body emits data");
                    output.extend_from_slice(data.chunk());
                    drop(data);
                }
                Poll::Ready(Some(Err(error))) => panic!("SSE body failed: {error}"),
                Poll::Ready(None) => break,
                Poll::Pending => panic!("ready source and released frame must progress"),
            }
        }

        assert_eq!(output, [first.as_ref(), second.as_ref()].concat());
        assert_eq!(drained.load(Ordering::Relaxed), 2);
        assert_eq!(polls.load(Ordering::Relaxed), 3);
        assert_eq!(cancellations.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn oversized_sse_item_fails_before_encoding_and_releases_reservation() {
        let (cancellations, drained, _polls, source) =
            scripted_source(vec![Bytes::from_static(b"too large")]);
        let (handle, mut body) = SseBody::new(source, 4, 1, 7, SseCompression::Identity);
        let waker = futures::task::noop_waker();
        let mut context = Context::from_waker(&waker);
        let error = ready(Pin::new(&mut body).poll_frame(&mut context))
            .expect("oversized item should produce one error")
            .expect_err("oversized item must be rejected");
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
        assert_eq!(cancellations.load(Ordering::Relaxed), 1);
        assert_eq!(drained.load(Ordering::Relaxed), 0);
        let stats = handle.stats();
        assert!(stats.failed);
        assert!(!stats.cancelled);
        assert_eq!(stats.pending_item_bytes, 0);
        assert_eq!(stats.frames.reserved_slots, 0);
        assert_eq!(stats.frames.transport_owned_slots, 0);
        assert_eq!(stats.frames.free_slots, 1);
        assert!(ready(Pin::new(&mut body).poll_frame(&mut context)).is_none());
    }
}
