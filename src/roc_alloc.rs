//! Host-owned allocation protocol for ordinary Roc allocations and immutable
//! seamless backings.
//!
//! Every allocation has a self-describing header immediately before the
//! pointer visible to Roc's allocator ABI. Ordinary allocations have no
//! finalizer. Host-owned allocations carry an immutable kind and finalizer, so
//! final Roc ARC release can destroy their native owner without a registry.

use core::alloc::Layout;
use core::ffi::c_void;
use core::ptr::NonNull;
#[cfg(feature = "benchmark-instrumentation")]
use core::sync::atomic::{AtomicI64, AtomicU64};
use core::sync::atomic::{AtomicUsize, Ordering};

use crate::roc_platform_abi::RocHost;

const ALLOCATION_MAGIC: u64 = 0x524f_4341_4c4c_4f43;
const DEAD_ALLOCATION_MAGIC: u64 = 0x4445_4144_414c_4c4f;
const ALLOCATION_VERSION: u32 = 1;
const HEADER_CANARY: u64 = 0xa110_cafe_fade_1680;
#[cfg(debug_assertions)]
const TAIL_CANARY: u64 = 0xb0d1_cafe_fade_1680;
const ROC_DEBUG_REFCOUNT_POISON: isize = if core::mem::size_of::<usize>() == 8 {
    0xdead_beef_dead_beef_u64 as isize
} else {
    0xdead_beef_u32 as isize
};

#[cfg(debug_assertions)]
const TAIL_BYTES: usize = core::mem::size_of::<u64>();
#[cfg(not(debug_assertions))]
const TAIL_BYTES: usize = 0;

pub(crate) type AllocationDrop = unsafe fn(*mut u8);

