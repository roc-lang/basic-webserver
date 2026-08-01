use datastar_transport_spike::{ExplicitBrotli, RecyclerStats, RecyclingBrotli};
use serde::Serialize;
use std::alloc::{GlobalAlloc, Layout, System};
use std::hint::black_box;
use std::mem::size_of;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::time::Instant;

const DEFAULT_CACHE_BYTES: usize = 256 * 1024;

struct CountingAllocator;

static ALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static DEALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static ALLOC_BYTES: AtomicU64 = AtomicU64::new(0);
static DEALLOC_BYTES: AtomicU64 = AtomicU64::new(0);
static LIVE_ALLOCS: AtomicI64 = AtomicI64::new(0);
static LIVE_BYTES: AtomicI64 = AtomicI64::new(0);
static PEAK_LIVE_ALLOCS: AtomicI64 = AtomicI64::new(0);
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
    let allocations = LIVE_ALLOCS.fetch_add(1, Ordering::Relaxed) + 1;
    let live = LIVE_BYTES.fetch_add(bytes as i64, Ordering::Relaxed) + bytes as i64;
    update_peak(&PEAK_LIVE_ALLOCS, allocations);
    update_peak(&PEAK_LIVE_BYTES, live);
}

fn record_dealloc(bytes: usize) {
    DEALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
    DEALLOC_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    LIVE_ALLOCS.fetch_sub(1, Ordering::Relaxed);
    LIVE_BYTES.fetch_sub(bytes as i64, Ordering::Relaxed);
}

fn update_peak(target: &AtomicI64, value: i64) {
    let mut peak = target.load(Ordering::Relaxed);
    while value > peak {
        match target.compare_exchange_weak(peak, value, Ordering::Relaxed, Ordering::Relaxed) {
            Ok(_) => break,
            Err(observed) => peak = observed,
        }
    }
}

#[derive(Clone, Copy)]
struct AllocationSnapshot {
    alloc_calls: u64,
    dealloc_calls: u64,
    allocated: u64,
    deallocated: u64,
    live_allocations: i64,
    live_bytes: i64,
}

fn snapshot() -> AllocationSnapshot {
    AllocationSnapshot {
        alloc_calls: ALLOC_CALLS.load(Ordering::Relaxed),
        dealloc_calls: DEALLOC_CALLS.load(Ordering::Relaxed),
        allocated: ALLOC_BYTES.load(Ordering::Relaxed),
        deallocated: DEALLOC_BYTES.load(Ordering::Relaxed),
        live_allocations: LIVE_ALLOCS.load(Ordering::Relaxed),
        live_bytes: LIVE_BYTES.load(Ordering::Relaxed),
    }
}

fn reset_peaks(baseline: AllocationSnapshot) {
    PEAK_LIVE_ALLOCS.store(baseline.live_allocations, Ordering::Relaxed);
    PEAK_LIVE_BYTES.store(baseline.live_bytes, Ordering::Relaxed);
}

struct Trace {
    name: &'static str,
    events: Vec<Vec<u8>>,
    input_bytes: usize,
    digest: u64,
}

impl Trace {
    fn new(name: &'static str, events: Vec<Vec<u8>>) -> Self {
        let input_bytes = events.iter().map(Vec::len).sum();
        let digest = events.iter().fold(0xcbf29ce484222325, |hash, event| {
            event.iter().fold(hash, |hash, byte| {
                (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3)
            })
        });
        Self {
            name,
            events,
            input_bytes,
            digest,
        }
    }
}

fn todo_trace() -> Trace {
    let mut events = Vec::with_capacity(512);
    for sequence in 0..512 {
        let mut event = format!(
            "event: datastar-patch-elements\ndata: selector #todos\ndata: mode replace\ndata: elements <ul id=\"todos\" data-version=\"{sequence}\">"
        );
        for row in 0..24 {
            let id = (sequence + row * 17) % 997;
            let completed = (sequence + row) % 5 == 0;
            let priority = ["low", "normal", "high"][(sequence + row) % 3];
            let state = if completed { " done" } else { "" };
            event.push_str(&format!(
                "<li id=\"todo-{id}\" class=\"todo{state}\" data-priority=\"{priority}\"><input type=\"checkbox\"{}><span>Task {id}: validate bounded progressive delivery</span><small>{}/{}</small></li>",
                if completed { " checked" } else { "" },
                sequence % 31,
                31
            ));
        }
        event.push_str("</ul>\n\n");
        events.push(event.into_bytes());
    }
    Trace::new("changing-todo-html", events)
}

