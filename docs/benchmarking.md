# Benchmarking and invariant validation

`scripts/benchmark.py` is the supported entrypoint for server validation and
local performance work. It builds isolated fixtures, invokes the Rust protocol
driver, records versioned JSONL, and compares repeated runs. The Rust driver is
also usable directly through a strict versioned scenario file.

The suite deliberately has two evidence layers:

- `check` replaces the accepted TCP stream with bounded in-memory duplex I/O.
  Hyper protocol handling, admission, the compiled application's real Roc
  callbacks, response streaming, compression, and shutdown all remain in the
  server process. This makes lifecycle, cleanup, allocation, and achieved
  high-water assertions socketless and repeatable enough for CI. It does not
  claim deterministic task scheduling or exhaustive overload coverage.
- `measure` uses the production host and real loopback TCP. Its throughput,
  latency, RSS/PSS, CPU, fault, thread, and file-descriptor observations are
  machine-specific evidence. Compare runs on the same controlled machine; do
  not turn their values into portable CI thresholds.

## Substituted-transport checks and allocations

Run the CI-safe ordinary HTTP and SSE scenarios with:

```sh
python scripts/benchmark.py check
```

The current gate covers ordinary HTTP/1.1 and HTTP/2, 1,024 simultaneous
logical HTTP/1.1 connections, and 64-stream identity and Brotli SSE lifecycle
runs. It asserts that those concurrency levels were actually reached. Boundary
rejection, parked cancellation, scheduler contention, and process capacity stay
in the real-listener suite below unless a focused socketless scenario is added.

The instrumented host uses a measurement epoch after warmup. Reports separate
Roc-requested allocations, their Rust allocator backing, other host
allocations, and allocations made by the simulated client. It also asserts that
Roc allocations and active/queued server resources return to zero after the
measured work. Persist a run for comparison with:

```sh
python scripts/benchmark.py check \
  --label before \
  --output target/benchmarks/check-before.jsonl
```

Allocation/deallocation/reallocation totals count operations during the epoch.
Live and peak-live fields track the cohort born during that epoch, so cleanup of
warmup allocations cannot make them negative or hide a measured allocation
that remains live at the epoch boundary.

These allocation counts describe the substituted transport workload. They do
not describe process RSS or kernel socket memory.

## Real HTTP and SSE load

An ordinary HTTP run includes minimal, hosted-effect, and weighted mixed
routes over HTTP/1.1 and HTTP/2:

```sh
python scripts/benchmark.py measure \
  --suite http \
  --label before \
  --output target/benchmarks/http-before.jsonl
```

The SSE suite covers finite hot streams, timer gaps, a 125 KB/5 Hz proxy for a
2,500-element re-render, transition-heavy SSE versus ordinary-request fairness,
parked-stream memory, cancellation, identity, and Brotli. This is the standard
thousand-user capacity run:

```sh
python scripts/benchmark.py measure \
  --suite sse \
  --protocol http1 \
  --parked-streams 100,1000,2500 \
  --samples 3 \
  --label before \
  --output target/benchmarks/sse-before.jsonl
```

During a parked test the Rust driver waits until every stream has received
response bytes, emits a `streams_ready` phase, and keeps the bodies alive while
the Python orchestrator samples the server. It then drops them concurrently and
records a recovered snapshot. The tool checks the per-process file-descriptor
limit before a large HTTP/1.1 run. Use HTTP/2 separately to evaluate multiplexed
streams rather than one socket per stream.

The fixture admits 4,096 SSE streams. Exercise the exact rejection boundary and
one-stream recovery explicitly with `--capacity-check`. This case can consume
substantial memory, especially with per-stream Brotli state, so it is not part
of CI or the default local run.

The 2,500-element route is a fixed byte-shape server proxy, not a browser
benchmark. It models 25 full updates at 200 ms intervals; it does not claim to
measure DOM morphing or a particular application renderer. Add an application
fixture when rendering cost is the question.

## SQLite workloads

SQLite load is owned by the same entrypoint. It creates or reuses a deterministic
fixture and runs pool, writer, read/write mixture, slow-query, large-result,
blob, and shared-statement scenarios:

```sh
python scripts/benchmark.py measure \
  --suite sqlite \
  --sqlite-suite full \
  --label before \
  --output target/benchmarks/sqlite-before.jsonl
```

Use repeated `--only TEXT` options for focused engineering runs. `--help`
lists worker, client, duration, sample, protocol, encoding, pool, and fixture
controls.

On Linux, use `--server-cpu` and `--client-cpu` with disjoint `taskset` CPU
lists when scheduler isolation matters, for example `--server-cpu 2` and
`--client-cpu 3-5`. The selected affinity and worker counts are recorded in
the JSONL run configuration. CPU pinning controls placement; isolating those
CPUs from unrelated machine activity remains the operator's responsibility.

## Comparing runs

```sh
python scripts/benchmark.py compare \
  target/benchmarks/before.jsonl \
  target/benchmarks/after.jsonl \
  --markdown target/benchmarks/comparison.md
```

For HTTP, the comparison's primary and secondary columns are requests/second
and p99 latency. For finite SSE they are events/second and completion p99; for
parked streams they are opened streams and first-byte p99; for parked memory
they are RSS and PSS in KiB; and for substituted-transport allocation records
they are allocated bytes per request and peak live bytes.

## Direct Rust scenarios

The driver accepts one JSON object with `schema_version: 1`, a stable name,
`request`, `sse`, or `sse_hold` workload, protocol, address, routes, duration,
timeouts, concurrency, connection count, client threads, and SSE event/encoding
expectations. Unknown fields and schema versions fail closed.

```sh
cargo run --locked --release \
  --features benchmark-driver \
  --bin benchmark-driver -- \
  --scenario-file scenario.json
```

The driver keeps latency histograms and SSE parsing bounded. Finite responses
are parsed incrementally, including Brotli, rather than accumulated in memory.
It intentionally does not render in a headless browser.

## Interpretation

Thousands of parked connections answer a different question from thousands of
events. Always record both axes: live connections, streams actively producing,
events per stream and cadence, payload size/compressibility, ordinary traffic,
protocol, compression, server workers, handler/queue/stream limits, errors, and
resource recovery. A server that holds 2,500 idle streams may still fail when
all 2,500 become ready together; the finite, timer, fairness, and capacity
scenarios exist to distinguish those cases.
