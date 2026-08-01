//! Disposable host-transport feasibility components.
//!
//! This crate deliberately imports the platform's real compression module so
//! measurements exercise the pinned encoder and configuration rather than a
//! lookalike. It is not linked into the production host.

#[path = "../../../src/compression.rs"]
mod host_compression;

use brotli::enc::encode::{
    BrotliEncoderDestroyInstance, BrotliEncoderOperation, BrotliEncoderParameter,
    BrotliEncoderStateStruct,
};
use brotli::enc::{
    interface, Allocator, BrotliAlloc, InputPair, InputReferenceMut, SliceWrapper, SliceWrapperMut,
    StandardAlloc, StaticCommand,
};
use bytes::Bytes;
use host_compression::{ContentCoding, ContentEncoder};
use hyper::body::{Body, Frame, SizeHint};
use std::any::TypeId;
use std::collections::VecDeque;
use std::io::{self, Write};
use std::mem;
use std::pin::Pin;
use std::ptr::{self, NonNull};
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};

/// The production Brotli settings under test: quality 4, 256 KiB window.
pub const BROTLI_QUALITY: u32 = 4;
pub const BROTLI_WINDOW_BITS: u32 = 18;

const RECYCLER_SLOTS: usize = 32;

/// Measurements owned by a per-encoder bounded Brotli scratch recycler.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RecyclerStats {
    pub allocation_requests: u64,
    pub cache_hits: u64,
    pub system_allocations: u64,
    pub frees: u64,
    pub uncached_frees: u64,
    pub cached_blocks: usize,
    pub cached_bytes: usize,
    pub peak_cached_bytes: usize,
}

struct CachedBlock {
    type_id: TypeId,
    pointer: NonNull<u8>,
    len: usize,
    bytes: usize,
    drop_block: unsafe fn(NonNull<u8>, usize),
}

// A cached pointer always came from a `Box<[T]>` where T was Send and is only
// recovered as that same T by the owning encoder's allocator.
unsafe impl Send for CachedBlock {}

impl CachedBlock {
    fn from_box<T: Send + 'static>(data: Box<[T]>) -> Self {
        assert!(!data.is_empty());
        let len = data.len();
        let bytes = len
            .checked_mul(mem::size_of::<T>())
            .expect("allocated Brotli block size fits usize");
        let raw = Box::into_raw(data);
        let pointer = NonNull::new(raw.cast::<T>().cast::<u8>())
            .expect("non-empty Box has a non-null data pointer");
        Self {
            type_id: TypeId::of::<T>(),
            pointer,
            len,
            bytes,
            drop_block: drop_cached_block::<T>,
        }
    }

    fn matches<T: 'static>(&self, len: usize) -> bool {
        self.type_id == TypeId::of::<T>() && self.len == len
    }

    unsafe fn into_box<T: 'static>(self) -> Box<[T]> {
        assert!(self.matches::<T>(self.len));
        // SAFETY: `matches` proves the TypeId and length are identical to the
        // allocation captured by `from_box`, and removing the cache entry
        // transfers its sole ownership to this Box.
        unsafe {
            Box::from_raw(ptr::slice_from_raw_parts_mut(
                self.pointer.cast::<T>().as_ptr(),
                self.len,
            ))
        }
    }
}

unsafe fn drop_cached_block<T>(pointer: NonNull<u8>, len: usize) {
    // SAFETY: this monomorphized function is stored only alongside a pointer
    // created from `Box<[T]>` and its original length.
    unsafe {
        drop(Box::from_raw(ptr::slice_from_raw_parts_mut(
            pointer.cast::<T>().as_ptr(),
            len,
        )));
    }
}

/// Allocated memory returned to the Brotli crate.
///
/// The Option permits the empty value required by the crate's allocation
/// interfaces without manufacturing a typed dangling pointer.
pub struct RecycledMemory<T>(Option<Box<[T]>>);

impl<T> Default for RecycledMemory<T> {
    fn default() -> Self {
        Self(None)
    }
}

impl<T> SliceWrapper<T> for RecycledMemory<T> {
    fn slice(&self) -> &[T] {
        self.0.as_deref().unwrap_or(&[])
    }
}

impl<T> SliceWrapperMut<T> for RecycledMemory<T> {
    fn slice_mut(&mut self) -> &mut [T] {
        self.0.as_deref_mut().unwrap_or(&mut [])
    }
}

/// Per-stream, fixed-slot allocator which recycles Brotli's transient scratch.
///
/// It never caches more than `max_cached_bytes`, and never has more than
/// `RECYCLER_SLOTS` blocks. A cache miss uses the system allocator; an
/// over-limit free immediately releases the block.
pub struct RecyclingAlloc {
    blocks: [Option<CachedBlock>; RECYCLER_SLOTS],
    max_cached_bytes: usize,
    stats: RecyclerStats,
}

impl RecyclingAlloc {
    pub fn new(max_cached_bytes: usize) -> Self {
        Self {
            blocks: std::array::from_fn(|_| None),
            max_cached_bytes,
            stats: RecyclerStats::default(),
        }
    }

    pub fn stats(&self) -> RecyclerStats {
        self.stats
    }
}

