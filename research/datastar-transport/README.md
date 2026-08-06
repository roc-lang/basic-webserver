# Datastar transport feasibility spike

This disposable crate tests the bounded Hyper-body and streaming-Brotli
hypotheses in `docs/datastar-experiment.md`. It imports the repository's real
`src/compression.rs`, including the pinned Brotli crate and quality/window
configuration, but is not linked into the production host.

The research contract and evidence labels live in
`docs/research/datastar-research-program.md` on the coordinating experiment
branch. Results here must distinguish semantic-equivalence comparisons from
the official Go SDK's idiomatic defaults.

Run the correctness checks with:

```sh
cargo test --manifest-path research/datastar-transport/Cargo.toml --release
```

The performance comparison is intentionally compressor-focused; it does not
claim to close the real-listener, browser, proxy, or cross-target gates.

## Reproduce the recorded run

The committed measurements used Rust 1.97.1, checksum-verified Go 1.26.5,
Datastar Go v1.2.2, release builds, and logical CPU 2. The benchmark performs a
100-event warmup before seven recorded samples. Each sample processes about 64
MiB of preframed input through one persistent stream.

```sh
cargo build --manifest-path research/datastar-transport/Cargo.toml --release
taskset -c 2 research/datastar-transport/target/release/datastar-transport-spike benchmark 7
taskset -c 2 research/datastar-transport/target/release/datastar-transport-spike observe-bounds 100
taskset -c 2 research/datastar-transport/target/release/datastar-transport-spike memory 1000

cd research/datastar-transport/go
GOTOOLCHAIN=local /tmp/go1.26.5/bin/go test ./...
GOTOOLCHAIN=local /tmp/go1.26.5/bin/go build -trimpath -o /tmp/datastar-go-transport-reference .
taskset -c 2 /tmp/datastar-go-transport-reference benchmark 7
taskset -c 2 /tmp/datastar-go-transport-reference memory direct 1000
taskset -c 2 /tmp/datastar-go-transport-reference memory sdk-q4 1000
taskset -c 2 /tmp/datastar-go-transport-reference memory sdk-default 100
```

The Go toolchain archive was `go1.26.5.linux-amd64.tar.gz`, SHA-256
`5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053`.
The official SDK source was tag `v1.2.2`, commit
`60dc10ebdaad3207d71e4bd8c1f158e65bb4acb0`.

`datastar_event` deliberately reproduces the Go SDK v1.2.2 three-LF event
terminator for a byte-equivalent compressor comparison. It is not a canonical
Datastar fixture: the pinned client's golden fixture and WHATWG framing end an
event with two LFs. Production Roc framing should use the canonical form.

Raw results and the machine description are under [`results`](results). The
numbers are indicative single-host measurements, not a portable guarantee.

## Footprint and Pareto follow-up

`brotli_footprint` adds canonical two-LF Datastar traces, exact requested-size
allocation accounting, a bounded scratch recycler, reusable event output, and
a matched Go runner. Its traces are `todo`, `dashboard`, `official` (Rust
only), `heartbeat`, and `large` (changing approximately 64 KiB HTML events).

```sh
cargo build --manifest-path research/datastar-transport/Cargo.toml --release --bin brotli_footprint
taskset -c 2 research/datastar-transport/target/release/brotli_footprint screen recycled todo 2
taskset -c 2 research/datastar-transport/target/release/brotli_footprint run recycled 1 11 todo 7 16
taskset -c 2 research/datastar-transport/target/release/brotli_footprint run standard 3 12 todo 7 16
research/datastar-transport/target/release/brotli_footprint steady recycled 1 11 todo 10000
research/datastar-transport/target/release/brotli_footprint memory recycled 1 11 10000 todo 256 1
research/datastar-transport/target/release/brotli_footprint verify 1 11 large

cd research/datastar-transport/go
GOTOOLCHAIN=local /tmp/go1.26.5/bin/go build -trimpath -o /tmp/datastar-go-brotli-footprint ./cmd/footprint
taskset -c 2 /tmp/datastar-go-brotli-footprint run 1 11 todo 7 16
taskset -c 2 /tmp/datastar-go-brotli-footprint memory 1 11 100 todo 512
```

