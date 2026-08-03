//! Host-owned response content-coding negotiation and encoders.

use brotli::enc::encode::{
    BrotliEncoderDestroyInstance, BrotliEncoderOperation, BrotliEncoderParameter,
    BrotliEncoderStateStruct,
};
use brotli::enc::{
    interface, Allocator, BrotliAlloc, InputPair, InputReferenceMut, SliceWrapper, SliceWrapperMut,
    StandardAlloc, StaticCommand,
};
use brotli::CompressorWriter;
use flate2::write::GzEncoder;
use flate2::Compression;
use hyper::header::{
    ACCEPT_ENCODING, CACHE_CONTROL, CONTENT_ENCODING, CONTENT_LENGTH, CONTENT_RANGE, CONTENT_TYPE,
    ETAG, VARY,
};
use hyper::{HeaderMap, StatusCode};
use std::any::TypeId;
use std::io::{self, Write};
use std::mem;
use std::ptr::{self, NonNull};

pub(crate) const MIN_COMPRESSION_BYTES: u64 = 1024;
pub(crate) const MAX_BUFFERED_COMPRESSION_BYTES: usize = 8 * 1024 * 1024;
const BROTLI_BUFFER_BYTES: usize = 4096;
const BROTLI_QUALITY: u32 = 4;
const BROTLI_WINDOW_BITS: u32 = 18;
const ZSTD_LEVEL: i32 = 3;
// Bound history-dependent encoder memory to the same 256 KiB window as Brotli.
const ZSTD_WINDOW_BITS: u32 = 18;
const BROTLI_RECYCLER_SLOTS: usize = 32;

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

// A cached pointer came from a `Box<[T]>` where T was Send and is recovered
// only as that same T by the owning encoder's allocator.
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
        // allocation captured by `from_box`, and removing the entry transfers
        // its sole ownership to this Box.
        unsafe {
            Box::from_raw(ptr::slice_from_raw_parts_mut(
                self.pointer.cast::<T>().as_ptr(),
                self.len,
            ))
        }
    }
}

unsafe fn drop_cached_block<T>(pointer: NonNull<u8>, len: usize) {
    // SAFETY: this monomorphized function is stored only with a pointer created
    // from `Box<[T]>` and its original length.
    unsafe {
        drop(Box::from_raw(ptr::slice_from_raw_parts_mut(
            pointer.cast::<T>().as_ptr(),
            len,
        )));
    }
}

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

/// Per-stream, fixed-slot allocator for Brotli's transient scratch memory.
pub struct RecyclingAlloc {
    blocks: [Option<CachedBlock>; BROTLI_RECYCLER_SLOTS],
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
                // typed Box allocation and is solely owned by this cache.
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
            // SAFETY: TypeId and length match, and taking the slot transferred
            // the cache's unique ownership here.
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
        // SAFETY: the block owns its original allocation and corresponding
        // typed destructor.
        unsafe { (block.drop_block)(block.pointer, block.len) };
    }
}

impl BrotliAlloc for RecyclingAlloc {}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct BrotliEncoderStep {
    pub(crate) input_consumed: usize,
    pub(crate) output_written: usize,
    pub(crate) complete: bool,
}

/// Persistent Brotli state advanced only into caller-owned output capacity.
///
/// Dropping this value aborts without emitting a tail. `finish` must be driven
/// to completion explicitly on a normal response close.
enum ResumableBrotliState {
    Standard(Option<BrotliEncoderStateStruct<StandardAlloc>>),
    Recycled(Option<BrotliEncoderStateStruct<RecyclingAlloc>>),
}

pub(crate) struct ResumableBrotli {
    state: ResumableBrotliState,
}

impl ResumableBrotli {
    pub(crate) fn new(quality: u32, window_bits: u32) -> Self {
        Self {
            state: ResumableBrotliState::Standard(Some(new_brotli_state(
                quality,
                window_bits,
                StandardAlloc::default(),
            ))),
        }
    }

    pub(crate) fn new_recycled(quality: u32, window_bits: u32, max_recycled_bytes: usize) -> Self {
        Self {
            state: ResumableBrotliState::Recycled(Some(new_brotli_state(
                quality,
                window_bits,
                RecyclingAlloc::new(max_recycled_bytes),
            ))),
        }
    }