pub(crate) fn is_finalized_roc_refcount(value: isize) -> bool {
    value == 0 || value == ROC_DEBUG_REFCOUNT_POISON
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub(crate) enum AllocationKind {
    Ordinary = 1,
    RequestBody = 2,
    SeamlessBytes = 3,
}

impl AllocationKind {
    fn from_raw(raw: u32) -> Option<Self> {
        match raw {
            1 => Some(Self::Ordinary),
            2 => Some(Self::RequestBody),
            3 => Some(Self::SeamlessBytes),
            _ => None,
        }
    }
}

#[repr(C)]
struct AllocationHeader {
    magic: u64,
    header_canary: u64,
    requested_size: usize,
    total_size: usize,
    prefix_size: usize,
    requested_alignment: usize,
    drop_fn: Option<AllocationDrop>,
    version: u32,
    kind: u32,
    #[cfg(feature = "benchmark-instrumentation")]
    benchmark_epoch: u64,
}

const _: () = assert!(core::mem::size_of::<AllocationHeader>()
    .is_multiple_of(core::mem::align_of::<AllocationHeader>()));

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct AllocationCounts {
    pub active_request_bodies: usize,
    pub request_body_high_water: usize,
    pub active_seamless_backings: usize,
    pub seamless_backing_high_water: usize,
}

static ACTIVE_REQUEST_BODIES: AtomicUsize = AtomicUsize::new(0);
static REQUEST_BODY_HIGH_WATER: AtomicUsize = AtomicUsize::new(0);
static ACTIVE_SEAMLESS_BACKINGS: AtomicUsize = AtomicUsize::new(0);
static SEAMLESS_BACKING_HIGH_WATER: AtomicUsize = AtomicUsize::new(0);

#[cfg(feature = "benchmark-instrumentation")]
struct BenchmarkCounters {
    allocs: AtomicUsize,
    deallocs: AtomicUsize,
    reallocs: AtomicUsize,
    allocated_bytes: AtomicUsize,
    deallocated_bytes: AtomicUsize,
    reallocated_bytes: AtomicUsize,
    live_blocks: AtomicI64,
    live_bytes: AtomicI64,
    peak_live_blocks: AtomicI64,
    peak_live_bytes: AtomicI64,
}

#[cfg(feature = "benchmark-instrumentation")]
impl BenchmarkCounters {
    const fn new() -> Self {
        Self {
            allocs: AtomicUsize::new(0),
            deallocs: AtomicUsize::new(0),
            reallocs: AtomicUsize::new(0),
            allocated_bytes: AtomicUsize::new(0),
            deallocated_bytes: AtomicUsize::new(0),
            reallocated_bytes: AtomicUsize::new(0),
            live_blocks: AtomicI64::new(0),
            live_bytes: AtomicI64::new(0),
            peak_live_blocks: AtomicI64::new(0),
            peak_live_bytes: AtomicI64::new(0),
        }
    }

    fn reset(&self) {
        self.allocs.store(0, Ordering::Release);
        self.deallocs.store(0, Ordering::Release);
        self.reallocs.store(0, Ordering::Release);
        self.allocated_bytes.store(0, Ordering::Release);
        self.deallocated_bytes.store(0, Ordering::Release);
        self.reallocated_bytes.store(0, Ordering::Release);
        self.live_blocks.store(0, Ordering::Release);
        self.live_bytes.store(0, Ordering::Release);
        self.peak_live_blocks.store(0, Ordering::Release);
        self.peak_live_bytes.store(0, Ordering::Release);
    }

    fn allocated(&self, bytes: usize) {
        self.allocs.fetch_add(1, Ordering::Relaxed);
        self.allocated_bytes.fetch_add(bytes, Ordering::Relaxed);
        let blocks = self.live_blocks.fetch_add(1, Ordering::AcqRel) + 1;
        let bytes = i64::try_from(bytes).unwrap_or(i64::MAX);
        let live_bytes = self.live_bytes.fetch_add(bytes, Ordering::AcqRel) + bytes;
        benchmark_update_peak(&self.peak_live_blocks, blocks);
        benchmark_update_peak(&self.peak_live_bytes, live_bytes);
    }

    fn deallocated(&self, bytes: usize, affects_live: bool) {
        self.deallocs.fetch_add(1, Ordering::Relaxed);
        self.deallocated_bytes.fetch_add(bytes, Ordering::Relaxed);
        if affects_live {
            self.live_blocks.fetch_sub(1, Ordering::AcqRel);
            self.live_bytes
                .fetch_sub(i64::try_from(bytes).unwrap_or(i64::MAX), Ordering::AcqRel);
        }
    }

    fn reallocated(&self, old_bytes: usize, new_bytes: usize, affects_live: bool) {
        self.reallocs.fetch_add(1, Ordering::Relaxed);
        self.reallocated_bytes
            .fetch_add(new_bytes, Ordering::Relaxed);
        if !affects_live {
            return;
        }
        let change = new_bytes as i128 - old_bytes as i128;
        let change = change.clamp(i64::MIN as i128, i64::MAX as i128) as i64;
        let live_bytes = self.live_bytes.fetch_add(change, Ordering::AcqRel) + change;
        benchmark_update_peak(&self.peak_live_bytes, live_bytes);
    }

    fn snapshot(&self) -> BenchmarkAllocationCounts {
        BenchmarkAllocationCounts {
            allocs: self.allocs.load(Ordering::Acquire),
            deallocs: self.deallocs.load(Ordering::Acquire),
            reallocs: self.reallocs.load(Ordering::Acquire),
            allocated_bytes: self.allocated_bytes.load(Ordering::Acquire),
            deallocated_bytes: self.deallocated_bytes.load(Ordering::Acquire),
            reallocated_bytes: self.reallocated_bytes.load(Ordering::Acquire),
            live_blocks: self.live_blocks.load(Ordering::Acquire),
            live_bytes: self.live_bytes.load(Ordering::Acquire),
            peak_live_blocks: self.peak_live_blocks.load(Ordering::Acquire),
            peak_live_bytes: self.peak_live_bytes.load(Ordering::Acquire),
        }
    }
}

#[cfg(feature = "benchmark-instrumentation")]
fn benchmark_update_peak(peak: &AtomicI64, value: i64) {
    let mut observed = peak.load(Ordering::Acquire);
    while value > observed {
        match peak.compare_exchange_weak(observed, value, Ordering::AcqRel, Ordering::Acquire) {
            Ok(_) => return,
            Err(next) => observed = next,
        }
    }
}

#[cfg(feature = "benchmark-instrumentation")]
static BENCH_TOTAL: BenchmarkCounters = BenchmarkCounters::new();
#[cfg(feature = "benchmark-instrumentation")]
static BENCH_EPOCH: BenchmarkCounters = BenchmarkCounters::new();
#[cfg(feature = "benchmark-instrumentation")]
static BENCH_CURRENT_EPOCH: AtomicU64 = AtomicU64::new(0);
#[cfg(feature = "benchmark-instrumentation")]
static BENCH_EPOCH_GENERATION: AtomicU64 = AtomicU64::new(0);

#[cfg(feature = "benchmark-instrumentation")]
std::thread_local! {
    static BENCH_ROC_ALLOCATION_DEPTH: core::cell::Cell<u32> = const { core::cell::Cell::new(0) };
    static BENCH_ROC_ALLOCATION_EPOCH: core::cell::Cell<u64> = const { core::cell::Cell::new(0) };
}

#[cfg(feature = "benchmark-instrumentation")]
#[derive(Clone, Copy, Debug, serde::Serialize)]
pub(crate) struct BenchmarkAllocationCounts {
    pub(crate) allocs: usize,
    pub(crate) deallocs: usize,
    pub(crate) reallocs: usize,
    pub(crate) allocated_bytes: usize,
    pub(crate) deallocated_bytes: usize,
    pub(crate) reallocated_bytes: usize,
    pub(crate) live_blocks: i64,
    pub(crate) live_bytes: i64,
    pub(crate) peak_live_blocks: i64,
    pub(crate) peak_live_bytes: i64,
}

#[cfg(feature = "benchmark-instrumentation")]
pub(crate) fn benchmark_begin_epoch() {
    BENCH_CURRENT_EPOCH.store(0, Ordering::Release);
    BENCH_EPOCH.reset();
    let generation = BENCH_EPOCH_GENERATION.fetch_add(1, Ordering::AcqRel) + 1;
    BENCH_CURRENT_EPOCH.store(generation, Ordering::Release);
}

#[cfg(feature = "benchmark-instrumentation")]
pub(crate) fn benchmark_counts() -> BenchmarkAllocationCounts {
    BENCH_EPOCH.snapshot()
}

#[cfg(feature = "benchmark-instrumentation")]
pub(crate) fn benchmark_end_epoch() {
    BENCH_CURRENT_EPOCH.store(0, Ordering::Release);
}

#[cfg(feature = "benchmark-instrumentation")]
pub(crate) fn benchmark_total_counts() -> BenchmarkAllocationCounts {
    BENCH_TOTAL.snapshot()
}

#[cfg(feature = "benchmark-instrumentation")]
pub(crate) fn benchmark_allocation_is_roc() -> bool {
    BENCH_ROC_ALLOCATION_DEPTH.with(|depth| depth.get() > 0)
}

#[cfg(feature = "benchmark-instrumentation")]
fn with_benchmark_roc_allocation<T>(epoch: u64, operation: impl FnOnce() -> T) -> T {
    BENCH_ROC_ALLOCATION_DEPTH.with(|depth| {
        let previous = depth.get();
        depth.set(previous + 1);
        let result = BENCH_ROC_ALLOCATION_EPOCH.with(|active_epoch| {
            let previous_epoch = active_epoch.replace(epoch);
            let result = operation();
            active_epoch.set(previous_epoch);
            result
        });
        depth.set(previous);
        result
    })
}

#[cfg(feature = "benchmark-instrumentation")]
fn benchmark_current_epoch() -> u64 {
    BENCH_CURRENT_EPOCH.load(Ordering::Acquire)
}

#[cfg(feature = "benchmark-instrumentation")]
fn benchmark_roc_allocation_epoch() -> u64 {
    BENCH_ROC_ALLOCATION_EPOCH.with(core::cell::Cell::get)
}

#[cfg(feature = "benchmark-instrumentation")]
fn benchmark_allocated(bytes: usize, operation_epoch: u64) {
    BENCH_TOTAL.allocated(bytes);
    if operation_epoch != 0 {
        BENCH_EPOCH.allocated(bytes);
    }
}

#[cfg(feature = "benchmark-instrumentation")]
fn benchmark_deallocated(bytes: usize, birth_epoch: u64, operation_epoch: u64) {
    BENCH_TOTAL.deallocated(bytes, true);
    if operation_epoch != 0 {
        let affects_live = birth_epoch == operation_epoch;
        BENCH_EPOCH.deallocated(bytes, affects_live);
    }
}

#[cfg(feature = "benchmark-instrumentation")]
fn benchmark_reallocated(
    old_bytes: usize,
    new_bytes: usize,
    birth_epoch: u64,
    operation_epoch: u64,
) {
    BENCH_TOTAL.reallocated(old_bytes, new_bytes, true);
    if operation_epoch != 0 {
        let affects_live = birth_epoch == operation_epoch;
        BENCH_EPOCH.reallocated(old_bytes, new_bytes, affects_live);
    }
}

#[cfg(debug_assertions)]
#[derive(Clone, Copy)]
struct DebugAllocation {
    kind: AllocationKind,
    requested_size: usize,
    requested_alignment: usize,
}

#[cfg(debug_assertions)]
fn debug_allocations(
) -> &'static std::sync::Mutex<std::collections::HashMap<usize, DebugAllocation>> {
    use std::sync::{Mutex, OnceLock};

    static LIVE: OnceLock<Mutex<std::collections::HashMap<usize, DebugAllocation>>> =
        OnceLock::new();
    LIVE.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

fn fatal(message: &str) -> ! {
    eprintln!("fatal: Roc allocation invariant failed: {message}");
    std::process::abort();
}

fn checked_add(left: usize, right: usize, context: &str) -> usize {
    left.checked_add(right).unwrap_or_else(|| fatal(context))
}

fn normalized_alignment(alignment: usize) -> usize {
    let alignment = alignment
        .max(core::mem::align_of::<usize>())
        .max(core::mem::align_of::<AllocationHeader>());
    if !alignment.is_power_of_two() {
        fatal("alignment is not a power of two");
    }
    alignment
}

fn round_up(value: usize, alignment: usize) -> usize {
    let mask = alignment - 1;
    checked_add(value, mask, "allocation prefix overflow") & !mask
}

fn update_high_water(active: &AtomicUsize, high_water: &AtomicUsize) {
    let current = active.fetch_add(1, Ordering::AcqRel) + 1;
    let mut observed = high_water.load(Ordering::Acquire);
    while current > observed {
        match high_water.compare_exchange_weak(
            observed,
            current,
            Ordering::AcqRel,
            Ordering::Acquire,
        ) {
            Ok(_) => break,
            Err(next) => observed = next,
        }
    }
}

fn allocated(kind: AllocationKind) {
    match kind {
        AllocationKind::Ordinary => {}
        AllocationKind::RequestBody => {
            update_high_water(&ACTIVE_REQUEST_BODIES, &REQUEST_BODY_HIGH_WATER);
        }
        AllocationKind::SeamlessBytes => {
            update_high_water(&ACTIVE_SEAMLESS_BACKINGS, &SEAMLESS_BACKING_HIGH_WATER);
        }
    }
}

fn deallocated(kind: AllocationKind) {
    let active = match kind {
        AllocationKind::Ordinary => return,
        AllocationKind::RequestBody => &ACTIVE_REQUEST_BODIES,
        AllocationKind::SeamlessBytes => &ACTIVE_SEAMLESS_BACKINGS,
    };
    let previous = active.fetch_sub(1, Ordering::AcqRel);
    if previous == 0 {
        fatal("host-owned allocation accounting underflow");
    }
}

#[cfg(debug_assertions)]
fn debug_register(
    user_ptr: *mut u8,
    kind: AllocationKind,
    requested_size: usize,
    requested_alignment: usize,
) {
    let old = debug_allocations()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert(
            user_ptr as usize,
            DebugAllocation {
                kind,
                requested_size,
                requested_alignment,
            },
        );
    if old.is_some() {
        fatal("duplicate live allocation address");
    }
}

#[cfg(not(debug_assertions))]
fn debug_register(
    _user_ptr: *mut u8,
    _kind: AllocationKind,
    _requested_size: usize,
    _requested_alignment: usize,
) {
}

#[cfg(debug_assertions)]
fn debug_lookup(user_ptr: *mut u8) -> DebugAllocation {
    debug_allocations()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .get(&(user_ptr as usize))
        .copied()
        .unwrap_or_else(|| fatal("foreign or duplicate deallocation"))
}

#[cfg(debug_assertions)]
fn debug_remove(user_ptr: *mut u8) -> DebugAllocation {
    debug_allocations()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&(user_ptr as usize))
        .unwrap_or_else(|| fatal("foreign or duplicate deallocation"))
}