Rust memory results add the encoder's inline size to exact requested heap
bytes; they exclude allocator metadata. Go memory results use `runtime.MemStats`
after a forced GC. `memory` activates every retained encoder before measuring;
its final argument can run a whole trace through each encoder to expose mature
window and cache growth. See
[`docs/research/datastar-brotli-footprint-findings.md`](../../docs/research/datastar-brotli-footprint-findings.md)
for the interpretation and recommendation.

## Bounded resumable output follow-up

The low-level spike also tests the alternative to proving a maximum compressed
size for an entire persistent-stream item. `ResumableBrotli` advances one
PROCESS, FLUSH, or FINISH operation only into caller-owned capacity which has
already been reserved by `BoundedBody`. If that capacity fills, encoder state
and the input offset are retained and the operation resumes only after the body
returns capacity.

`resumable_brotli_never_advances_without_one_bounded_frame` deliberately uses
one queued frame of only seven bytes and a 64 KiB Datastar-shaped item. It
passes for q1/LGWin11 and q3/LGWin12, forces each operation to span multiple
frames, proves backpressure between frames, incrementally decodes the FLUSHed
prefix, and independently decodes the FINISHed stream.

```sh
cargo test --manifest-path research/datastar-transport/Cargo.toml --release \
  resumable_brotli_never_advances_without_one_bounded_frame
```

This is a correctness and boundedness result, not an allocation result. The
test copies each produced slice into a new `Bytes`; production feasibility still
requires reusable owned frames and integration with the real response body,
listener accounting, deadlines, HTTP/2 flow control, and cancellation.

## Owned-frame allocation follow-up

The next fixture replaces that copy with one preallocated vector whose custom
`Buf` frame returns the slot and wakes the producer from `Drop`. It compares a
candidate internal `ServerData::Pooled` wrapper with the compatibility path
required by the former `ServerBody::Data = Bytes`.

```sh
cargo build --manifest-path research/datastar-transport/Cargo.toml --release --bin brotli_footprint
research/datastar-transport/target/release/brotli_footprint body-ownership server-data identity 10000
research/datastar-transport/target/release/brotli_footprint body-ownership server-data q1 10000
research/datastar-transport/target/release/brotli_footprint body-ownership server-data q3 10000
research/datastar-transport/target/release/brotli_footprint body-ownership bytes-owner identity 10000
research/datastar-transport/target/release/brotli_footprint body-ownership bytes-owner q1 10000
research/datastar-transport/target/release/brotli_footprint body-ownership bytes-owner q3 10000
```

After 2,048 warmup events, the `server-data` runs make zero allocator calls for
all three modes. `bytes-owner` makes exactly one 56-byte allocation and free per
output frame because bytes 1.11.1 boxes every owner. Cancellation tests cover
abandoned reservations, queued frames, and transport-owned frames, including
waking a blocked producer. Raw results and the resulting internal type decision
are in
[`datastar-frame-ownership-findings.md`](../../docs/research/datastar-frame-ownership-findings.md).

## Production body allocation follow-up

The controlled fixture drives the production-internal `SseBody`, production
`ServerData` pool, and production resumable encoder. It reuses one item and one
frame slot, warms one persistent stream for 2,048 events, and counts the next
10,000 events. Stream construction and FINISH are outside the window.

```sh
cargo build --manifest-path research/datastar-transport/Cargo.toml --release --bin brotli_footprint
research/datastar-transport/target/release/brotli_footprint production-body identity 10000
research/datastar-transport/target/release/brotli_footprint production-body q1-standard 10000
research/datastar-transport/target/release/brotli_footprint production-body q1 10000
research/datastar-transport/target/release/brotli_footprint production-body q3 10000
```

Identity, recycled q1, and standard q3 make zero calls to the counted global
allocator. Standard q1 makes four allocations and requests 14,096 bytes per
event; the bounded 256 KiB recycler removes them without changing frame or wire
counts. The body also passes normal H1/H2 and stalled-H2 cancellation tests.
Raw results and remaining boundaries are in
[`datastar-production-body-findings.md`](../../docs/research/datastar-production-body-findings.md).