impl Drop for RecyclingAlloc {
    fn drop(&mut self) {
        for block in &mut self.blocks {
            if let Some(block) = block.take() {
                // SAFETY: each entry carries the destructor for its original
                // typed Box allocation and is owned solely by this cache.
                unsafe { (block.drop_block)(block.pointer, block.len) };
            }
        }
    }
}

impl<T> Allocator<T> for RecyclingAlloc
where
    T: Clone + Default + Send + 'static,
{
    type AllocatedMemory = RecycledMemory<T>;

    fn alloc_cell(&mut self, len: usize) -> Self::AllocatedMemory {
        self.stats.allocation_requests += 1;
        if len == 0 {
            return RecycledMemory::default();
        }
        if let Some(index) = self
            .blocks
            .iter()
            .position(|block| block.as_ref().is_some_and(|block| block.matches::<T>(len)))
        {
            let block = self.blocks[index]
                .take()
                .expect("matching cache entry exists");
            self.stats.cache_hits += 1;
            self.stats.cached_blocks -= 1;
            self.stats.cached_bytes -= block.bytes;
            // SAFETY: the TypeId and length match T and len, and taking the
            // slot transferred the cache's unique ownership here.
            let mut data = unsafe { block.into_box::<T>() };
            for item in &mut data {
                *item = T::default();
            }
            return RecycledMemory(Some(data));
        }

        self.stats.system_allocations += 1;
        RecycledMemory(Some(vec![T::default(); len].into_boxed_slice()))
    }

    fn free_cell(&mut self, mut data: Self::AllocatedMemory) {
        self.stats.frees += 1;
        let Some(data) = data.0.take() else {
            return;
        };
        if data.is_empty() {
            return;
        }
        let block = CachedBlock::from_box(data);
        let within_byte_limit = self
            .stats
            .cached_bytes
            .checked_add(block.bytes)
            .is_some_and(|bytes| bytes <= self.max_cached_bytes);
        if within_byte_limit {
            if let Some(slot) = self.blocks.iter_mut().find(|slot| slot.is_none()) {
                self.stats.cached_blocks += 1;
                self.stats.cached_bytes += block.bytes;
                self.stats.peak_cached_bytes =
                    self.stats.peak_cached_bytes.max(self.stats.cached_bytes);
                *slot = Some(block);
                return;
            }
        }

        self.stats.uncached_frees += 1;
        // SAFETY: the block still owns its original allocation and carries
        // the corresponding typed destructor.
        unsafe { (block.drop_block)(block.pointer, block.len) };
    }
}

impl BrotliAlloc for RecyclingAlloc {}

#[derive(Debug)]
struct SegmentSink {
    bytes: Vec<u8>,
    limit: usize,
}

impl SegmentSink {
    fn new(limit: usize) -> Self {
        Self {
            bytes: Vec::with_capacity(limit.min(4096)),
            limit,
        }
    }

    fn take(&mut self) -> Bytes {
        Bytes::from(std::mem::take(&mut self.bytes))
    }
}