unsafe fn header_from_user(user_ptr: *mut u8) -> *mut AllocationHeader {
    unsafe { user_ptr.sub(core::mem::size_of::<AllocationHeader>()) }.cast::<AllocationHeader>()
}

unsafe fn validate_header(
    user_ptr: *mut u8,
    supplied_alignment: Option<usize>,
) -> *mut AllocationHeader {
    if user_ptr.is_null() {
        fatal("null allocation pointer");
    }

    #[cfg(debug_assertions)]
    let recorded = debug_lookup(user_ptr);

    let header_ptr = unsafe { header_from_user(user_ptr) };
    let header = unsafe { &*header_ptr };
    if header.magic != ALLOCATION_MAGIC {
        fatal("bad allocation magic");
    }
    if header.version != ALLOCATION_VERSION {
        fatal("unsupported allocation header version");
    }
    if header.header_canary != HEADER_CANARY {
        fatal("allocation header canary was overwritten");
    }
    let kind =
        AllocationKind::from_raw(header.kind).unwrap_or_else(|| fatal("invalid allocation kind"));
    let alignment = normalized_alignment(header.requested_alignment);
    if alignment != header.requested_alignment || (user_ptr as usize) & (alignment - 1) != 0 {
        fatal("allocation alignment metadata is invalid");
    }
    if supplied_alignment.is_some_and(|value| normalized_alignment(value) != alignment) {
        fatal("deallocation alignment does not match allocation");
    }
    if header.prefix_size < core::mem::size_of::<AllocationHeader>()
        || header.prefix_size % alignment != 0
    {
        fatal("allocation-base recovery metadata is invalid");
    }
    let expected_total = checked_add(
        checked_add(
            header.prefix_size,
            header.requested_size,
            "allocation size overflow",
        ),
        TAIL_BYTES,
        "allocation tail size overflow",
    );
    if header.total_size != expected_total {
        fatal("allocation size metadata is invalid");
    }
    if kind == AllocationKind::Ordinary && header.drop_fn.is_some() {
        fatal("ordinary allocation unexpectedly has a finalizer");
    }
    if kind != AllocationKind::Ordinary && header.drop_fn.is_none() {
        fatal("host-owned allocation is missing its finalizer");
    }

    #[cfg(debug_assertions)]
    {
        if recorded.kind != kind
            || recorded.requested_size != header.requested_size
            || recorded.requested_alignment != header.requested_alignment
        {
            fatal("live-allocation ledger disagrees with allocation metadata");
        }
        let tail = unsafe { user_ptr.add(header.requested_size).cast::<u64>() };
        if unsafe { tail.read_unaligned() } != TAIL_CANARY {
            fatal("allocation tail canary was overwritten");
        }
    }

    header_ptr
}

