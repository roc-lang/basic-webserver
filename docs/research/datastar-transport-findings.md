# Datastar SSE transport research findings

Status: preliminary transport evidence; browser, proxy, complete HTTP/1.1 and
HTTP/2, and cross-target gates remain open

Date: 2026-08-01

Research branch: `research/datastar-transport`

Performance source commit: `d09423ac5285a582049c41778df29f41ccda96cb`

Output-bound probe source commit: `9b19f81`

## Scope

This track adversarially tested the host-side streaming and Brotli assumptions
in [`docs/datastar-experiment.md`](../datastar-experiment.md). It does not change
the accepted platform contract in [`design.md`](../../design.md), which still
lists Roc-produced SSE runtimes as a non-goal.

The disposable harness at
[`research/datastar-transport`](../../research/datastar-transport) imports the
real `src/compression.rs`. Its exact encoder settings and dependency versions
therefore match the host baseline. It adds:

- a persistent encoder that exercises the existing `ContentEncoder`;
- an explicit low-level Brotli adapter with separate PROCESS, FLUSH, FINISH,
  and abort paths;
- a Hyper `Body` prototype whose frame and byte budget is reserved before an
  encoder is mutated;
- cancellation, bounded-backpressure, progressive-decode, heartbeat, clean
  finish, and injected-failure tests;
- a direct Go Brotli q4/LGWin18 semantic comparison;
- configured and idiomatic-default official Datastar Go SDK comparisons; and
- deterministic retained-memory and incompressible-candidate observations.

Evidence labels below use the shared research program's definitions.

## Pins and environment

- **Measured:** Rust `1.97.1`; release profile.
- **Measured:** checksum-verified Go `1.26.5 linux/amd64`; archive SHA-256
  `5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053`.
- **Specified:** Datastar Go SDK `v1.2.2`, commit
  `60dc10ebdaad3207d71e4bd8c1f158e65bb4acb0`.
- **Measured:** `brotli` Rust crate `8.0.4` and `andybalholm/brotli` Go module
  `1.2.0`.
- **Measured:** Linux x86-64, AMD Ryzen 7 9700X, 16 logical CPUs, 30.46 GiB
  RAM, file-descriptor limit 1,048,576.
- **Measured:** all timed runs were pinned to logical CPU 2. Frequency boost
  remained enabled, so min/max dispersion is reported and these values are not
  portable performance guarantees.

Exact machine output and raw samples are committed under
[`research/datastar-transport/results`](../../research/datastar-transport/results).

## Hard transport findings

### One bounded response body remains the right integration point

- **Observed:** `response::finalize_response` already accepts an unknown-length
  native body, removes `Content-Length`, and rejects application control of
  HTTP framing. SSE does not need a second response authority.
- **Observed:** the HTTP/1.1 path wraps `ServerBody` in `TrackedResponseBody`;
  body-frame inactivity and socket-write inactivity have separate progress
  deadlines. A heartbeat must therefore be strictly more frequent than the
  response-body idle deadline after configuration clamping.
- **Observed:** the HTTP/2 sender polls one body frame before waiting for flow
  control capacity, then divides it according to granted capacity. The global
  and per-stream budget must include that one already-produced maximum frame.
- **Inferred:** one event per body frame gives useful event-level ownership and
  telemetry, but a frame becoming available to Hyper is not proof of browser
  or proxy visibility. The browser/proxy gate remains mandatory.

The bounded prototype reserves both one frame slot and a conservative maximum
encoded byte charge before compression. The charge remains live until Hyper
consumes the frame. Body drop atomically cancels the producer and releases all
queued and reserved accounting. Six tests imported with the host compression
module and seven transport/lifecycle tests passed in release mode.

### `CompressorWriter` is not a safe SSE lifecycle primitive

- **Observed by test and pinned source inspection:** dropping Rust
  `brotli::CompressorWriter` performs FINISH and may synchronously write a tail.
  It therefore cannot implement "disconnect aborts without finishing output."
- **Observed by injected failure:** `CompressorWriter::into_inner` performs
  FINISH but discards its error. Consequently the existing
  `ContentEncoder::finish` reports `Ok` even when its Brotli sink rejects the
  final bytes.
