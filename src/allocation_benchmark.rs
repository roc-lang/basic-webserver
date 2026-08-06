//! Benchmark-only process allocation instrumentation.
//!
//! Normal host builds do not install this allocator. Instrumented builds can
//! delimit a quiescent measurement epoch and obtain fixed-size snapshots
//! without allocating while accounting is active.

use serde::Serialize;
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicI64, AtomicU64, AtomicU8, AtomicUsize, Ordering};

struct CountingAllocator;

#[global_allocator]
static ALLOCATOR: CountingAllocator = CountingAllocator;

const TRACKER_SLOTS: usize = 1 << 17;
const TRACKER_PROBES: usize = 128;

#[derive(Clone, Copy)]
#[repr(u8)]
enum AllocationDomain {
    Host = 1,
    Roc = 2,
    Harness = 3,
}

struct AllocationSlot {
    pointer: AtomicUsize,
    size: AtomicUsize,
    domain: AtomicU8,
    epoch: AtomicU64,
}

impl AllocationSlot {
    const fn new() -> Self {
        Self {
            pointer: AtomicUsize::new(0),
            size: AtomicUsize::new(0),
            domain: AtomicU8::new(0),
            epoch: AtomicU64::new(0),
        }
    }
}

static ALLOCATION_SLOTS: [AllocationSlot; TRACKER_SLOTS] =
    [const { AllocationSlot::new() }; TRACKER_SLOTS];
static TRACKING_MISSES_TOTAL: AtomicU64 = AtomicU64::new(0);
static TRACKING_MISSES_EPOCH: AtomicU64 = AtomicU64::new(0);
static EPOCH_GENERATION: AtomicU64 = AtomicU64::new(0);

fn allocation_hash(pointer: usize) -> usize {
    (pointer >> 4).wrapping_mul(0x9e37_79b1) & (TRACKER_SLOTS - 1)
}