unsafe fn allocate(
    requested_size: usize,
    requested_alignment: usize,
    kind: AllocationKind,
    drop_fn: Option<AllocationDrop>,
) -> *mut u8 {
    if (kind == AllocationKind::Ordinary) != drop_fn.is_none() {
        fatal("allocation kind/finalizer mismatch");
    }
    let alignment = normalized_alignment(requested_alignment);
    let prefix_size = round_up(core::mem::size_of::<AllocationHeader>(), alignment);
    let total_size = checked_add(
        checked_add(prefix_size, requested_size, "allocation size overflow"),
        TAIL_BYTES,
        "allocation tail size overflow",
    );
    let layout = Layout::from_size_align(total_size, alignment)
        .unwrap_or_else(|_| fatal("invalid allocation layout"));
    let base = unsafe { std::alloc::alloc(layout) };
    let base = NonNull::new(base).unwrap_or_else(|| fatal("out of memory"));
    let user_ptr = unsafe { base.as_ptr().add(prefix_size) };
    let header_ptr = unsafe { header_from_user(user_ptr) };
    unsafe {
        header_ptr.write(AllocationHeader {
            magic: ALLOCATION_MAGIC,
            header_canary: HEADER_CANARY,
            requested_size,
            total_size,
            prefix_size,
            requested_alignment: alignment,
            drop_fn,
            version: ALLOCATION_VERSION,
            kind: kind as u32,
            #[cfg(feature = "benchmark-instrumentation")]
            benchmark_epoch: if kind == AllocationKind::Ordinary && benchmark_allocation_is_roc() {
                benchmark_roc_allocation_epoch()
            } else {
                0
            },
        });
    }
    #[cfg(debug_assertions)]
    unsafe {
        user_ptr
            .add(requested_size)
            .cast::<u64>()
            .write_unaligned(TAIL_CANARY);
    }
    debug_register(user_ptr, kind, requested_size, alignment);
    allocated(kind);
    user_ptr
}