fn dashboard_trace() -> Trace {
    let mut events = Vec::with_capacity(512);
    for sequence in 0..512 {
        if sequence % 7 == 0 {
            events.push(
                format!(
                    "event: datastar-patch-signals\ndata: signals {{\"active\":{},\"queued\":{},\"p95Ms\":{},\"region\":\"{}\"}}\n\n",
                    80 + sequence % 37,
                    sequence % 19,
                    11 + sequence % 23,
                    ["mel", "syd", "sin", "fra"][sequence % 4],
                )
                .into_bytes(),
            );
            continue;
        }
        let mut event = format!(
            "event: datastar-patch-elements\ndata: selector #dashboard\ndata: mode replace\ndata: elements <section id=\"dashboard\" data-sample=\"{sequence}\"><header><h2>Live operations</h2><time>2026-08-01T12:{:02}:{:02}+10:00</time></header><table>",
            (sequence / 60) % 60,
            sequence % 60,
        );
        for row in 0..18 {
            let value = (sequence * 97 + row * 43) % 10_000;
            event.push_str(&format!(
                "<tr data-service=\"svc-{row}\"><th>service-{row:02}</th><td>{value}</td><td>{:.2}%</td><td><meter min=\"0\" max=\"100\" value=\"{}\"></meter></td></tr>",
                (value % 1000) as f64 / 100.0,
                value % 101,
            ));
        }
        event.push_str("</table></section>\n\n");
        events.push(event.into_bytes());
    }
    Trace::new("changing-dashboard-mixed", events)
}

fn official_fixture_trace() -> Trace {
    const FIXTURES: [&[u8]; 12] = [
        include_bytes!("../../../datastar-parity/fixtures/official/execute-script-all-options.sse"),
        include_bytes!("../../../datastar-parity/fixtures/official/execute-script-default.sse"),
        include_bytes!("../../../datastar-parity/fixtures/official/patch-elements-all-options.sse"),
        include_bytes!("../../../datastar-parity/fixtures/official/patch-elements-default.sse"),
        include_bytes!("../../../datastar-parity/fixtures/official/patch-elements-multiline.sse"),
        include_bytes!("../../../datastar-parity/fixtures/official/patch-signals-all-options.sse"),
        include_bytes!("../../../datastar-parity/fixtures/official/patch-signals-default.sse"),
        include_bytes!("../../../datastar-parity/fixtures/official/patch-signals-multiline.sse"),
        include_bytes!(
            "../../../datastar-parity/fixtures/official/remove-elements-all-options.sse"
        ),
        include_bytes!("../../../datastar-parity/fixtures/official/remove-elements.sse"),
        include_bytes!("../../../datastar-parity/fixtures/official/remove-signals.sse"),
        include_bytes!("../../../datastar-parity/fixtures/official/two-events.sse"),
    ];
    let events = (0..512)
        .map(|index| FIXTURES[index % FIXTURES.len()].to_vec())
        .collect();
    Trace::new("pinned-official-fixture-mix", events)
}

fn trace(name: &str) -> Trace {
    match name {
        "todo" => todo_trace(),
        "dashboard" => dashboard_trace(),
        "official" => official_fixture_trace(),
        _ => panic!("unknown trace {name:?}; expected todo, dashboard, or official"),
    }
}

enum MeasuredEncoder {
    Standard(ExplicitBrotli),
    Recycled(RecyclingBrotli),
}

impl MeasuredEncoder {
    fn new(implementation: &str, quality: u32, window_bits: u32, cache_bytes: usize) -> Self {
        match implementation {
            "standard" => Self::Standard(ExplicitBrotli::with_settings(
                512 * 1024,
                quality,
                window_bits,
            )),
            "recycled" => Self::Recycled(RecyclingBrotli::with_settings(
                512 * 1024,
                quality,
                window_bits,
                cache_bytes,
            )),
            _ => panic!("unknown implementation {implementation:?}"),
        }
    }

    fn encode_event(&mut self, event: &[u8]) -> &[u8] {
        match self {
            Self::Standard(encoder) => encoder.encode_event_reusable(event).unwrap(),
            Self::Recycled(encoder) => encoder.encode_event_reusable(event).unwrap(),
        }
    }

