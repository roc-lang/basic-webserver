use datastar_transport_spike::{datastar_event, ExplicitBrotli, PersistentBrotli};
use serde::Serialize;
use std::alloc::{GlobalAlloc, Layout, System};
use std::hint::black_box;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::time::Instant;

struct CountingAllocator;

static ALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static ALLOC_BYTES: AtomicU64 = AtomicU64::new(0);
static DEALLOC_BYTES: AtomicU64 = AtomicU64::new(0);
static LIVE_BYTES: AtomicI64 = AtomicI64::new(0);
static PEAK_LIVE_BYTES: AtomicI64 = AtomicI64::new(0);

#[global_allocator]
static ALLOCATOR: CountingAllocator = CountingAllocator;

unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let pointer = unsafe { System.alloc(layout) };
        if !pointer.is_null() {
            record_alloc(layout.size());
        }
        pointer
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        record_dealloc(layout.size());
        unsafe { System.dealloc(pointer, layout) };
    }

    unsafe fn realloc(&self, pointer: *mut u8, old: Layout, new_size: usize) -> *mut u8 {
        let next = unsafe { System.realloc(pointer, old, new_size) };
        if !next.is_null() {
            record_dealloc(old.size());
            record_alloc(new_size);
        }
        next
    }
}

fn record_alloc(bytes: usize) {
    ALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
    ALLOC_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    let live = LIVE_BYTES.fetch_add(bytes as i64, Ordering::Relaxed) + bytes as i64;
    let mut peak = PEAK_LIVE_BYTES.load(Ordering::Relaxed);
    while live > peak {
        match PEAK_LIVE_BYTES.compare_exchange_weak(
            peak,
            live,
            Ordering::Relaxed,
            Ordering::Relaxed,
        ) {
            Ok(_) => break,
            Err(observed) => peak = observed,
        }
    }
}

fn record_dealloc(bytes: usize) {
    DEALLOC_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    LIVE_BYTES.fetch_sub(bytes as i64, Ordering::Relaxed);
}

#[derive(Clone, Copy)]
struct AllocationSnapshot {
    calls: u64,
    allocated: u64,
    deallocated: u64,
    live: i64,
}

fn snapshot() -> AllocationSnapshot {
    AllocationSnapshot {
        calls: ALLOC_CALLS.load(Ordering::Relaxed),
        allocated: ALLOC_BYTES.load(Ordering::Relaxed),
        deallocated: DEALLOC_BYTES.load(Ordering::Relaxed),
        live: LIVE_BYTES.load(Ordering::Relaxed),
    }
}

#[derive(Serialize)]
struct Sample {
    implementation: &'static str,
    evidence: &'static str,
    mode: &'static str,
    quality: u32,
    window_bits: u32,
    target_event_bytes: usize,
    framed_event_bytes: usize,
    events: usize,
    sample: usize,
    elapsed_ns: u128,
    ns_per_event: f64,
    input_bytes: u64,
    wire_bytes: u64,
    compression_ratio: f64,
    maximum_flush_bytes: usize,
    allocation_calls: u64,
    allocated_bytes: u64,
    deallocated_bytes: u64,
    retained_bytes: i64,
}

fn event_count(target: usize) -> usize {
    ((64 * 1024 * 1024) / target).max(1_000)
}

fn run_explicit(event: &[u8], events: usize) -> (u64, usize) {
    let segment_limit = event.len() * 2 + 64 * 1024;
    let mut encoder = ExplicitBrotli::new(segment_limit);
    let mut wire_bytes = 0_u64;
    let mut maximum_flush_bytes = 0;
    for _ in 0..events {
        let output = encoder.encode_event(black_box(event)).unwrap();
        maximum_flush_bytes = maximum_flush_bytes.max(output.len());
        wire_bytes += output.len() as u64;
        black_box(output);
    }
    let tail = encoder.finish().unwrap();
    maximum_flush_bytes = maximum_flush_bytes.max(tail.len());
    wire_bytes += tail.len() as u64;
    black_box(tail);
    (wire_bytes, maximum_flush_bytes)
}