- **Observed:** the public low-level `BrotliEncoderStateStruct` API can perform
  PROCESS and FLUSH, propagate FINISH failure, and call
  `BrotliEncoderDestroyInstance` on abort without producing output. Its output
  is byte-identical to the writer adapter for the tested traces.
- **Inferred:** production SSE must use a reviewed explicit-state adapter or a
  different library with equivalent lifecycle operations. Wrapping the current
  `CompressorWriter` is a failed hypothesis. The low-level Rust API is pinned
  but not a comfortable stable abstraction; an upstream-supported adapter is
  preferable.

### Incremental decode works, but the output bound is not proven

- **Observed:** after every event and `: keepalive\n\n` flush, the accumulated
  Brotli prefix independently decodes to all input through that flush. Normal
  FINISH adds a one-byte tail in these traces and the complete stream decodes.
- **Observed:** across 100 deterministic xorshift incompressible-candidate
  events per size, maximum FLUSH output was input plus 3 bytes at 256, 4,096,
  and 65,536 bytes, and input plus 7 bytes at 1 MiB.
- **Observed:** those values fit below the crate's exported
  `BrotliEncoderMaxCompressedSize` result.
- **Not proven:** that exported function documents a one-shot FINISH bound. It
  does not establish a mathematical maximum for one item in a persistent
  stream with an arbitrary history and repeated FLUSH operations. The corpus
  maximum must not be turned into a production reservation constant.

Bounded failure is achievable today: a fixed output ceiling closes the stream
if exhausted. The release-quality gate is stronger. It must either derive a
reviewable bound for the selected encoder and parameters, obtain an upstream
streaming bound, or select an adapter/library that exposes one. A valid maximum
event must not fail depending on data history.

## Controlled Rust/Go comparison

### Method

Each sample compressed approximately 64 MiB of preframed, repetitive,
Datastar-Go-v1.2.2-shaped events through one persistent stream, flushing every
event. There was a 100-event warmup and seven recorded samples per case.

The semantic baseline used Brotli quality 4 and LGWin 18 and included a clean
FINISH in both Rust and direct Go. It produced byte-identical output. The
official SDK cases include SDK framing, mutex, buffer-pool, and flush overhead.
The SDK exposes no normal FINISH operation, so those cases are deliberately
labeled non-equivalent on clean EOF.

This corpus repeats one event and is a best case for persistent dictionary
reuse, not a substitute for realistic evolving HTML and signal traces.

### Semantic-equivalence compressor results

| Framed event | Rust low-level median (min–max) | Go direct median (min–max) | Rust throughput advantage | Rust allocations/event | Go setup-amortized allocations/event |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 240 B | 1,747 ns (1,737–1,784) | 2,392 ns (2,297–2,457) | 1.37x | 17.00 calls / 20,438 B | 0.00007 calls / 4 B |
| 4,080 B | 3,239 ns (3,233–3,282) | 9,745 ns (9,736–9,766) | 3.01x | 17.00 calls / 20,508 B | 0.0012 calls / 74 B |
| 65,520 B | 27,771 ns (27,697–27,833) | 129,798 ns (129,297–130,165) | 4.67x | 17.01 calls / 22,485 B | 0.0186 calls / 2,091 B |

- **Measured:** Rust meets the throughput target in this compressor-only
  microbenchmark and emits exactly the same bytes as direct Go.
- **Measured:** Rust does not meet Go's steady-state allocation behavior. Both
  the existing writer and explicit-state adapter allocate and free roughly 20
  KiB across 17 calls per flush. The maximum output frame in the repetitive
  corpus was only 128 bytes, so frame ownership alone does not explain the
  churn.
- **Gate:** profile and remove or pool the Rust crate's per-FLUSH scratch
  allocations without increasing retained per-stream state past the Go target.
  Repeat the comparison after adding the real body queue and socket transport.

### Idiomatic official SDK results

The SDK default uses Brotli quality 6 and automatic window selection. Median
costs were 2,832 ns, 9,366 ns, and 109,513 ns for the three event sizes. Rust
q4/LGWin18 was respectively 1.62x, 2.89x, and 3.94x faster, but this is a
product-default comparison rather than an encoder-equivalence result.

The configured SDK q4/LGWin18 allocated approximately 8–12 times per event;
the idiomatic default did likewise. Those include SDK framing and are not
direct evidence about a future Roc framing ABI.

### Retained encoder memory