    fn recycler_stats(&self) -> Option<RecyclerStats> {
        match self {
            Self::Standard(_) => None,
            Self::Recycled(encoder) => Some(encoder.recycler_stats()),
        }
    }

    fn finish(self) -> bytes::Bytes {
        match self {
            Self::Standard(encoder) => encoder.finish().unwrap(),
            Self::Recycled(encoder) => encoder.finish().unwrap(),
        }
    }
}

#[derive(Serialize)]
struct BenchmarkResult {
    implementation: String,
    evidence: &'static str,
    quality: u32,
    window_bits: u32,
    trace: &'static str,
    trace_digest_fnv64: String,
    cycles: usize,
    events: usize,
    input_bytes: u64,
    wire_bytes: u64,
    compression_ratio: f64,
    elapsed_ns: u128,
    ns_per_event: f64,
    flush_p50_ns: u128,
    flush_p95_ns: u128,
    flush_p99_ns: u128,
    flush_max_ns: u128,
    maximum_flush_bytes: usize,
    allocation_calls: u64,
    allocated_bytes: u64,
    allocation_calls_per_event: f64,
    allocated_bytes_per_event: f64,
    peak_live_allocations_delta: i64,
    peak_live_bytes_delta: i64,
    recycler: Option<SerializableRecyclerStats>,
}

#[derive(Serialize)]
struct SerializableRecyclerStats {
    allocation_requests: u64,
    cache_hits: u64,
    system_allocations: u64,
    uncached_frees: u64,
    cached_blocks: usize,
    cached_bytes: usize,
    peak_cached_bytes: usize,
}

impl From<RecyclerStats> for SerializableRecyclerStats {
    fn from(stats: RecyclerStats) -> Self {
        Self {
            allocation_requests: stats.allocation_requests,
            cache_hits: stats.cache_hits,
            system_allocations: stats.system_allocations,
            uncached_frees: stats.uncached_frees,
            cached_blocks: stats.cached_blocks,
            cached_bytes: stats.cached_bytes,
            peak_cached_bytes: stats.peak_cached_bytes,
        }
    }
}

fn percentile(values: &[u128], percentile: usize) -> u128 {
    let index = ((values.len() - 1) * percentile) / 100;
    values[index]
}

fn run_sample(
    implementation: &str,
    quality: u32,
    window_bits: u32,
    trace: &Trace,
    target_mib: usize,
    cache_bytes: usize,
) -> BenchmarkResult {
    let target_bytes = target_mib * 1024 * 1024;
    let cycles = target_bytes.div_ceil(trace.input_bytes).max(1);
    let events = cycles * trace.events.len();
    let mut latencies = Vec::with_capacity(events);
    let before = snapshot();
    reset_peaks(before);
    let started = Instant::now();
    let mut encoder = MeasuredEncoder::new(implementation, quality, window_bits, cache_bytes);
    let mut wire_bytes = 0_u64;
    let mut maximum_flush_bytes = 0;
    for _ in 0..cycles {
        for event in &trace.events {
            let flush_started = Instant::now();
            let output = encoder.encode_event(black_box(event));
            let flush_ns = flush_started.elapsed().as_nanos();
            latencies.push(flush_ns);
            maximum_flush_bytes = maximum_flush_bytes.max(output.len());
            wire_bytes += output.len() as u64;
            black_box(output);
        }
    }
    let recycler = encoder.recycler_stats().map(Into::into);
    let tail = encoder.finish();
    wire_bytes += tail.len() as u64;
    maximum_flush_bytes = maximum_flush_bytes.max(tail.len());
    black_box(&tail);
    drop(tail);
    let elapsed = started.elapsed();
    let after = snapshot();
    let peak_allocations = PEAK_LIVE_ALLOCS.load(Ordering::Relaxed);
    let peak_bytes = PEAK_LIVE_BYTES.load(Ordering::Relaxed);
    latencies.sort_unstable();
    let input_bytes = (trace.input_bytes * cycles) as u64;
    BenchmarkResult {
        implementation: format!("rust-{implementation}"),
        evidence: "measured-requested-allocation-sizes",
        quality,
        window_bits,
        trace: trace.name,
        trace_digest_fnv64: format!("{:016x}", trace.digest),
        cycles,
        events,
        input_bytes,
        wire_bytes,
        compression_ratio: wire_bytes as f64 / input_bytes as f64,
        elapsed_ns: elapsed.as_nanos(),
        ns_per_event: elapsed.as_nanos() as f64 / events as f64,
        flush_p50_ns: percentile(&latencies, 50),
        flush_p95_ns: percentile(&latencies, 95),
        flush_p99_ns: percentile(&latencies, 99),
        flush_max_ns: *latencies.last().unwrap(),
        maximum_flush_bytes,
        allocation_calls: after.alloc_calls - before.alloc_calls,
        allocated_bytes: after.allocated - before.allocated,
        allocation_calls_per_event: (after.alloc_calls - before.alloc_calls) as f64 / events as f64,
        allocated_bytes_per_event: (after.allocated - before.allocated) as f64 / events as f64,
        peak_live_allocations_delta: peak_allocations - before.live_allocations,
        peak_live_bytes_delta: peak_bytes - before.live_bytes,
        recycler,
    }
}