/// Allocate a self-describing host-owned Roc allocation.
///
/// # Safety
/// `drop_fn` must correctly destroy the initialized payload at the returned
/// pointer, and the caller must initialize it before Roc can release it.
pub(crate) unsafe fn allocate_host_owned(
    requested_size: usize,
    requested_alignment: usize,
    kind: AllocationKind,
    drop_fn: AllocationDrop,
) -> *mut u8 {
    if kind == AllocationKind::Ordinary {
        fatal("host-owned allocation cannot use the ordinary kind");
    }
    unsafe { allocate(requested_size, requested_alignment, kind, Some(drop_fn)) }
}

/// Validate a host-owned allocation before interpreting its payload.
///
/// # Safety
/// `user_ptr` must be a live pointer supplied by the opaque Roc capability
/// whose ARC reference the caller currently owns.
pub(crate) unsafe fn validate_host_owned(
    user_ptr: *mut u8,
    expected_kind: AllocationKind,
    minimum_size: usize,
    expected_alignment: usize,
) {
    let header = unsafe { &*validate_header(user_ptr, None) };
    if AllocationKind::from_raw(header.kind) != Some(expected_kind) {
        fatal("opaque allocation has the wrong kind");
    }
    if header.requested_size < minimum_size {
        fatal("opaque allocation is smaller than its representation");
    }
    if header.requested_alignment < normalized_alignment(expected_alignment) {
        fatal("opaque allocation alignment is too small");
    }
}