    pub(crate) fn process(
        &mut self,
        input: &[u8],
        input_offset: &mut usize,
        output: &mut [u8],
    ) -> io::Result<BrotliEncoderStep> {
        self.operation(
            BrotliEncoderOperation::BROTLI_OPERATION_PROCESS,
            input,
            input_offset,
            output,
        )
    }

    pub(crate) fn flush(&mut self, output: &mut [u8]) -> io::Result<BrotliEncoderStep> {
        let mut input_offset = 0;
        self.operation(
            BrotliEncoderOperation::BROTLI_OPERATION_FLUSH,
            &[],
            &mut input_offset,
            output,
        )
    }

    pub(crate) fn finish(&mut self, output: &mut [u8]) -> io::Result<BrotliEncoderStep> {
        let mut input_offset = 0;
        self.operation(
            BrotliEncoderOperation::BROTLI_OPERATION_FINISH,
            &[],
            &mut input_offset,
            output,
        )
    }

    fn operation(
        &mut self,
        operation: BrotliEncoderOperation,
        input: &[u8],
        input_offset: &mut usize,
        output: &mut [u8],
    ) -> io::Result<BrotliEncoderStep> {
        match &mut self.state {
            ResumableBrotliState::Standard(state) => brotli_operation_step(
                state.as_mut().expect("live encoder has state"),
                operation,
                input,
                input_offset,
                output,
            ),
            ResumableBrotliState::Recycled(state) => brotli_operation_step(
                state.as_mut().expect("live encoder has state"),
                operation,
                input,
                input_offset,
                output,
            ),
        }
    }

    #[cfg(test)]
    pub(crate) fn recycler_stats(&self) -> Option<RecyclerStats> {
        match &self.state {
            ResumableBrotliState::Standard(_) => None,
            ResumableBrotliState::Recycled(state) => {
                Some(state.as_ref().expect("live encoder has state").m8.stats())
            }
        }
    }
}

impl Drop for ResumableBrotli {
    fn drop(&mut self) {
        match &mut self.state {
            ResumableBrotliState::Standard(state) => {
                if let Some(mut state) = state.take() {
                    BrotliEncoderDestroyInstance(&mut state);
                }
            }
            ResumableBrotliState::Recycled(state) => {
                if let Some(mut state) = state.take() {
                    BrotliEncoderDestroyInstance(&mut state);
                }
            }
        }
    }
}

fn new_brotli_state<Alloc: BrotliAlloc>(
    quality: u32,
    window_bits: u32,
    allocator: Alloc,
) -> BrotliEncoderStateStruct<Alloc> {
    assert!(quality <= 11, "Brotli quality must be in 0..=11");
    assert!(
        (10..=24).contains(&window_bits),
        "standard Brotli window bits must be in 10..=24"
    );
    let mut state = BrotliEncoderStateStruct::new(allocator);
    assert!(state.set_parameter(BrotliEncoderParameter::BROTLI_PARAM_QUALITY, quality));
    assert!(state.set_parameter(BrotliEncoderParameter::BROTLI_PARAM_LGWIN, window_bits));
    state
}