#[derive(Serialize)]
struct MemoryResult {
    implementation: String,
    evidence: &'static str,
    quality: u32,
    window_bits: u32,
    trace: &'static str,
    streams: usize,
    inline_bytes_per_stream: usize,
    heap_live_allocations: i64,
    heap_requested_bytes: i64,
    heap_requested_bytes_per_stream: f64,
    total_requested_bytes_per_stream: f64,
    projected_1k_mib: f64,
    projected_10k_gib: f64,
    peak_heap_requested_bytes: i64,
    allocation_calls: u64,
    allocated_bytes: u64,
}

fn memory(
    implementation: &str,
    quality: u32,
    window_bits: u32,
    streams: usize,
    trace: &Trace,
    cache_bytes: usize,
) -> MemoryResult {
    let mut encoders = Vec::with_capacity(streams);
    let before = snapshot();
    reset_peaks(before);
    for index in 0..streams {
        let mut encoder = MeasuredEncoder::new(implementation, quality, window_bits, cache_bytes);
        black_box(encoder.encode_event(&trace.events[index % trace.events.len()]));
        encoders.push(encoder);
    }
    let after = snapshot();
    let heap_bytes = after.live_bytes - before.live_bytes;
    let inline_bytes = match implementation {
        "standard" => size_of::<ExplicitBrotli>(),
        "recycled" => size_of::<RecyclingBrotli>(),
        _ => unreachable!(),
    };
    let per_stream = heap_bytes as f64 / streams as f64 + inline_bytes as f64;
    let result = MemoryResult {
        implementation: format!("rust-{implementation}"),
        evidence: "measured-requested-allocation-sizes-plus-inline-state",
        quality,
        window_bits,
        trace: trace.name,
        streams,
        inline_bytes_per_stream: inline_bytes,
        heap_live_allocations: after.live_allocations - before.live_allocations,
        heap_requested_bytes: heap_bytes,
        heap_requested_bytes_per_stream: heap_bytes as f64 / streams as f64,
        total_requested_bytes_per_stream: per_stream,
        projected_1k_mib: per_stream * 1_000.0 / (1024.0 * 1024.0),
        projected_10k_gib: per_stream * 10_000.0 / (1024.0 * 1024.0 * 1024.0),
        peak_heap_requested_bytes: PEAK_LIVE_BYTES.load(Ordering::Relaxed) - before.live_bytes,
        allocation_calls: after.alloc_calls - before.alloc_calls,
        allocated_bytes: after.allocated - before.allocated,
    };
    black_box(encoders);
    result
}

#[derive(Serialize)]
struct SteadyResult {
    implementation: String,
    quality: u32,
    window_bits: u32,
    trace: &'static str,
    warmup_events: usize,
    measured_events: usize,
    allocation_calls: u64,
    deallocation_calls: u64,
    allocated_bytes: u64,
    deallocated_bytes: u64,
    live_allocations_delta: i64,
    live_bytes_delta: i64,
    recycler_before: Option<SerializableRecyclerStats>,
    recycler_after: Option<SerializableRecyclerStats>,
}