/// Return the immutable allocation kind for a live allocator-base pointer.
///
/// # Safety
/// `user_ptr` must identify a live allocation owned by this allocator.
pub(crate) unsafe fn allocation_kind(user_ptr: *mut u8) -> AllocationKind {
    let header = unsafe { &*validate_header(user_ptr, None) };
    AllocationKind::from_raw(header.kind).unwrap_or_else(|| fatal("invalid allocation kind"))
}

/// Validate a byte range against an ordinary allocation.
///
/// # Safety
/// `user_ptr` must identify a live allocation owned by this allocator.
pub(crate) unsafe fn validate_range(user_ptr: *mut u8, range_ptr: *const u8, range_length: usize) {
    let header = unsafe { &*validate_header(user_ptr, None) };
    if AllocationKind::from_raw(header.kind) != Some(AllocationKind::Ordinary) {
        fatal("ordinary allocation range check used with a host-owned allocation");
    }
    let allocation_start = user_ptr as usize;
    let allocation_end = allocation_start
        .checked_add(header.requested_size)
        .unwrap_or_else(|| fatal("allocation range overflow"));
    let range_start = range_ptr as usize;
    let range_end = range_start
        .checked_add(range_length)
        .unwrap_or_else(|| fatal("seamless slice range overflow"));
    if range_start < allocation_start || range_end > allocation_end {
        fatal("seamless slice escapes its ordinary backing allocation");
    }
}