impl Write for SegmentSink {
    fn write(&mut self, input: &[u8]) -> io::Result<usize> {
        let next = self
            .bytes
            .len()
            .checked_add(input.len())
            .filter(|next| *next <= self.limit)
            .ok_or_else(|| io::Error::other("bounded Brotli segment output exhausted"))?;
        self.bytes.reserve(next - self.bytes.len());
        self.bytes.extend_from_slice(input);
        Ok(input.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// A persistent Brotli stream using the exact encoder configuration currently
/// owned by `src/compression.rs`. Each call performs a real Brotli flush and
/// returns only bytes produced since the previous flush.
pub struct PersistentBrotli {
    encoder: ContentEncoder<SegmentSink>,
}

/// Low-level alternative which separates FLUSH, FINISH, and abort.
///
/// Unlike `CompressorWriter`, dropping this value destroys the encoder state
/// without attempting to emit a Brotli tail. `finish` propagates all encoder
/// and output-limit failures. This uses public-but-low-level crate APIs, so API
/// stability remains a release gate.
struct EncoderCore<Alloc: BrotliAlloc> {
    state: Option<BrotliEncoderStateStruct<Alloc>>,
    max_segment_bytes: usize,
    output: Vec<u8>,
}

/// Result of advancing one Brotli operation into caller-owned bounded output.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct EncoderStep {
    pub input_consumed: usize,
    pub output_written: usize,
    pub complete: bool,
}

impl<Alloc: BrotliAlloc> EncoderCore<Alloc> {
    fn new(max_segment_bytes: usize, quality: u32, window_bits: u32, allocator: Alloc) -> Self {
        assert!(quality <= 11, "Brotli quality must be in 0..=11");
        assert!(
            (10..=24).contains(&window_bits),
            "standard Brotli window bits must be in 10..=24"
        );
        let mut state = BrotliEncoderStateStruct::new(allocator);
        assert!(state.set_parameter(BrotliEncoderParameter::BROTLI_PARAM_QUALITY, quality));
        assert!(state.set_parameter(BrotliEncoderParameter::BROTLI_PARAM_LGWIN, window_bits));
        Self {
            state: Some(state),
            max_segment_bytes,
            output: Vec::with_capacity(max_segment_bytes.min(4096)),
        }
    }

    fn encode_event(&mut self, framed_event: &[u8]) -> io::Result<Bytes> {
        Ok(Bytes::copy_from_slice(
            self.encode_event_reusable(framed_event)?,
        ))
    }

    /// Encode and flush one event into storage retained by this encoder.
    ///
    /// The returned bytes are valid until the next mutable operation. A body
    /// adapter must copy them into an already-reserved frame or otherwise
    /// transfer ownership before calling this encoder again.
    fn encode_event_reusable(&mut self, framed_event: &[u8]) -> io::Result<&[u8]> {
        self.output.clear();
        Self::operation(
            self.state.as_mut().expect("live encoder has state"),
            self.max_segment_bytes,
            BrotliEncoderOperation::BROTLI_OPERATION_PROCESS,
            framed_event,
            &mut self.output,
        )?;
        Self::operation(
            self.state.as_mut().expect("live encoder has state"),
            self.max_segment_bytes,
            BrotliEncoderOperation::BROTLI_OPERATION_FLUSH,
            &[],
            &mut self.output,
        )?;
        Ok(&self.output)
    }

    fn finish(&mut self) -> io::Result<Bytes> {
        self.output.clear();
        Self::operation(
            self.state.as_mut().expect("live encoder has state"),
            self.max_segment_bytes,
            BrotliEncoderOperation::BROTLI_OPERATION_FINISH,
            &[],
            &mut self.output,
        )?;
        Ok(Bytes::from(std::mem::take(&mut self.output)))
    }

    fn operation(
        state: &mut BrotliEncoderStateStruct<Alloc>,
        max_segment_bytes: usize,
        operation: BrotliEncoderOperation,
        input: &[u8],
        encoded: &mut Vec<u8>,
    ) -> io::Result<()> {
        let mut available_in = input.len();
        let mut input_offset = 0;
        let mut total_out = Some(0);
        let mut callback = |_data: &mut interface::PredictionModeContextMap<InputReferenceMut>,
                            _commands: &mut [StaticCommand],
                            _input: InputPair,
                            _allocator: &mut Alloc| {};

        loop {
            let before_input = available_in;
            let before_output = encoded.len();
            let remaining = max_segment_bytes
                .checked_sub(encoded.len())
                .ok_or_else(|| io::Error::other("bounded Brotli segment output exhausted"))?;
            if remaining == 0 {
                return Err(io::Error::other("bounded Brotli segment output exhausted"));
            }
            let chunk_bytes = remaining.min(4096);
            let mut output = [0_u8; 4096];
            let mut available_out = chunk_bytes;
            let mut output_offset = 0;
            let valid = state.compress_stream(
                operation,
                &mut available_in,
                input,
                &mut input_offset,
                &mut available_out,
                &mut output[..chunk_bytes],
                &mut output_offset,
                &mut total_out,
                &mut callback,
            );
            if !valid {
                return Err(io::Error::other("Brotli streaming encoder rejected input"));
            }
            encoded.extend_from_slice(&output[..output_offset]);

            let complete = match operation {
                BrotliEncoderOperation::BROTLI_OPERATION_PROCESS => {
                    available_in == 0 && !state.has_more_output()
                }
                BrotliEncoderOperation::BROTLI_OPERATION_FLUSH => available_in == 0
                    && !state.has_more_output()
                    && state.stream_state_
                        == brotli::enc::encode::BrotliEncoderStreamState::BROTLI_STREAM_PROCESSING,
                BrotliEncoderOperation::BROTLI_OPERATION_FINISH => state.is_finished(),
                BrotliEncoderOperation::BROTLI_OPERATION_EMIT_METADATA => unreachable!(),
            };
            if complete {
                return Ok(());
            }
            if before_input == available_in && before_output == encoded.len() {
                return Err(io::Error::other("Brotli encoder made no progress"));
            }
        }
    }

    fn operation_step(
        state: &mut BrotliEncoderStateStruct<Alloc>,
        operation: BrotliEncoderOperation,
        input: &[u8],
        input_offset: &mut usize,
        output: &mut [u8],
    ) -> io::Result<EncoderStep> {
        if output.is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "Brotli output reservation must not be empty",
            ));
        }
        if *input_offset > input.len() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "Brotli input offset exceeds the supplied input",
            ));
        }

        let before_input_offset = *input_offset;
        let mut available_in = input.len() - *input_offset;
        let mut available_out = output.len();
        let mut output_offset = 0;
        let mut total_out = Some(0);
        let mut callback = |_data: &mut interface::PredictionModeContextMap<InputReferenceMut>,
                            _commands: &mut [StaticCommand],
                            _input: InputPair,
                            _allocator: &mut Alloc| {};
        let valid = state.compress_stream(
            operation,
            &mut available_in,
            input,
            input_offset,
            &mut available_out,
            output,
            &mut output_offset,
            &mut total_out,
            &mut callback,
        );
        if !valid {
            return Err(io::Error::other("Brotli streaming encoder rejected input"));
        }

        let complete =
            match operation {
                BrotliEncoderOperation::BROTLI_OPERATION_PROCESS => {
                    available_in == 0 && !state.has_more_output()
                }
                BrotliEncoderOperation::BROTLI_OPERATION_FLUSH => available_in == 0
                    && !state.has_more_output()
                    && state.stream_state_
                        == brotli::enc::encode::BrotliEncoderStreamState::BROTLI_STREAM_PROCESSING,
                BrotliEncoderOperation::BROTLI_OPERATION_FINISH => state.is_finished(),
                BrotliEncoderOperation::BROTLI_OPERATION_EMIT_METADATA => unreachable!(),
            };
        let step = EncoderStep {
            input_consumed: *input_offset - before_input_offset,
            output_written: output_offset,
            complete,
        };
        if !step.complete && step.input_consumed == 0 && step.output_written == 0 {
            return Err(io::Error::other("Brotli encoder made no progress"));
        }
        Ok(step)
    }
}