fn steady(
    implementation: &str,
    quality: u32,
    window_bits: u32,
    trace: &Trace,
    measured_events: usize,
    cache_bytes: usize,
) -> SteadyResult {
    let warmup_events = 2_048;
    let mut encoder = MeasuredEncoder::new(implementation, quality, window_bits, cache_bytes);
    for index in 0..warmup_events {
        black_box(encoder.encode_event(&trace.events[index % trace.events.len()]));
    }
    let recycler_before = encoder.recycler_stats().map(Into::into);
    let before = snapshot();
    for index in 0..measured_events {
        black_box(encoder.encode_event(&trace.events[index % trace.events.len()]));
    }
    let after = snapshot();
    let recycler_after = encoder.recycler_stats().map(Into::into);
    black_box(encoder);
    SteadyResult {
        implementation: format!("rust-{implementation}"),
        quality,
        window_bits,
        trace: trace.name,
        warmup_events,
        measured_events,
        allocation_calls: after.alloc_calls - before.alloc_calls,
        deallocation_calls: after.dealloc_calls - before.dealloc_calls,
        allocated_bytes: after.allocated - before.allocated,
        deallocated_bytes: after.deallocated - before.deallocated,
        live_allocations_delta: after.live_allocations - before.live_allocations,
        live_bytes_delta: after.live_bytes - before.live_bytes,
        recycler_before,
        recycler_after,
    }
}

fn parse<T: std::str::FromStr>(value: Option<String>, name: &str) -> T {
    value
        .unwrap_or_else(|| panic!("missing {name}"))
        .parse()
        .unwrap_or_else(|_| panic!("invalid {name}"))
}

fn print_json<T: Serialize>(value: &T) {
    println!("{}", serde_json::to_string(value).unwrap());
}

fn main() {
    let mut arguments = std::env::args().skip(1);
    match arguments.next().as_deref() {
        Some("run") => {
            let implementation = arguments.next().expect("missing implementation");
            let quality = parse(arguments.next(), "quality");
            let window_bits = parse(arguments.next(), "window bits");
            let trace = trace(&arguments.next().expect("missing trace"));
            let samples: usize = parse(arguments.next(), "samples");
            let target_mib = parse(arguments.next(), "target MiB");
            let cache_kib = arguments
                .next()
                .map(|value| value.parse::<usize>().expect("invalid cache KiB"))
                .unwrap_or(DEFAULT_CACHE_BYTES / 1024);
            for _ in 0..samples {
                print_json(&run_sample(
                    &implementation,
                    quality,
                    window_bits,
                    &trace,
                    target_mib,
                    cache_kib * 1024,
                ));
            }
        }
        Some("screen") => {
            let implementation = arguments.next().expect("missing implementation");
            let trace = trace(&arguments.next().expect("missing trace"));
            let target_mib = arguments
                .next()
                .map(|value| value.parse().expect("invalid target MiB"))
                .unwrap_or(2);
            for quality in 0..=6 {
                for window_bits in 10..=18 {
                    print_json(&run_sample(
                        &implementation,
                        quality,
                        window_bits,
                        &trace,
                        target_mib,
                        DEFAULT_CACHE_BYTES,
                    ));
                }
            }
        }
        Some("memory") => {
            let implementation = arguments.next().expect("missing implementation");
            let quality = parse(arguments.next(), "quality");
            let window_bits = parse(arguments.next(), "window bits");
            let streams = parse(arguments.next(), "streams");
            let trace = trace(&arguments.next().expect("missing trace"));
            let cache_kib = arguments
                .next()
                .map(|value| value.parse::<usize>().expect("invalid cache KiB"))
                .unwrap_or(DEFAULT_CACHE_BYTES / 1024);
            print_json(&memory(
                &implementation,
                quality,
                window_bits,
                streams,
                &trace,
                cache_kib * 1024,
            ));
        }
        Some("steady") => {
            let implementation = arguments.next().expect("missing implementation");
            let quality = parse(arguments.next(), "quality");
            let window_bits = parse(arguments.next(), "window bits");
            let trace = trace(&arguments.next().expect("missing trace"));
            let events = parse(arguments.next(), "events");
            let cache_kib = arguments
                .next()
                .map(|value| value.parse::<usize>().expect("invalid cache KiB"))
                .unwrap_or(DEFAULT_CACHE_BYTES / 1024);
            print_json(&steady(
                &implementation,
                quality,
                window_bits,
                &trace,
                events,
                cache_kib * 1024,
            ));
        }
        _ => panic!(
            "usage: brotli_footprint run IMPL Q W TRACE SAMPLES MIB [CACHE_KIB] | screen IMPL TRACE [MIB] | memory IMPL Q W STREAMS TRACE [CACHE_KIB] | steady IMPL Q W TRACE EVENTS [CACHE_KIB]"
        ),
    }
}