| Live flushed streams | Rust q4/LGWin18 | Go direct q4/LGWin18 | Go SDK q4/LGWin18 | Go SDK q6/auto |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 534,320 B/stream | 547,598 B/stream | 548,272 B/stream | 2,145,863 B/stream |
| 1,000 | 534,320 B/stream | 547,427 B/stream | 548,097 B/stream | not run (projected host cost was too high) |

- **Measured:** Rust retained 2.4% less encoder memory than direct Go with the
  same q4/LGWin18 parameters and about 75% less than the SDK default.
- **Inferred:** 10,000 compressed idle streams would retain about 4.98 GiB of
  Rust encoder state before sockets, tasks, Roc machines, body buffers, and
  metrics. That architecture run is feasible only on a deliberately sized
  reference host and argues strongly against advertising 10,000 as a default.
- **Gate:** measure fixed encoder state before and after the proposed scratch
  allocation optimization; allocation wins must not hide a retained-memory
  regression.

## Go SDK differences the Roc contract should not copy

- **Specified/Observed with the parity track:** canonical pinned-client and
  WHATWG fixtures end an event with two LF bytes. Go SDK v1.2.2 emits three;
  the extra blank record is ignored by the client. The byte-equivalence corpus
  here retains three only to compare compressor cost. Production Roc framing
  should emit canonical two-LF records.
- **Observed with the parity track:** `ServerSentEventGenerator` retains its
  compression writer only as `io.Writer` and exposes no `Close`. Normal SDK EOF
  is therefore an unfinished Brotli stream; an independent decoder returns an
  unfinished-stream error. The direct Go and Rust clean-FINISH outputs are
  exactly one byte longer in this corpus.
- **Candidate contract consequence:** Roc must FINISH on deliberate normal EOF
  and abort without FINISH on disconnect. Go SDK behavior is an ergonomic
  reference, not permission to weaken the wire lifecycle.

## Precise changes recommended for the experiment spikes

1. In Spike 2, say that body capacity is reserved before producing or encoding
   one item. Account for one frame already pulled before HTTP/2 flow-control
   capacity is granted.
2. In Spike 2, require heartbeat intervals to be validated below the common
   response-progress deadline, with enough margin for scheduling delay.
3. In Spike 5, replace reuse of `ContentEncoder` with an explicit requirement
   for distinct `flush_event`, fallible `finish`, and non-emitting `abort`
   operations. Name the current `CompressorWriter` behavior as a failed path.
4. Keep a fixed output ceiling as the safety fallback, but do not call the
   incompressible corpus maximum or one-shot max-size function a proven
   per-FLUSH reservation bound.
5. Add steady-state allocations/event to the performance gate. Profile the
   observed 17-call/~20-KiB Rust churn and repeat after the body and socket path
   are present.
6. Split protocol fixtures from comparison corpora: canonical Datastar uses a
   two-LF terminator; a separately labeled `go-sdk-v1.2.2` corpus uses three.
7. Require an independent decoder to accept normal FINISH and explicitly test
   abort without a tail. Do not use the official SDK's unfinished normal EOF as
   the expected contract.
8. Keep q4/LGWin18 as the current semantic-comparison candidate. It beats Go
   throughput and retained memory here, but remains provisional until realistic
   traces, ordinary-request interference, browsers, and proxies pass.

## Gates still open

- A real basic-webserver listener proving first-event visibility over HTTP/1.1
  and HTTP/2, including one blocked HTTP/2 stream beside an unrelated stream.
- Browser processing of compressed event one before event two exists.
- Reference NGINX buffering/no-buffering and timeout measurements.
- Slow-reader closure latency and global/per-stream output high-water marks.
- Producer scheduling proving compression never runs on async transport
  workers and ordinary Roc handlers retain capacity during wake herds.
- A proven persistent-FLUSH output bound or a deliberate encoder replacement.
- Removal or justified retention of Rust's per-event allocation churn.
- Realistic changing Datastar HTML/signal traces instead of a repeated payload.
- Debug failure injection, disconnect during compression, and shutdown races
  through the integrated host lifecycle.
- Independent cross-target decoding and retained-memory validation on every
  supported native runner.

None of these gaps is evidence against the overall host-scheduled stream
machine. They mean the streaming Brotli and transport gates are not yet closed.