fn run_writer(event: &[u8], events: usize) -> (u64, usize) {
    let segment_limit = event.len() * 2 + 64 * 1024;
    let mut encoder = PersistentBrotli::new(segment_limit).unwrap();
    let mut wire_bytes = 0_u64;
    let mut maximum_flush_bytes = 0;
    for _ in 0..events {
        let output = encoder.encode_event(black_box(event)).unwrap();
        maximum_flush_bytes = maximum_flush_bytes.max(output.len());
        wire_bytes += output.len() as u64;
        black_box(output);
    }
    let tail = encoder.finish().unwrap();
    maximum_flush_bytes = maximum_flush_bytes.max(tail.len());
    wire_bytes += tail.len() as u64;
    black_box(tail);
    (wire_bytes, maximum_flush_bytes)
}

fn benchmark(samples: usize) {
    for target in [256, 4096, 65_536] {
        let event = datastar_event(target, 1);
        let events = event_count(target);
        black_box(run_explicit(&event, events.min(100)));
        black_box(run_writer(&event, events.min(100)));

        for (implementation, run) in [
            (
                "rust-low-level-q4-w18",
                run_explicit as fn(&[u8], usize) -> (u64, usize),
            ),
            (
                "rust-compressor-writer-q4-w18",
                run_writer as fn(&[u8], usize) -> (u64, usize),
            ),
        ] {
            for sample in 0..samples {
                let before = snapshot();
                let started = Instant::now();
                let (wire_bytes, maximum_flush_bytes) = run(&event, events);
                let elapsed = started.elapsed();
                let after = snapshot();
                let input_bytes = event.len() as u64 * events as u64;
                println!(
                    "{}",
                    serde_json::to_string(&Sample {
                        implementation,
                        evidence: "measured",
                        mode: "semantic-equivalence-compressor",
                        quality: 4,
                        window_bits: 18,
                        target_event_bytes: target,
                        framed_event_bytes: event.len(),
                        events,
                        sample,
                        elapsed_ns: elapsed.as_nanos(),
                        ns_per_event: elapsed.as_nanos() as f64 / events as f64,
                        input_bytes,
                        wire_bytes,
                        compression_ratio: wire_bytes as f64 / input_bytes as f64,
                        maximum_flush_bytes,
                        allocation_calls: after.calls - before.calls,
                        allocated_bytes: after.allocated - before.allocated,
                        deallocated_bytes: after.deallocated - before.deallocated,
                        retained_bytes: after.live - before.live,
                    })
                    .unwrap()
                );
            }
        }
    }
}

#[derive(Serialize)]
struct MemoryResult {
    implementation: &'static str,
    evidence: &'static str,
    streams: usize,
    event_bytes: usize,
    allocation_calls: u64,
    allocated_bytes: u64,
    retained_bytes: i64,
    peak_live_delta_bytes: i64,
    retained_bytes_per_stream: f64,
}

fn memory(streams: usize) {
    let event = datastar_event(256, 1);
    let before = snapshot();
    PEAK_LIVE_BYTES.store(before.live, Ordering::Relaxed);
    let mut encoders = Vec::with_capacity(streams);
    for _ in 0..streams {
        let mut encoder = ExplicitBrotli::new(128 * 1024);
        black_box(encoder.encode_event(&event).unwrap());
        encoders.push(encoder);
    }
    let after = snapshot();
    let peak = PEAK_LIVE_BYTES.load(Ordering::Relaxed);
    let retained = after.live - before.live;
    println!(
        "{}",
        serde_json::to_string(&MemoryResult {
            implementation: "rust-low-level-q4-w18",
            evidence: "measured",
            streams,
            event_bytes: event.len(),
            allocation_calls: after.calls - before.calls,
            allocated_bytes: after.allocated - before.allocated,
            retained_bytes: retained,
            peak_live_delta_bytes: peak - before.live,
            retained_bytes_per_stream: retained as f64 / streams as f64,
        })
        .unwrap()
    );
    black_box(encoders);
}

fn main() {
    let mut arguments = std::env::args().skip(1);
    match arguments.next().as_deref() {
        None | Some("benchmark") => {
            let samples = arguments
                .next()
                .map(|value| value.parse().expect("samples must be an integer"))
                .unwrap_or(7);
            benchmark(samples);
        }
        Some("memory") => {
            let streams = arguments
                .next()
                .expect("memory requires a stream count")
                .parse()
                .expect("stream count must be an integer");
            memory(streams);
        }
        Some(command) => panic!("unknown command {command:?}"),
    }
}