pub(crate) fn counts() -> AllocationCounts {
    AllocationCounts {
        active_request_bodies: ACTIVE_REQUEST_BODIES.load(Ordering::Acquire),
        request_body_high_water: REQUEST_BODY_HIGH_WATER.load(Ordering::Acquire),
        active_seamless_backings: ACTIVE_SEAMLESS_BACKINGS.load(Ordering::Acquire),
        seamless_backing_high_water: SEAMLESS_BACKING_HIGH_WATER.load(Ordering::Acquire),
    }
}

#[cfg(all(test, debug_assertions))]
pub(crate) fn debug_is_live(user_ptr: *mut u8) -> bool {
    debug_allocations()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .contains_key(&(user_ptr as usize))
}

pub(crate) extern "C" fn roc_alloc(
    _roc_host: *mut RocHost,
    length: usize,
    alignment: usize,
) -> *mut c_void {
    #[cfg(feature = "benchmark-instrumentation")]
    {
        let operation_epoch = benchmark_current_epoch();
        benchmark_allocated(length, operation_epoch);
        return with_benchmark_roc_allocation(operation_epoch, || unsafe {
            allocate(length, alignment, AllocationKind::Ordinary, None).cast()
        });
    }
    #[cfg(not(feature = "benchmark-instrumentation"))]
    unsafe {
        allocate(length, alignment, AllocationKind::Ordinary, None).cast()
    }
}

pub(crate) extern "C" fn roc_dealloc(_roc_host: *mut RocHost, ptr: *mut c_void, alignment: usize) {
    #[cfg(feature = "benchmark-instrumentation")]
    let operation_epoch = benchmark_current_epoch();
    let user_ptr = ptr.cast::<u8>();
    let (layout, base, kind, drop_fn, _requested_size, _benchmark_epoch) = unsafe {
        let header = &mut *validate_header(user_ptr, Some(alignment));
        #[cfg(debug_assertions)]
        {
            debug_remove(user_ptr);
        }
        let layout = Layout::from_size_align(header.total_size, header.requested_alignment)
            .unwrap_or_else(|_| fatal("invalid deallocation layout"));
        let base = user_ptr.sub(header.prefix_size);
        let kind = AllocationKind::from_raw(header.kind)
            .unwrap_or_else(|| fatal("invalid allocation kind"));
        let drop_fn = header.drop_fn;
        let requested_size = header.requested_size;
        #[cfg(feature = "benchmark-instrumentation")]
        let benchmark_epoch = header.benchmark_epoch;
        #[cfg(not(feature = "benchmark-instrumentation"))]
        let benchmark_epoch = 0;
        header.magic = DEAD_ALLOCATION_MAGIC;
        (layout, base, kind, drop_fn, requested_size, benchmark_epoch)
    };

    if let Some(finalize) = drop_fn {
        unsafe { finalize(user_ptr) };
    }
    deallocated(kind);
    #[cfg(feature = "benchmark-instrumentation")]
    if kind == AllocationKind::Ordinary {
        benchmark_deallocated(_requested_size, _benchmark_epoch, operation_epoch);
        with_benchmark_roc_allocation(operation_epoch, || unsafe {
            std::alloc::dealloc(base, layout)
        });
        return;
    }
    unsafe { std::alloc::dealloc(base, layout) };
}