fn track_allocation(
    pointer: *mut u8,
    size: usize,
    domain: AllocationDomain,
    birth_epoch: u64,
    operation_epoch: u64,
) {
    let pointer = pointer as usize;
    let start = allocation_hash(pointer);
    for offset in 0..TRACKER_PROBES {
        let slot = &ALLOCATION_SLOTS[(start + offset) & (TRACKER_SLOTS - 1)];
        if slot
            .pointer
            .compare_exchange(0, usize::MAX, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
        {
            slot.size.store(size, Ordering::Relaxed);
            slot.domain.store(domain as u8, Ordering::Relaxed);
            slot.epoch.store(birth_epoch, Ordering::Relaxed);
            slot.pointer.store(pointer, Ordering::Release);
            return;
        }
    }
    // Tracking capacity is diagnostic rather than an allocation-safety
    // boundary. Counts remain useful, but the eventual release falls back to
    // the releasing task's domain if this fixed table is saturated.
    TRACKING_MISSES_TOTAL.fetch_add(1, Ordering::Relaxed);
    if operation_epoch != 0 {
        TRACKING_MISSES_EPOCH.fetch_add(1, Ordering::Relaxed);
    }
}

fn untrack_allocation(pointer: *mut u8) -> Option<(usize, AllocationDomain, u64)> {
    let pointer = pointer as usize;
    let start = allocation_hash(pointer);
    for offset in 0..TRACKER_PROBES {
        let slot = &ALLOCATION_SLOTS[(start + offset) & (TRACKER_SLOTS - 1)];
        let observed = slot.pointer.load(Ordering::Acquire);
        if observed == pointer {
            if slot
                .pointer
                .compare_exchange(pointer, usize::MAX, Ordering::AcqRel, Ordering::Acquire)
                .is_err()
            {
                continue;
            }
            let size = slot.size.load(Ordering::Relaxed);
            let domain = match slot.domain.load(Ordering::Relaxed) {
                2 => AllocationDomain::Roc,
                3 => AllocationDomain::Harness,
                _ => AllocationDomain::Host,
            };
            let epoch = slot.epoch.load(Ordering::Relaxed);
            slot.pointer.store(0, Ordering::Release);
            return Some((size, domain, epoch));
        }
    }
    None
}

struct Counters {
    allocs: AtomicU64,
    deallocs: AtomicU64,
    reallocs: AtomicU64,
    allocated_bytes: AtomicU64,
    deallocated_bytes: AtomicU64,
    reallocated_bytes: AtomicU64,
    live_blocks: AtomicI64,
    live_bytes: AtomicI64,
    peak_live_blocks: AtomicI64,
    peak_live_bytes: AtomicI64,
}

impl Counters {
    const fn new() -> Self {
        Self {
            allocs: AtomicU64::new(0),
            deallocs: AtomicU64::new(0),
            reallocs: AtomicU64::new(0),
            allocated_bytes: AtomicU64::new(0),
            deallocated_bytes: AtomicU64::new(0),
            reallocated_bytes: AtomicU64::new(0),
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
        self.allocated_bytes
            .fetch_add(bytes as u64, Ordering::Relaxed);
        let blocks = self.live_blocks.fetch_add(1, Ordering::AcqRel) + 1;
        let bytes = self.live_bytes.fetch_add(bytes as i64, Ordering::AcqRel) + bytes as i64;
        update_peak(&self.peak_live_blocks, blocks);
        update_peak(&self.peak_live_bytes, bytes);
    }

    fn deallocated(&self, bytes: usize, affects_live: bool) {
        self.deallocs.fetch_add(1, Ordering::Relaxed);
        self.deallocated_bytes
            .fetch_add(bytes as u64, Ordering::Relaxed);
        if affects_live {
            self.live_blocks.fetch_sub(1, Ordering::AcqRel);
            self.live_bytes.fetch_sub(bytes as i64, Ordering::AcqRel);
        }
    }

    fn reallocated(&self, old_bytes: usize, new_bytes: usize, affects_live: bool) {
        self.reallocs.fetch_add(1, Ordering::Relaxed);
        self.reallocated_bytes
            .fetch_add(new_bytes as u64, Ordering::Relaxed);
        if !affects_live {
            return;
        }
        let change = new_bytes as i128 - old_bytes as i128;
        let change = change.clamp(i64::MIN as i128, i64::MAX as i128) as i64;
        let bytes = self.live_bytes.fetch_add(change, Ordering::AcqRel) + change;
        update_peak(&self.peak_live_bytes, bytes);
    }

    fn snapshot(&self) -> CounterSnapshot {
        CounterSnapshot {
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

fn update_peak(peak: &AtomicI64, value: i64) {
    let mut observed = peak.load(Ordering::Acquire);
    while value > observed {
        match peak.compare_exchange_weak(observed, value, Ordering::AcqRel, Ordering::Acquire) {
            Ok(_) => return,
            Err(next) => observed = next,
        }
    }
}

static PROCESS_TOTAL: Counters = Counters::new();
static ROC_BACKING_TOTAL: Counters = Counters::new();
static HOST_TOTAL: Counters = Counters::new();
static HARNESS_TOTAL: Counters = Counters::new();
static EPOCH_PROCESS: Counters = Counters::new();
static EPOCH_ROC_BACKING: Counters = Counters::new();
static EPOCH_HOST: Counters = Counters::new();
static EPOCH_HARNESS: Counters = Counters::new();
static CURRENT_EPOCH: AtomicU64 = AtomicU64::new(0);

tokio::task_local! {
    static HARNESS_ALLOCATION_DOMAIN: ();
}

pub(crate) async fn scope_harness<F: std::future::Future>(future: F) -> F::Output {
    HARNESS_ALLOCATION_DOMAIN.scope((), future).await
}

fn allocation_is_harness() -> bool {
    HARNESS_ALLOCATION_DOMAIN.try_with(|()| ()).is_ok()
}

unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let pointer = unsafe { System.alloc(layout) };
        if !pointer.is_null() {
            let domain = current_domain();
            let epoch = current_epoch();
            track_allocation(pointer, layout.size(), domain, epoch, epoch);
            record_alloc(layout.size(), domain, epoch);
        }
        pointer
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let pointer = unsafe { System.alloc_zeroed(layout) };
        if !pointer.is_null() {
            let domain = current_domain();
            let epoch = current_epoch();
            track_allocation(pointer, layout.size(), domain, epoch, epoch);
            record_alloc(layout.size(), domain, epoch);
        }
        pointer
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        let operation_epoch = current_epoch();
        let (size, domain, epoch) =
            untrack_allocation(pointer).unwrap_or((layout.size(), current_domain(), 0));
        record_dealloc(size, domain, epoch, operation_epoch);
        unsafe { System.dealloc(pointer, layout) };
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let operation_epoch = current_epoch();
        let replacement = unsafe { System.realloc(pointer, layout, new_size) };
        if !replacement.is_null() {
            let (old_size, domain, epoch) =
                untrack_allocation(pointer).unwrap_or((layout.size(), current_domain(), 0));
            track_allocation(replacement, new_size, domain, epoch, operation_epoch);
            record_realloc(old_size, new_size, domain, epoch, operation_epoch);
        }
        replacement
    }
}

fn current_domain() -> AllocationDomain {
    if crate::roc_alloc::benchmark_allocation_is_roc() {
        AllocationDomain::Roc
    } else if allocation_is_harness() {
        AllocationDomain::Harness
    } else {
        AllocationDomain::Host
    }
}

fn current_epoch() -> u64 {
    CURRENT_EPOCH.load(Ordering::Acquire)
}

fn record_alloc(bytes: usize, domain: AllocationDomain, operation_epoch: u64) {
    PROCESS_TOTAL.allocated(bytes);
    match domain {
        AllocationDomain::Roc => ROC_BACKING_TOTAL.allocated(bytes),
        AllocationDomain::Harness => HARNESS_TOTAL.allocated(bytes),
        AllocationDomain::Host => HOST_TOTAL.allocated(bytes),
    }
    if operation_epoch != 0 {
        EPOCH_PROCESS.allocated(bytes);
        match domain {
            AllocationDomain::Roc => EPOCH_ROC_BACKING.allocated(bytes),
            AllocationDomain::Harness => EPOCH_HARNESS.allocated(bytes),
            AllocationDomain::Host => EPOCH_HOST.allocated(bytes),
        }
    }
}

fn record_dealloc(bytes: usize, domain: AllocationDomain, birth_epoch: u64, operation_epoch: u64) {
    PROCESS_TOTAL.deallocated(bytes, true);
    match domain {
        AllocationDomain::Roc => ROC_BACKING_TOTAL.deallocated(bytes, true),
        AllocationDomain::Harness => HARNESS_TOTAL.deallocated(bytes, true),
        AllocationDomain::Host => HOST_TOTAL.deallocated(bytes, true),
    }
    if operation_epoch != 0 {
        let affects_live = birth_epoch == operation_epoch;
        EPOCH_PROCESS.deallocated(bytes, affects_live);
        match domain {
            AllocationDomain::Roc => EPOCH_ROC_BACKING.deallocated(bytes, affects_live),
            AllocationDomain::Harness => EPOCH_HARNESS.deallocated(bytes, affects_live),
            AllocationDomain::Host => EPOCH_HOST.deallocated(bytes, affects_live),
        }
    }
}

fn record_realloc(
    old_bytes: usize,
    new_bytes: usize,
    domain: AllocationDomain,
    birth_epoch: u64,
    operation_epoch: u64,
) {
    PROCESS_TOTAL.reallocated(old_bytes, new_bytes, true);
    match domain {
        AllocationDomain::Roc => ROC_BACKING_TOTAL.reallocated(old_bytes, new_bytes, true),
        AllocationDomain::Harness => HARNESS_TOTAL.reallocated(old_bytes, new_bytes, true),
        AllocationDomain::Host => HOST_TOTAL.reallocated(old_bytes, new_bytes, true),
    }
    if operation_epoch != 0 {
        let affects_live = birth_epoch == operation_epoch;
        EPOCH_PROCESS.reallocated(old_bytes, new_bytes, affects_live);
        match domain {
            AllocationDomain::Roc => {
                EPOCH_ROC_BACKING.reallocated(old_bytes, new_bytes, affects_live)
            }
            AllocationDomain::Harness => {
                EPOCH_HARNESS.reallocated(old_bytes, new_bytes, affects_live)
            }
            AllocationDomain::Host => EPOCH_HOST.reallocated(old_bytes, new_bytes, affects_live),
        }
    }
}

#[derive(Clone, Copy, Debug, Serialize)]
pub(crate) struct CounterSnapshot {
    pub(crate) allocs: u64,
    pub(crate) deallocs: u64,
    pub(crate) reallocs: u64,
    pub(crate) allocated_bytes: u64,
    pub(crate) deallocated_bytes: u64,
    pub(crate) reallocated_bytes: u64,
    pub(crate) live_blocks: i64,
    pub(crate) live_bytes: i64,
    pub(crate) peak_live_blocks: i64,
    pub(crate) peak_live_bytes: i64,
}

#[derive(Clone, Copy, Debug, Serialize)]
pub(crate) struct AllocationSnapshot {
    pub(crate) process: CounterSnapshot,
    pub(crate) roc_backing: CounterSnapshot,
    pub(crate) host: CounterSnapshot,
    pub(crate) harness: CounterSnapshot,
    pub(crate) roc_requested: crate::roc_alloc::BenchmarkAllocationCounts,
    pub(crate) tracking_misses: u64,
}

pub(crate) fn begin_epoch() -> Result<(), &'static str> {
    if CURRENT_EPOCH.load(Ordering::Acquire) != 0 {
        return Err("an allocation measurement epoch is already active");
    }
    EPOCH_PROCESS.reset();
    EPOCH_ROC_BACKING.reset();
    EPOCH_HOST.reset();
    EPOCH_HARNESS.reset();
    TRACKING_MISSES_EPOCH.store(0, Ordering::Release);
    let generation = EPOCH_GENERATION.fetch_add(1, Ordering::AcqRel) + 1;
    crate::roc_alloc::benchmark_begin_epoch();
    CURRENT_EPOCH.store(generation, Ordering::Release);
    Ok(())
}

pub(crate) fn snapshot_epoch() -> AllocationSnapshot {
    let process = EPOCH_PROCESS.snapshot();
    let roc_backing = EPOCH_ROC_BACKING.snapshot();
    AllocationSnapshot {
        process,
        roc_backing,
        host: EPOCH_HOST.snapshot(),
        harness: EPOCH_HARNESS.snapshot(),
        roc_requested: crate::roc_alloc::benchmark_counts(),
        tracking_misses: TRACKING_MISSES_EPOCH.load(Ordering::Acquire),
    }
}

pub(crate) fn end_epoch() -> Result<AllocationSnapshot, &'static str> {
    if CURRENT_EPOCH.swap(0, Ordering::AcqRel) == 0 {
        return Err("no allocation measurement epoch is active");
    }
    crate::roc_alloc::benchmark_end_epoch();
    Ok(snapshot_epoch())
}

pub(crate) fn report() {
    CURRENT_EPOCH.store(0, Ordering::Release);
    crate::roc_alloc::benchmark_end_epoch();
    let process = PROCESS_TOTAL.snapshot();
    let roc_backing = ROC_BACKING_TOTAL.snapshot();
    let report = AllocationSnapshot {
        process,
        roc_backing,
        host: HOST_TOTAL.snapshot(),
        harness: HARNESS_TOTAL.snapshot(),
        roc_requested: crate::roc_alloc::benchmark_total_counts(),
        tracking_misses: TRACKING_MISSES_TOTAL.load(Ordering::Acquire),
    };
    match serde_json::to_string(&report) {
        Ok(json) => eprintln!("BENCHMARK_ALLOCATIONS {json}"),
        Err(error) => eprintln!("BENCHMARK_ALLOCATIONS_ERROR {error}"),
    }
}