impl<Alloc: BrotliAlloc> Drop for EncoderCore<Alloc> {
    fn drop(&mut self) {
        if let Some(mut state) = self.state.take() {
            BrotliEncoderDestroyInstance(&mut state);
        }
    }
}

pub struct ExplicitBrotli {
    core: EncoderCore<StandardAlloc>,
}

/// Persistent Brotli encoder which advances only into output capacity already
/// reserved by the body. PROCESS, FLUSH, and FINISH may each span many frames.
pub struct ResumableBrotli {
    core: EncoderCore<StandardAlloc>,
}

impl ResumableBrotli {
    pub fn with_settings(quality: u32, window_bits: u32) -> Self {
        Self {
            // The reusable vector is unused by the step API. Keep the limit at
            // one so the shared lifecycle container does not reserve a large
            // speculative segment.
            core: EncoderCore::new(1, quality, window_bits, StandardAlloc::default()),
        }
    }

    pub fn process(
        &mut self,
        input: &[u8],
        input_offset: &mut usize,
        output: &mut [u8],
    ) -> io::Result<EncoderStep> {
        EncoderCore::operation_step(
            self.core.state.as_mut().expect("live encoder has state"),
            BrotliEncoderOperation::BROTLI_OPERATION_PROCESS,
            input,
            input_offset,
            output,
        )
    }

    pub fn flush(&mut self, output: &mut [u8]) -> io::Result<EncoderStep> {
        let mut input_offset = 0;
        EncoderCore::operation_step(
            self.core.state.as_mut().expect("live encoder has state"),
            BrotliEncoderOperation::BROTLI_OPERATION_FLUSH,
            &[],
            &mut input_offset,
            output,
        )
    }

    pub fn finish(&mut self, output: &mut [u8]) -> io::Result<EncoderStep> {
        let mut input_offset = 0;
        EncoderCore::operation_step(
            self.core.state.as_mut().expect("live encoder has state"),
            BrotliEncoderOperation::BROTLI_OPERATION_FINISH,
            &[],
            &mut input_offset,
            output,
        )
    }
}

impl ExplicitBrotli {
    pub fn new(max_segment_bytes: usize) -> Self {
        Self::with_settings(max_segment_bytes, BROTLI_QUALITY, BROTLI_WINDOW_BITS)
    }

    /// Compatibility constructor used by the real-browser harness.
    pub fn new_with_parameters(max_segment_bytes: usize, quality: u32, window_bits: u32) -> Self {
        Self::with_settings(max_segment_bytes, quality, window_bits)
    }

    pub fn with_settings(max_segment_bytes: usize, quality: u32, window_bits: u32) -> Self {
        Self {
            core: EncoderCore::new(
                max_segment_bytes,
                quality,
                window_bits,
                StandardAlloc::default(),
            ),
        }
    }

    pub fn encode_event(&mut self, framed_event: &[u8]) -> io::Result<Bytes> {
        self.core.encode_event(framed_event)
    }

    pub fn encode_event_reusable(&mut self, framed_event: &[u8]) -> io::Result<&[u8]> {
        self.core.encode_event_reusable(framed_event)
    }

    pub fn finish(mut self) -> io::Result<Bytes> {
        self.core.finish()
    }
}

/// Lifecycle-safe low-level encoder with reusable output and bounded scratch.
pub struct RecyclingBrotli {
    core: EncoderCore<RecyclingAlloc>,
}

impl RecyclingBrotli {
    pub fn with_settings(
        max_segment_bytes: usize,
        quality: u32,
        window_bits: u32,
        max_recycled_bytes: usize,
    ) -> Self {
        Self {
            core: EncoderCore::new(
                max_segment_bytes,
                quality,
                window_bits,
                RecyclingAlloc::new(max_recycled_bytes),
            ),
        }
    }

    pub fn encode_event(&mut self, framed_event: &[u8]) -> io::Result<Bytes> {
        self.core.encode_event(framed_event)
    }

    pub fn encode_event_reusable(&mut self, framed_event: &[u8]) -> io::Result<&[u8]> {
        self.core.encode_event_reusable(framed_event)
    }

    pub fn recycler_stats(&self) -> RecyclerStats {
        self.core
            .state
            .as_ref()
            .expect("live encoder has state")
            .m8
            .stats()
    }

    pub fn finish(mut self) -> io::Result<Bytes> {
        self.core.finish()
    }
}

impl PersistentBrotli {
    pub fn new(max_segment_bytes: usize) -> io::Result<Self> {
        Ok(Self {
            encoder: ContentEncoder::new(
                ContentCoding::Brotli,
                SegmentSink::new(max_segment_bytes),
            )?,
        })
    }

    pub fn encode_event(&mut self, framed_event: &[u8]) -> io::Result<Bytes> {
        self.encoder.write_all(framed_event)?;
        self.encoder.flush()?;
        Ok(self.sink_mut().take())
    }