pub(crate) extern "C" fn roc_realloc(
    _roc_host: *mut RocHost,
    ptr: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> *mut c_void {
    #[cfg(feature = "benchmark-instrumentation")]
    let operation_epoch = benchmark_current_epoch();
    let old_user_ptr = ptr.cast::<u8>();
    unsafe {
        let header = &mut *validate_header(old_user_ptr, Some(alignment));
        if AllocationKind::from_raw(header.kind) != Some(AllocationKind::Ordinary) {
            fatal("Roc attempted to reallocate immutable host-owned backing");
        }
        #[cfg(debug_assertions)]
        {
            debug_remove(old_user_ptr);
        }

        let old_layout = Layout::from_size_align(header.total_size, header.requested_alignment)
            .unwrap_or_else(|_| fatal("invalid reallocation layout"));
        let prefix_size = header.prefix_size;
        let requested_alignment = header.requested_alignment;
        let _old_requested_size = header.requested_size;
        #[cfg(feature = "benchmark-instrumentation")]
        let _benchmark_epoch = header.benchmark_epoch;
        let new_total_size = checked_add(
            checked_add(prefix_size, new_length, "reallocation size overflow"),
            TAIL_BYTES,
            "reallocation tail size overflow",
        );
        let old_base = old_user_ptr.sub(prefix_size);
        #[cfg(feature = "benchmark-instrumentation")]
        let new_base = {
            benchmark_reallocated(
                _old_requested_size,
                new_length,
                _benchmark_epoch,
                operation_epoch,
            );
            with_benchmark_roc_allocation(operation_epoch, || {
                std::alloc::realloc(old_base, old_layout, new_total_size)
            })
        };
        #[cfg(not(feature = "benchmark-instrumentation"))]
        let new_base = std::alloc::realloc(old_base, old_layout, new_total_size);
        let new_base = NonNull::new(new_base).unwrap_or_else(|| fatal("out of memory"));
        let new_user_ptr = new_base.as_ptr().add(prefix_size);
        let new_header = &mut *header_from_user(new_user_ptr);
        new_header.requested_size = new_length;
        new_header.total_size = new_total_size;
        new_header.magic = ALLOCATION_MAGIC;
        #[cfg(debug_assertions)]
        new_user_ptr
            .add(new_length)
            .cast::<u64>()
            .write_unaligned(TAIL_CANARY);
        debug_register(
            new_user_ptr,
            AllocationKind::Ordinary,
            new_length,
            requested_alignment,
        );
        new_user_ptr.cast()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static FINALIZED: AtomicUsize = AtomicUsize::new(0);

    unsafe fn finalize_word(ptr: *mut u8) {
        assert_eq!(unsafe { ptr.cast::<usize>().read() }, 42);
        FINALIZED.fetch_add(1, Ordering::AcqRel);
    }

    #[test]
    fn ordinary_allocation_reallocates_and_preserves_bytes() {
        unsafe {
            let ptr = roc_alloc(core::ptr::null_mut(), 4, 4).cast::<u8>();
            ptr.copy_from_nonoverlapping([1, 2, 3, 4].as_ptr(), 4);
            let ptr = roc_realloc(core::ptr::null_mut(), ptr.cast(), 12, 4).cast::<u8>();
            assert_eq!(core::slice::from_raw_parts(ptr, 4), &[1, 2, 3, 4]);
            roc_dealloc(core::ptr::null_mut(), ptr.cast(), 4);
        }
    }

    #[test]
    fn host_owned_allocation_runs_its_embedded_finalizer_once() {
        FINALIZED.store(0, Ordering::Release);
        unsafe {
            let ptr = allocate_host_owned(
                core::mem::size_of::<usize>(),
                core::mem::align_of::<usize>(),
                AllocationKind::SeamlessBytes,
                finalize_word,
            );
            ptr.cast::<usize>().write(42);
            validate_host_owned(
                ptr,
                AllocationKind::SeamlessBytes,
                core::mem::size_of::<usize>(),
                core::mem::align_of::<usize>(),
            );
            roc_dealloc(
                core::ptr::null_mut(),
                ptr.cast(),
                core::mem::align_of::<usize>(),
            );
        }
        assert_eq!(FINALIZED.load(Ordering::Acquire), 1);
    }
}
