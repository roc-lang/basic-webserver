//! Benchmark-only process allocation instrumentation.
//!
//! This feature is intentionally absent from production host builds. It lets
//! the end-to-end SSE harness estimate per-event allocation slopes across
//! otherwise identical short-lived server processes.

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicU64, Ordering};

struct CountingAllocator;

static ALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static DEALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static REALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static ALLOCATED_BYTES: AtomicU64 = AtomicU64::new(0);
static REALLOCATED_BYTES: AtomicU64 = AtomicU64::new(0);

#[global_allocator]
static ALLOCATOR: CountingAllocator = CountingAllocator;

unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        ALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
        ALLOCATED_BYTES.fetch_add(layout.size() as u64, Ordering::Relaxed);
        unsafe { System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        ALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
        ALLOCATED_BYTES.fetch_add(layout.size() as u64, Ordering::Relaxed);
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        DEALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
        unsafe { System.dealloc(pointer, layout) };
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        REALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
        REALLOCATED_BYTES.fetch_add(new_size as u64, Ordering::Relaxed);
        unsafe { System.realloc(pointer, layout, new_size) }
    }
}

pub(crate) fn report() {
    let roc = crate::roc_alloc::benchmark_counts();
    eprintln!(
        "SSE_BENCH_ALLOC global_allocs={} global_deallocs={} global_reallocs={} \
         global_allocated_bytes={} global_reallocated_bytes={} roc_allocs={} \
         roc_deallocs={} roc_reallocs={} roc_allocated_bytes={} roc_reallocated_bytes={}",
        ALLOC_CALLS.load(Ordering::Relaxed),
        DEALLOC_CALLS.load(Ordering::Relaxed),
        REALLOC_CALLS.load(Ordering::Relaxed),
        ALLOCATED_BYTES.load(Ordering::Relaxed),
        REALLOCATED_BYTES.load(Ordering::Relaxed),
        roc.allocs,
        roc.deallocs,
        roc.reallocs,
        roc.allocated_bytes,
        roc.reallocated_bytes,
    );
}