    pub fn finish(self) -> io::Result<Bytes> {
        let mut sink = self.encoder.finish()?;
        Ok(sink.take())
    }

    fn sink_mut(&mut self) -> &mut SegmentSink {
        match &mut self.encoder {
            ContentEncoder::Brotli(encoder) => encoder.get_mut(),
            _ => unreachable!("PersistentBrotli always selects Brotli"),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ReserveError {
    Backpressured,
    Closed,
}

struct QueuedFrame {
    bytes: Bytes,
    reserved_bytes: usize,
}

struct BodyState {
    queue: VecDeque<QueuedFrame>,
    max_frames: usize,
    max_bytes: usize,
    reserved_frames: usize,
    reserved_bytes: usize,
    closed: bool,
    cancelled: bool,
    body_waker: Option<Waker>,
}

/// Producer-side handle for the bounded body prototype.
#[derive(Clone)]
pub struct BoundedProducer {
    state: Arc<Mutex<BodyState>>,
}

/// A reservation is acquired before compression mutates the persistent
/// encoder. Its conservative byte charge remains live until Hyper consumes the
/// resulting frame.
pub struct Reservation {
    state: Arc<Mutex<BodyState>>,
    reserved_bytes: usize,
    committed: bool,
}

impl BoundedProducer {
    pub fn reserve(&self, worst_case_bytes: usize) -> Result<Reservation, ReserveError> {
        let mut state = self.state.lock().expect("body state mutex is not poisoned");
        if state.cancelled || state.closed {
            return Err(ReserveError::Closed);
        }
        let next_bytes = state
            .reserved_bytes
            .checked_add(worst_case_bytes)
            .ok_or(ReserveError::Backpressured)?;
        if state.reserved_frames >= state.max_frames || next_bytes > state.max_bytes {
            return Err(ReserveError::Backpressured);
        }
        state.reserved_frames += 1;
        state.reserved_bytes = next_bytes;
        drop(state);
        Ok(Reservation {
            state: Arc::clone(&self.state),
            reserved_bytes: worst_case_bytes,
            committed: false,
        })
    }

    pub fn close(&self) {
        let mut state = self.state.lock().expect("body state mutex is not poisoned");
        state.closed = true;
        if let Some(waker) = state.body_waker.take() {
            waker.wake();
        }
    }

    pub fn is_cancelled(&self) -> bool {
        self.state
            .lock()
            .expect("body state mutex is not poisoned")
            .cancelled
    }

    pub fn reserved_bytes(&self) -> usize {
        self.state
            .lock()
            .expect("body state mutex is not poisoned")
            .reserved_bytes
    }
}

impl Reservation {
    pub fn commit(mut self, bytes: Bytes) -> Result<(), ReserveError> {
        assert!(
            bytes.len() <= self.reserved_bytes,
            "encoded output exceeded its pre-encoding reservation"
        );
        let mut state = self.state.lock().expect("body state mutex is not poisoned");
        if state.cancelled || state.closed {
            state.reserved_frames -= 1;
            state.reserved_bytes -= self.reserved_bytes;
            self.committed = true;
            return Err(ReserveError::Closed);
        }
        state.queue.push_back(QueuedFrame {
            bytes,
            reserved_bytes: self.reserved_bytes,
        });
        self.committed = true;
        if let Some(waker) = state.body_waker.take() {
            waker.wake();
        }
        Ok(())
    }
}

impl Drop for Reservation {
    fn drop(&mut self) {
        if self.committed {
            return;
        }
        let mut state = self.state.lock().expect("body state mutex is not poisoned");
        state.reserved_frames -= 1;
        state.reserved_bytes -= self.reserved_bytes;
    }
}

pub struct BoundedBody {
    state: Arc<Mutex<BodyState>>,
}

pub fn bounded_body(max_frames: usize, max_bytes: usize) -> (BoundedProducer, BoundedBody) {
    assert!(max_frames > 0);
    assert!(max_bytes > 0);
    let state = Arc::new(Mutex::new(BodyState {
        queue: VecDeque::with_capacity(max_frames),
        max_frames,
        max_bytes,
        reserved_frames: 0,
        reserved_bytes: 0,
        closed: false,
        cancelled: false,
        body_waker: None,
    }));
    (
        BoundedProducer {
            state: Arc::clone(&state),
        },
        BoundedBody { state },
    )
}

impl Body for BoundedBody {
    type Data = Bytes;
    type Error = io::Error;

    fn poll_frame(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        let mut state = self.state.lock().expect("body state mutex is not poisoned");
        if let Some(frame) = state.queue.pop_front() {
            state.reserved_frames -= 1;
            state.reserved_bytes -= frame.reserved_bytes;
            return Poll::Ready(Some(Ok(Frame::data(frame.bytes))));
        }
        if state.closed || state.cancelled {
            Poll::Ready(None)
        } else {
            state.body_waker = Some(context.waker().clone());
            Poll::Pending
        }
    }

    fn is_end_stream(&self) -> bool {
        let state = self.state.lock().expect("body state mutex is not poisoned");
        (state.closed || state.cancelled) && state.queue.is_empty()
    }

    fn size_hint(&self) -> SizeHint {
        SizeHint::new()
    }
}

impl Drop for BoundedBody {
    fn drop(&mut self) {
        let mut state = self.state.lock().expect("body state mutex is not poisoned");
        state.cancelled = true;
        state.queue.clear();
        state.reserved_frames = 0;
        state.reserved_bytes = 0;
    }
}

/// Deterministic, repetitive Datastar-shaped patch event of approximately the
/// requested framed size. The exact result can be a few bytes larger.
pub fn datastar_event(target_bytes: usize, sequence: usize) -> Vec<u8> {
    let prefix = format!(
        "event: datastar-patch-elements\ndata: selector #todos\ndata: mode replace\ndata: elements <ul data-seq=\"{sequence}\">"
    );
    // Datastar Go v1.2.2 writes a newline for the final data field followed by
    // its `DoubleNewLine` constant, producing three line feeds on the wire.
    let suffix = "</ul>\n\n\n";
    let row = "<li class=\"todo\"><span>write bounded streaming tests</span></li>";
    let mut event = String::with_capacity(target_bytes + row.len());
    event.push_str(&prefix);
    while event.len() + row.len() + suffix.len() < target_bytes {
        event.push_str(row);
    }
    event.push_str(suffix);
    event.into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use http_body_util::BodyExt;
    use std::io::Read;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::Duration;

    fn decode_partial(input: &[u8]) -> Vec<u8> {
        let mut decoded = Vec::new();
        let _ = brotli::Decompressor::new(input, 4096).read_to_end(&mut decoded);
        decoded
    }

    #[test]
    fn every_flush_is_incrementally_decodable() {
        let events = [datastar_event(256, 1), datastar_event(4096, 2)];
        let heartbeat = b": keepalive\n\n".to_vec();
        let mut encoder = PersistentBrotli::new(128 * 1024).unwrap();
        let mut encoded = Vec::new();
        let mut expected = Vec::new();

        for item in [&events[0], &heartbeat, &events[1]] {
            expected.extend_from_slice(item);
            encoded.extend_from_slice(&encoder.encode_event(item).unwrap());
            assert_eq!(decode_partial(&encoded), expected);
        }
        encoded.extend_from_slice(&encoder.finish().unwrap());
        assert_eq!(decode_partial(&encoded), expected);
    }

    #[test]
    fn low_level_encoder_matches_writer_and_can_abort_without_finish() {
        let events = [datastar_event(256, 1), datastar_event(4096, 2)];
        let mut writer = PersistentBrotli::new(128 * 1024).unwrap();
        let mut explicit = ExplicitBrotli::new(128 * 1024);
        let mut writer_bytes = Vec::new();
        let mut explicit_bytes = Vec::new();
        for event in &events {
            writer_bytes.extend_from_slice(&writer.encode_event(event).unwrap());
            explicit_bytes.extend_from_slice(&explicit.encode_event(event).unwrap());
        }
        assert_eq!(writer_bytes, explicit_bytes);
        writer_bytes.extend_from_slice(&writer.finish().unwrap());
        explicit_bytes.extend_from_slice(&explicit.finish().unwrap());
        assert_eq!(writer_bytes, explicit_bytes);

        // Destruction without FINISH is a separate operation and cannot write
        // output because the low-level state owns no writer.
        let mut aborted = ExplicitBrotli::new(128 * 1024);
        let flushed = aborted.encode_event(&events[0]).unwrap();
        drop(aborted);
        assert_eq!(decode_partial(&flushed), events[0]);
    }

    #[test]
    fn low_memory_candidate_profile_flushes_and_finishes() {
        let events = [datastar_event(256, 1), datastar_event(4096, 2)];
        let mut encoder = ExplicitBrotli::new_with_parameters(128 * 1024, 1, 11);
        let mut encoded = Vec::new();
        let mut expected = Vec::new();
        for event in &events {
            expected.extend_from_slice(event);
            encoded.extend_from_slice(&encoder.encode_event(event).unwrap());
            assert_eq!(decode_partial(&encoded), expected);
        }
        let tail = encoder.finish().unwrap();
        assert!(!tail.is_empty());
        encoded.extend_from_slice(&tail);
        assert_eq!(decode_partial(&encoded), expected);
    }

    #[test]
    fn bounded_recycler_matches_standard_encoder_and_reaches_a_steady_state() {
        let events = [
            datastar_event(256, 1),
            datastar_event(4096, 2),
            b": keepalive\n\n".to_vec(),
        ];
        let mut standard = ExplicitBrotli::with_settings(128 * 1024, 4, 18);
        let mut recycled = RecyclingBrotli::with_settings(128 * 1024, 4, 18, 256 * 1024);
        let mut standard_bytes = Vec::new();
        let mut recycled_bytes = Vec::new();

        for event in &events {
            standard_bytes.extend_from_slice(standard.encode_event_reusable(event).unwrap());
            recycled_bytes.extend_from_slice(recycled.encode_event_reusable(event).unwrap());
        }
        assert_eq!(recycled_bytes, standard_bytes);

        for sequence in 3..103 {
            let event = datastar_event(4096, sequence);
            standard_bytes.extend_from_slice(standard.encode_event_reusable(&event).unwrap());
            recycled_bytes.extend_from_slice(recycled.encode_event_reusable(&event).unwrap());
        }
        assert_eq!(recycled_bytes, standard_bytes);
        let after_warmup = recycled.recycler_stats();

        for sequence in 103..203 {
            let event = datastar_event(4096, sequence);
            standard_bytes.extend_from_slice(standard.encode_event_reusable(&event).unwrap());
            recycled_bytes.extend_from_slice(recycled.encode_event_reusable(&event).unwrap());
        }
        assert_eq!(recycled_bytes, standard_bytes);
        let steady = recycled.recycler_stats();
        assert_eq!(
            steady.system_allocations, after_warmup.system_allocations,
            "warmup={after_warmup:?}, steady={steady:?}"
        );
        assert_eq!(steady.uncached_frees, 0);
        assert!(steady.cache_hits > after_warmup.cache_hits);
        assert!(steady.cached_bytes <= 256 * 1024);

        standard_bytes.extend_from_slice(&standard.finish().unwrap());
        recycled_bytes.extend_from_slice(&recycled.finish().unwrap());
        assert_eq!(recycled_bytes, standard_bytes);
    }

    #[test]
    fn recycler_limit_is_enforced_and_abort_does_not_finish() {
        let event = datastar_event(4096, 1);
        let mut recycled = RecyclingBrotli::with_settings(128 * 1024, 4, 18, 0);
        let flushed = recycled.encode_event_reusable(&event).unwrap().to_vec();
        let after_first = recycled.recycler_stats();
        assert_eq!(after_first.cached_bytes, 0);
        assert!(after_first.uncached_frees > 0);
        recycled.encode_event_reusable(&event).unwrap();
        assert!(recycled.recycler_stats().system_allocations > after_first.system_allocations);
        drop(recycled);
        assert_eq!(decode_partial(&flushed), event);
    }

    #[test]
    fn recycler_does_not_change_q1_or_q3_output() {
        let events = [datastar_event(4096, 1), datastar_event(65_536, 2)];
        for (quality, window_bits) in [(1, 11), (3, 12)] {
            let mut standard = ExplicitBrotli::with_settings(256 * 1024, quality, window_bits);
            let mut recycled =
                RecyclingBrotli::with_settings(256 * 1024, quality, window_bits, 256 * 1024);
            let mut standard_bytes = Vec::new();
            let mut recycled_bytes = Vec::new();
            for event in &events {
                standard_bytes.extend_from_slice(standard.encode_event_reusable(event).unwrap());
                recycled_bytes.extend_from_slice(recycled.encode_event_reusable(event).unwrap());
            }
            standard_bytes.extend_from_slice(&standard.finish().unwrap());
            recycled_bytes.extend_from_slice(&recycled.finish().unwrap());
            assert_eq!(recycled_bytes, standard_bytes);
            assert_eq!(decode_partial(&recycled_bytes), events.concat());
        }
    }

    #[derive(Clone)]
    struct SwitchableSink {
        bytes: Arc<Mutex<Vec<u8>>>,
        fail: Arc<AtomicBool>,
    }

    impl Write for SwitchableSink {
        fn write(&mut self, input: &[u8]) -> io::Result<usize> {
            if self.fail.load(Ordering::Acquire) {
                return Err(io::Error::other("injected sink failure"));
            }
            self.bytes.lock().unwrap().extend_from_slice(input);
            Ok(input.len())
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn current_writer_finishes_on_drop_and_swallows_finish_errors() {
        let bytes = Arc::new(Mutex::new(Vec::new()));
        let fail = Arc::new(AtomicBool::new(false));
        let sink = SwitchableSink {
            bytes: Arc::clone(&bytes),
            fail: Arc::clone(&fail),
        };
        let mut encoder = ContentEncoder::new(ContentCoding::Brotli, sink).unwrap();
        encoder.write_all(&datastar_event(256, 1)).unwrap();
        encoder.flush().unwrap();
        let after_flush = bytes.lock().unwrap().len();
        drop(encoder);
        assert!(bytes.lock().unwrap().len() > after_flush);

        let sink = SwitchableSink {
            bytes: Arc::new(Mutex::new(Vec::new())),
            fail: Arc::clone(&fail),
        };
        let mut encoder = ContentEncoder::new(ContentCoding::Brotli, sink).unwrap();
        encoder.write_all(&datastar_event(256, 1)).unwrap();
        encoder.flush().unwrap();
        fail.store(true, Ordering::Release);
        assert!(
            encoder.finish().is_ok(),
            "CompressorWriter::into_inner currently suppresses the injected FINISH error"
        );
    }

    #[test]
    fn low_level_output_limit_fails_closed() {
        let mut encoder = ExplicitBrotli::new(1);
        let error = encoder
            .encode_event(&datastar_event(4096, 1))
            .expect_err("one output byte cannot hold an event and flush");
        assert_eq!(error.kind(), io::ErrorKind::Other);
        drop(encoder);
    }

    #[tokio::test]
    async fn reservation_precedes_encoding_and_bounds_backpressure() {
        let (producer, mut body) = bounded_body(1, 8192);
        let reservation = producer.reserve(8192).unwrap();
        assert_eq!(producer.reserve(1).err(), Some(ReserveError::Backpressured));

        let mut encoder = PersistentBrotli::new(8192).unwrap();
        let encoded = encoder.encode_event(&datastar_event(4096, 1)).unwrap();
        reservation.commit(encoded.clone()).unwrap();
        assert_eq!(producer.reserved_bytes(), 8192);
        assert_eq!(producer.reserve(1).err(), Some(ReserveError::Backpressured));

        let frame = body.frame().await.unwrap().unwrap().into_data().unwrap();
        assert_eq!(frame, encoded);
        assert_eq!(producer.reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn resumable_brotli_never_advances_without_one_bounded_frame() {
        const FRAME_BYTES: usize = 7;

        for (quality, window_bits) in [(1, 11), (3, 12)] {
            let event = datastar_event(65_536, quality as usize);
            let (producer, mut body) = bounded_body(1, FRAME_BYTES);
            let mut encoder = ResumableBrotli::with_settings(quality, window_bits);
            let mut input_offset = 0;
            let mut encoded = Vec::new();
            let mut frames = 0;

            loop {
                let reservation = producer.reserve(FRAME_BYTES).unwrap();
                let mut output = [0_u8; FRAME_BYTES];
                let step = encoder
                    .process(&event, &mut input_offset, &mut output)
                    .unwrap();
                if step.output_written == 0 {
                    drop(reservation);
                } else {
                    reservation
                        .commit(Bytes::copy_from_slice(&output[..step.output_written]))
                        .unwrap();
                    assert_eq!(producer.reserved_bytes(), FRAME_BYTES);
                    assert_eq!(producer.reserve(1).err(), Some(ReserveError::Backpressured));
                    let frame = body.frame().await.unwrap().unwrap().into_data().unwrap();
                    assert!(frame.len() <= FRAME_BYTES);
                    encoded.extend_from_slice(&frame);
                    frames += 1;
                    assert_eq!(producer.reserved_bytes(), 0);
                }
                if step.complete {
                    break;
                }
            }
            assert_eq!(input_offset, event.len());

            loop {
                let reservation = producer.reserve(FRAME_BYTES).unwrap();
                let mut output = [0_u8; FRAME_BYTES];
                let step = encoder.flush(&mut output).unwrap();
                if step.output_written == 0 {
                    drop(reservation);
                } else {
                    reservation
                        .commit(Bytes::copy_from_slice(&output[..step.output_written]))
                        .unwrap();
                    assert_eq!(producer.reserved_bytes(), FRAME_BYTES);
                    let frame = body.frame().await.unwrap().unwrap().into_data().unwrap();
                    assert!(frame.len() <= FRAME_BYTES);
                    encoded.extend_from_slice(&frame);
                    frames += 1;
                    assert_eq!(producer.reserved_bytes(), 0);
                }
                if step.complete {
                    break;
                }
            }

            assert!(frames > 1, "the test must exercise resumable output");
            assert_eq!(decode_partial(&encoded), event);

            loop {
                let reservation = producer.reserve(FRAME_BYTES).unwrap();
                let mut output = [0_u8; FRAME_BYTES];
                let step = encoder.finish(&mut output).unwrap();
                if step.output_written == 0 {
                    drop(reservation);
                } else {
                    reservation
                        .commit(Bytes::copy_from_slice(&output[..step.output_written]))
                        .unwrap();
                    let frame = body.frame().await.unwrap().unwrap().into_data().unwrap();
                    encoded.extend_from_slice(&frame);
                }
                if step.complete {
                    break;
                }
            }
            producer.close();
            assert!(body.frame().await.is_none());
            assert_eq!(decode_partial(&encoded), event);
        }
    }

    #[tokio::test]
    async fn body_drop_cancels_and_releases_all_reservations() {
        let (producer, body) = bounded_body(2, 16 * 1024);
        let reservation = producer.reserve(8192).unwrap();
        reservation
            .commit(Bytes::from_static(b"encoded event"))
            .unwrap();
        assert!(!producer.is_cancelled());
        drop(body);
        assert!(producer.is_cancelled());
        assert_eq!(producer.reserved_bytes(), 0);
        assert_eq!(producer.reserve(1).err(), Some(ReserveError::Closed));
    }

    #[tokio::test]
    async fn event_one_is_observable_before_event_two_exists() {
        let (producer, mut body) = bounded_body(1, 128 * 1024);
        let worker = std::thread::spawn(move || {
            let mut encoder = PersistentBrotli::new(128 * 1024).unwrap();
            let first = datastar_event(4096, 1);
            let reservation = loop {
                if let Ok(reservation) = producer.reserve(128 * 1024) {
                    break reservation;
                }
                std::thread::yield_now();
            };
            reservation
                .commit(encoder.encode_event(&first).unwrap())
                .unwrap();
            std::thread::sleep(Duration::from_millis(100));
            let second = datastar_event(4096, 2);
            let reservation = loop {
                if let Ok(reservation) = producer.reserve(128 * 1024) {
                    break reservation;
                }
                std::thread::yield_now();
            };
            reservation
                .commit(encoder.encode_event(&second).unwrap())
                .unwrap();
            producer.close();
        });

        let started = std::time::Instant::now();
        let first = body.frame().await.unwrap().unwrap().into_data().unwrap();
        assert!(!first.is_empty());
        assert!(started.elapsed() < Duration::from_millis(80));
        let second = body.frame().await.unwrap().unwrap().into_data().unwrap();
        assert!(!second.is_empty());
        assert!(started.elapsed() >= Duration::from_millis(90));
        assert!(body.frame().await.is_none());
        worker.join().unwrap();
    }
}