fn brotli_operation_step<Alloc: BrotliAlloc>(
    state: &mut BrotliEncoderStateStruct<Alloc>,
    operation: BrotliEncoderOperation,
    input: &[u8],
    input_offset: &mut usize,
    output: &mut [u8],
) -> io::Result<BrotliEncoderStep> {
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

    let complete = match operation {
        BrotliEncoderOperation::BROTLI_OPERATION_PROCESS => {
            available_in == 0 && !state.has_more_output()
        }
        BrotliEncoderOperation::BROTLI_OPERATION_FLUSH => {
            available_in == 0
                && !state.has_more_output()
                && state.stream_state_
                    == brotli::enc::encode::BrotliEncoderStreamState::BROTLI_STREAM_PROCESSING
        }
        BrotliEncoderOperation::BROTLI_OPERATION_FINISH => state.is_finished(),
        BrotliEncoderOperation::BROTLI_OPERATION_EMIT_METADATA => unreachable!(),
    };
    let step = BrotliEncoderStep {
        input_consumed: *input_offset - before_input_offset,
        output_written: output_offset,
        complete,
    };
    if !step.complete && step.input_consumed == 0 && step.output_written == 0 {
        return Err(io::Error::other("Brotli encoder made no progress"));
    }
    Ok(step)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ContentCoding {
    Zstandard,
    Brotli,
    Gzip,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum StreamingContentCoding {
    Identity,
    Brotli,
    NotAcceptable,
}

impl ContentCoding {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Zstandard => "zstd",
            Self::Brotli => "br",
            Self::Gzip => "gzip",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct AcceptedEncodings {
    present: bool,
    zstandard: u16,
    brotli: u16,
    gzip: u16,
    identity: u16,
    identity_explicit: bool,
}

impl AcceptedEncodings {
    pub(crate) fn from_headers(headers: &HeaderMap) -> Self {
        let present = headers.contains_key(ACCEPT_ENCODING);
        if !present {
            return Self {
                present: false,
                zstandard: 0,
                brotli: 0,
                gzip: 0,
                identity: 1000,
                identity_explicit: false,
            };
        }

        let mut zstandard = None;
        let mut brotli = None;
        let mut gzip = None;
        let mut identity = None;
        let mut wildcard = None;
        for value in headers.get_all(ACCEPT_ENCODING) {
            let Ok(value) = value.to_str() else {
                continue;
            };
            for member in value.split(',').filter_map(parse_member) {
                let target = if member.name.eq_ignore_ascii_case("zstd") {
                    &mut zstandard
                } else if member.name.eq_ignore_ascii_case("br") {
                    &mut brotli
                } else if member.name.eq_ignore_ascii_case("gzip")
                    || member.name.eq_ignore_ascii_case("x-gzip")
                {
                    &mut gzip
                } else if member.name.eq_ignore_ascii_case("identity") {
                    &mut identity
                } else if member.name == "*" {
                    &mut wildcard
                } else {
                    continue;
                };
                *target = Some(target.unwrap_or(0).max(member.weight));
            }
        }

        let wildcard_weight = wildcard.unwrap_or(0);
        let identity_explicit = identity.is_some();
        Self {
            present: true,
            zstandard: zstandard.unwrap_or(wildcard_weight),
            brotli: brotli.unwrap_or(wildcard_weight),
            gzip: gzip.unwrap_or(wildcard_weight),
            identity: identity.unwrap_or(if wildcard == Some(0) { 0 } else { 1000 }),
            identity_explicit,
        }
    }

    pub(crate) fn preferred(self) -> Option<ContentCoding> {
        if !self.present {
            return None;
        }

        let mut selected = None;
        let mut selected_weight = 0;
        for (coding, weight) in [
            (ContentCoding::Zstandard, self.zstandard),
            (ContentCoding::Brotli, self.brotli),
            (ContentCoding::Gzip, self.gzip),
        ] {
            if weight > selected_weight {
                selected = Some(coding);
                selected_weight = weight;
            }
        }

        if selected_weight == 0 || (self.identity_explicit && self.identity > selected_weight) {
            None
        } else {
            selected
        }
    }

    /// Select among the representations the streaming body can produce.
    /// Streaming deliberately does not advertise the buffered gzip or zstd
    /// encoders, and must not silently send identity when the client forbids
    /// both available representations.
    pub(crate) fn preferred_streaming(self) -> StreamingContentCoding {
        if !self.present {
            return StreamingContentCoding::Identity;
        }
        if self.brotli != 0 && !(self.identity_explicit && self.identity > self.brotli) {
            StreamingContentCoding::Brotli
        } else if self.identity != 0 {
            StreamingContentCoding::Identity
        } else {
            StreamingContentCoding::NotAcceptable
        }
    }
}

struct EncodingMember<'a> {
    name: &'a str,
    weight: u16,
}

fn parse_member(raw: &str) -> Option<EncodingMember<'_>> {
    let mut parts = raw.split(';');
    let name = parts.next()?.trim();
    if name.is_empty()
        || !name.bytes().all(|byte| {
            byte.is_ascii_alphanumeric()
                || matches!(
                    byte,
                    b'!' | b'#'
                        ..=b'\'' | b'*' | b'+' | b'-' | b'.' | b'^' | b'_' | b'`' | b'|' | b'~'
                )
        })
    {
        return None;
    }
    let mut weight = 1000;
    for parameter in parts {
        let (parameter_name, value) = parameter.trim().split_once('=')?;
        if !parameter_name.trim().eq_ignore_ascii_case("q") {
            return None;
        }
        weight = parse_quality(value.trim())?;
    }
    Some(EncodingMember { name, weight })
}

fn parse_quality(raw: &str) -> Option<u16> {
    let (whole, fractional) = raw.split_once('.').unwrap_or((raw, ""));
    if fractional.len() > 3 || !fractional.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    match whole {
        "0" => {
            let mut value = fractional.parse::<u16>().unwrap_or(0);
            for _ in fractional.len()..3 {
                value *= 10;
            }
            Some(value)
        }
        "1" if fractional.bytes().all(|byte| byte == b'0') => Some(1000),
        _ => None,
    }
}

pub(crate) fn response_is_compressible(
    status: StatusCode,
    headers: &HeaderMap,
    body_bytes: u64,
) -> bool {
    body_bytes >= MIN_COMPRESSION_BYTES
        && !status.is_informational()
        && status != StatusCode::NO_CONTENT
        && status != StatusCode::RESET_CONTENT
        && status != StatusCode::NOT_MODIFIED
        && status != StatusCode::PARTIAL_CONTENT
        && !headers.contains_key(CONTENT_ENCODING)
        && !headers.contains_key(CONTENT_RANGE)
        && !headers.contains_key(ETAG)
        && !headers.contains_key("content-md5")
        && !headers.contains_key("digest")
        && !headers.contains_key("content-digest")
        && !cache_control_has_no_transform(headers)
        && content_type_is_compressible(headers)
}

fn cache_control_has_no_transform(headers: &HeaderMap) -> bool {
    headers.get_all(CACHE_CONTROL).iter().any(|value| {
        value.to_str().ok().is_some_and(|value| {
            value
                .split(',')
                .any(|directive| directive.trim().eq_ignore_ascii_case("no-transform"))
        })
    })
}

fn content_type_is_compressible(headers: &HeaderMap) -> bool {
    let Some(raw) = headers
        .get(CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
    else {
        return true;
    };
    let media_type = raw
        .split(';')
        .next()
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase();
    if media_type == "image/svg+xml" {
        return true;
    }
    if media_type.starts_with("image/")
        || media_type.starts_with("audio/")
        || media_type.starts_with("video/")
        || media_type.starts_with("font/")
    {
        return false;
    }
    !matches!(
        media_type.as_str(),
        "application/gzip"
            | "application/octet-stream"
            | "application/pdf"
            | "application/x-7z-compressed"
            | "application/x-bzip2"
            | "application/x-gzip"
            | "application/x-rar-compressed"
            | "application/zip"
            | "application/zstd"
    )
}

pub(crate) fn vary_on_accept_encoding(headers: &mut HeaderMap) {
    let already_varies = headers.get_all(VARY).iter().any(|value| {
        value.to_str().ok().is_some_and(|value| {
            value.split(',').any(|name| {
                let name = name.trim();
                name == "*" || name.eq_ignore_ascii_case("accept-encoding")
            })
        })
    });
    if !already_varies {
        headers.append(
            VARY,
            hyper::header::HeaderValue::from_static("Accept-Encoding"),
        );
    }
}

pub(crate) fn apply_content_coding(
    headers: &mut HeaderMap,
    coding: ContentCoding,
    encoded_length: Option<usize>,
) {
    vary_on_accept_encoding(headers);
    headers.insert(
        CONTENT_ENCODING,
        hyper::header::HeaderValue::from_static(coding.as_str()),
    );
    if let Some(length) = encoded_length {
        headers.insert(
            CONTENT_LENGTH,
            length
                .to_string()
                .parse()
                .expect("encoded response length is a valid header"),
        );
    } else {
        headers.remove(CONTENT_LENGTH);
    }
}

pub(crate) fn encoded_etag(etag: &str, coding: ContentCoding) -> String {
    match etag.strip_suffix('"') {
        Some(prefix) => format!("{prefix}-{}\"", coding.as_str()),
        None => etag.to_owned(),
    }
}

pub(crate) fn encode_bytes(coding: ContentCoding, input: &[u8]) -> io::Result<Vec<u8>> {
    let encoder = ContentEncoder::new(coding, Vec::with_capacity(input.len().min(64 * 1024)))?;
    encode_all(encoder, input)
}

fn encode_all<W: Write>(mut encoder: ContentEncoder<W>, input: &[u8]) -> io::Result<W> {
    encoder.write_all(input)?;
    encoder.finish()
}

pub(crate) enum ContentEncoder<W: Write> {
    Zstandard(zstd::stream::write::Encoder<'static, W>),
    Brotli(Box<CompressorWriter<W>>),
    Gzip(GzEncoder<W>),
}

impl<W: Write> ContentEncoder<W> {
    pub(crate) fn new(coding: ContentCoding, writer: W) -> io::Result<Self> {
        match coding {
            ContentCoding::Zstandard => {
                let mut encoder = zstd::stream::write::Encoder::new(writer, ZSTD_LEVEL)?;
                encoder.window_log(ZSTD_WINDOW_BITS)?;
                Ok(Self::Zstandard(encoder))
            }
            ContentCoding::Brotli => Ok(Self::Brotli(Box::new(CompressorWriter::new(
                writer,
                BROTLI_BUFFER_BYTES,
                BROTLI_QUALITY,
                BROTLI_WINDOW_BITS,
            )))),
            ContentCoding::Gzip => Ok(Self::Gzip(GzEncoder::new(writer, Compression::default()))),
        }
    }

    pub(crate) fn finish(self) -> io::Result<W> {
        match self {
            Self::Zstandard(encoder) => encoder.finish(),
            Self::Brotli(encoder) => Ok(encoder.into_inner()),
            Self::Gzip(encoder) => encoder.finish(),
        }
    }
}

impl<W: Write> Write for ContentEncoder<W> {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        match self {
            Self::Zstandard(encoder) => encoder.write(buffer),
            Self::Brotli(encoder) => encoder.write(buffer),
            Self::Gzip(encoder) => encoder.write(buffer),
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        match self {
            Self::Zstandard(encoder) => encoder.flush(),
            Self::Brotli(encoder) => encoder.flush(),
            Self::Gzip(encoder) => encoder.flush(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

    fn accepted(value: Option<&str>) -> AcceptedEncodings {
        let mut headers = HeaderMap::new();
        if let Some(value) = value {
            headers.insert(ACCEPT_ENCODING, value.parse().unwrap());
        }
        AcceptedEncodings::from_headers(&headers)
    }

    fn advance_resumable_event(encoder: &mut ResumableBrotli, input: &[u8]) {
        let mut input_offset = 0;
        loop {
            let mut output = [0_u8; 4096];
            let step = encoder
                .process(input, &mut input_offset, &mut output)
                .unwrap();
            if step.complete {
                break;
            }
        }
        loop {
            let mut output = [0_u8; 4096];
            let step = encoder.flush(&mut output).unwrap();
            if step.complete {
                break;
            }
        }
    }

    #[test]
    fn resumable_q1_recycles_transient_scratch_after_warmup() {
        let input = vec![b'x'; 4096];
        let mut encoder = ResumableBrotli::new_recycled(1, 11, 256 * 1024);
        advance_resumable_event(&mut encoder, &input);
        let after_first = encoder.recycler_stats().unwrap();
        assert!(after_first.system_allocations > 0);
        advance_resumable_event(&mut encoder, &input);
        let after_second = encoder.recycler_stats().unwrap();
        assert_eq!(
            after_second.system_allocations,
            after_first.system_allocations
        );
        assert!(after_second.cache_hits > after_first.cache_hits);
        assert!(after_second.cached_bytes <= 256 * 1024);
    }

    #[test]
    fn negotiation_honors_quality_wildcards_and_identity() {
        assert_eq!(accepted(None).preferred(), None);
        assert_eq!(accepted(Some("")).preferred(), None);
        assert_eq!(
            accepted(Some("gzip, br, zstd")).preferred(),
            Some(ContentCoding::Zstandard)
        );
        assert_eq!(
            accepted(Some("gzip, br")).preferred(),
            Some(ContentCoding::Brotli)
        );
        assert_eq!(
            accepted(Some("br;q=0.4, gzip;q=0.8")).preferred(),
            Some(ContentCoding::Gzip)
        );
        assert_eq!(
            accepted(Some("*;q=0.5")).preferred(),
            Some(ContentCoding::Zstandard)
        );
        assert_eq!(
            accepted(Some("zstd;q=0, br;q=0, gzip;q=0")).preferred(),
            None
        );
        assert_eq!(accepted(Some("br;q=0.5, identity;q=0.8")).preferred(), None);
        assert_eq!(
            accepted(Some("GZIP;Q=1.000, br;q=0")).preferred(),
            Some(ContentCoding::Gzip)
        );
        assert_eq!(
            accepted(Some("zstd, br;q=0.8")).preferred_streaming(),
            StreamingContentCoding::Brotli
        );
        assert_eq!(
            accepted(Some("br;q=0")).preferred_streaming(),
            StreamingContentCoding::Identity
        );
        assert_eq!(
            accepted(Some("br;q=0.5, identity;q=0.8")).preferred_streaming(),
            StreamingContentCoding::Identity
        );
        assert_eq!(
            accepted(Some("gzip, identity;q=0")).preferred_streaming(),
            StreamingContentCoding::NotAcceptable
        );
        assert_eq!(
            accepted(Some("*;q=0")).preferred_streaming(),
            StreamingContentCoding::NotAcceptable
        );
    }

    #[test]
    fn invalid_quality_does_not_enable_a_coding() {
        assert_eq!(accepted(Some("br;q=2, gzip;q=0.1234")).preferred(), None);
        assert_eq!(accepted(Some("br;level=4")).preferred(), None);
    }

    #[test]
    fn eligibility_respects_size_type_metadata_and_opt_out() {
        let mut headers = HeaderMap::new();
        headers.insert(CONTENT_TYPE, "text/plain; charset=utf-8".parse().unwrap());
        assert!(!response_is_compressible(StatusCode::OK, &headers, 1023));
        assert!(response_is_compressible(StatusCode::OK, &headers, 1024));

        headers.insert(CACHE_CONTROL, "public, no-transform".parse().unwrap());
        assert!(!response_is_compressible(StatusCode::OK, &headers, 1024));
        headers.remove(CACHE_CONTROL);
        headers.insert(CONTENT_TYPE, "image/png".parse().unwrap());
        assert!(!response_is_compressible(StatusCode::OK, &headers, 1024));
        headers.insert(CONTENT_TYPE, "image/svg+xml".parse().unwrap());
        assert!(response_is_compressible(StatusCode::OK, &headers, 1024));
    }

    #[test]
    fn vary_is_merged_without_duplicates() {
        let mut headers = HeaderMap::new();
        headers.insert(VARY, "Accept-Language".parse().unwrap());
        vary_on_accept_encoding(&mut headers);
        vary_on_accept_encoding(&mut headers);
        let values = headers
            .get_all(VARY)
            .iter()
            .map(|value| value.to_str().unwrap())
            .collect::<Vec<_>>();
        assert_eq!(values, ["Accept-Language", "Accept-Encoding"]);
    }

    #[test]
    fn supported_content_codings_roundtrip() {
        let input = b"compressible response body ".repeat(256);
        for coding in [
            ContentCoding::Zstandard,
            ContentCoding::Brotli,
            ContentCoding::Gzip,
        ] {
            let encoded = encode_bytes(coding, &input).unwrap();
            assert!(encoded.len() < input.len());
            let mut decoded = Vec::new();
            match coding {
                ContentCoding::Zstandard => {
                    zstd::stream::read::Decoder::new(encoded.as_slice())
                        .unwrap()
                        .read_to_end(&mut decoded)
                        .unwrap();
                }
                ContentCoding::Brotli => {
                    brotli::Decompressor::new(encoded.as_slice(), 4096)
                        .read_to_end(&mut decoded)
                        .unwrap();
                }
                ContentCoding::Gzip => {
                    flate2::read::GzDecoder::new(encoded.as_slice())
                        .read_to_end(&mut decoded)
                        .unwrap();
                }
            }
            assert_eq!(decoded, input);
        }
    }

    #[test]
    fn encoded_etags_are_representation_specific() {
        assert_eq!(
            encoded_etag("W/\"abc\"", ContentCoding::Brotli),
            "W/\"abc-br\""
        );
        assert_eq!(encoded_etag("\"abc\"", ContentCoding::Gzip), "\"abc-gzip\"");
        assert_eq!(
            encoded_etag("\"abc\"", ContentCoding::Zstandard),
            "\"abc-zstd\""
        );
    }
}
