# Datastar research synthesis and spike contract

Status: callable correctness gate cleared; implementation performance gates remain

Date: 2026-08-01

Branch: `datastar-experiment`

This document reconciles the independent Datastar protocol, Roc ABI,
transport/browser, and Brotli-footprint tracks. It records the agreed direction
for the next feasibility spikes. It is not an accepted platform contract and
does not change [`design.md`](../../design.md).

## Bottom line

The research supports a coherent first-class SSE and Datastar design for
`basic-webserver`:

- Roc constructs typed events and a finite, pull-driven stream machine.
- The Rust host owns scheduling, timers, admission, backpressure, heartbeat,
  cancellation, HTTP framing, compression, and shutdown.
- A parked stream retains opaque Roc state but no Roc stack, worker, or native
  thread.
- Finite Datastar actions use the ordinary response path; progressive and
  persistent actions use the same bounded SSE body with different producers.
- Datastar v1.0.2 is the compatibility authority. The Go SDK is an ergonomics
  and performance reference, not a wire authority.
- Brotli is first class, automatically negotiated, continuously streamed,
  flushed after each logical item, FINISHed only on normal close, and abandoned
  without a tail on cancellation.
- Brotli needs two named operating points rather than pretending one encoder
  profile serves every population: a full-compression default candidate and an
  explicitly selected scale profile. Identity remains a deliberate result of
  negotiation, opt-out, admission, or endpoint policy.

This is enough agreement to proceed with focused implementation spikes. It is
not enough to select the final dynamic-stream ABI or update `design.md`.

The preferred boxed-callable ABI now passes the complete local lifecycle
through generated provided wrappers on Roc main `1c1ceccf`; the former generic
box teardown crash is fixed. The explicit-state fallback is also
lifecycle-correct, but its single-event transition is about 21 times slower
than unique Go state in the focused optimized benchmark. Immutable callable
continuation replacement likewise allocates once per step. A supported typed
adapter or compiler/glue ownership improvement must remove the remaining outer
ARC and per-step replacement allocation before the public API is frozen.

## Decisions we can make now

### Compatibility and framing

Pin stable Datastar client v1.0.2 at
`e24f04d43ca4445d662b4a035e5bfe9ed68de57c`. Regenerate fixtures and rerun the
browser matrix for any pin change.

Emit canonical WHATWG/Datastar records ending in two line feeds. Validate event
names, IDs, retry fields, and multiline data before framing. Do not copy the Go
SDK v1.2.2 extra blank record, permissive field injection, incomplete content
negotiation, or unfinished Brotli EOF.

Treat Datastar actions according to the pinned client:

| Method/mode | Signals transport |
| --- | --- |
| GET and DELETE | JSON in the `datastar` query parameter |
| POST, PUT, PATCH | JSON request body |
| Form mode | Form data, not Datastar signals JSON |

Clean status-200 EOF is terminal under stable `retry: auto`. `Last-Event-ID` is
scoped to one action retry/reopen loop. Durable replay, event IDs, and maximum
stream lifetime remain application policy rather than host delivery promises.

### Public application experience

Keep the public concepts small and typed:

- `Datastar.respond` for zero or more finite patches;
- declarative `Sse.steps` for common progressive sequences;
- `Sse.unfold!` or an equivalent pull machine for dynamic streams;
- typed element and signal patch constructors;
- typed event ID, retry, wait, close, and application-error outcomes;
- no compressor or response writer in application code.

The public program should ideally remain `{ init!, respond!, shutdown! }`, with
an opaque `Sse.Stream` response plan. The ABI used to advance that plan is an
implementation boundary, not something every application should manually
dispatch.

The fourth `stream!` entrypoint remains a supported feasibility fallback. A
compiled fixture proves route packages can keep their nominal state payload
and transitions private; the root application only enumerates route cases and
dispatches them. This corrects the earlier concern that all state
representations would become public. It does not remove central wiring or the
current transition cost.

Do not add a dynamic state bag, general callback registry, arbitrary byte
writer, application pub/sub bus, or one-thread-per-stream API to hide an ABI
limitation.

### Host runtime topology

Use one host-owned record per admitted stream. It contains the parked Roc
machine/state, wake description, cancellation state, body reservation,
optional Brotli encoder, accounting, and lifecycle metadata.

Only one advance for a stream may run at a time. A finite step returns a
bounded event batch, a wait/continue decision, a normal end, or an error. The
host does not advance again until output reservation and backpressure permit
it. Independent streams may advance concurrently within an explicit fair
admission unit reserved separately from ordinary request work.

Run the first step before committing headers unless an API explicitly requests
immediate commitment. This preserves ordinary pre-commit errors and prevents
admitting a stream that fails before producing a valid plan.

On cancellation while parked, drop state and encoder without invoking Roc. On
cancellation during an advance, allow the finite call to return, then release
the returned state and output rather than parking or publishing it. Body drop,
request accounting, shutdown, and encoder lifetime must converge on one
idempotent close path.

### HTTP and browser behavior

The SSE body remains a validated native response owned by the existing response
authority. It has unknown encoded length and does not create a second server or
connection-framing path.

Default response metadata candidates are:

```text
Content-Type: text/event-stream; charset=utf-8
Cache-Control: no-cache
Vary: Accept-Encoding
X-Accel-Buffering: no
```

`Content-Encoding: br` is added only when Brotli is selected before commitment.
`Cache-Control: no-transform` disables transformation. Applications never set
connection-specific framing fields or change coding after headers.

The generation-gated Firefox test is the minimum useful progressive assertion:
the DOM must apply event one while the server still proves event two has not
been generated. This has passed direct HTTP/1.1 and NGINX-fronted TLS HTTP/2
for identity, q4/LGWin18, and q1/LGWin11. Direct h2c also passes with curl.
Normal Brotli EOF produces a valid FINISH tail without retry; navigation abort
reaches producer cleanup without event two or a finish tail.

Keep Chromium/WebKit, the production listener, slow readers, H2 fairness,
proxy timeout/heartbeat behavior, and cross-target decoding as release gates.

### Brotli lifecycle and profiles

Use a low-level lifecycle adapter, not the current `CompressorWriter` wrapper:

1. PROCESS a fully framed item.
2. FLUSH it into reusable bounded encoder output.
3. Transfer/copy that output into an already-reserved owned body frame.
4. FINISH explicitly and fallibly on normal EOF.
5. Destroy encoder state without emitting output on cancellation.

The existing wrapper FINISHes from `Drop` and can lose finish errors; those are
the wrong semantics for disconnect and committed response failure.

The current Pareto decision is:

| Mode | Candidate | Mature todo state | 10k state | Steady system allocations | Role |
| --- | --- | ---: | ---: | ---: | --- |
| Minimum memory | recycled q1/LGWin10 | 18,400 B | 0.171 GiB measured | 0 | Explicit specialist option; wire/latency penalty |
| Scale | recycled q1/LGWin11 | 36,311 B | 0.338 GiB measured | 0 | Large changing-HTML populations |
| Full compression | standard q3/LGWin12 | 378,187 B | 3.522 GiB projected | 0 | Current automatic/default candidate |
| Rejected default | standard q4/LGWin18 | 1,180,995 B | 10.999 GiB projected | 16 allocs/event | Dominated for this product boundary |

Across activated corpora q1/LGWin11 retains 13,297–48,615 requested bytes per
stream. It is 1.22–1.25 times faster than matched Go, but its encoded/identity
ratio is 0.889 for the tiny official-fixture mix and 1.231 for heartbeat-only
traffic. It is not a universal compression default.

Standard q3/LGWin12 needs no recycler. It is 1.44–1.47 times faster than
matched Go, retains 4.7% less mature todo state under the documented
non-identical accounting methods, and saves roughly 90–92.6% on the active
Datastar corpora. It retains much more state than q1, so it requires separate
compressed-stream admission and cannot be the profile for an unconstrained
10,000-stream promise.

The host therefore needs a small endpoint/server policy selected before
headers:

- `Auto` (default candidate): q3/LGWin12 when compressed-stream capacity is
  available and negotiation selects Brotli;
- `Scale`: recycled q1/LGWin11 for endpoints designed for large changing-HTML
  populations;
- `Identity`: for explicit opt-out, compression-oracle risk, heartbeat-only
  traffic, or deployments that prefer connection scale to wire savings.

Whether `Scale` is a server route option, an `Sse.Options` field, or inferred
from a higher-level constructor is an ergonomics spike. Do not select profiles
from individual events and never switch mid-response. Preserve q1/LGWin10 in
the measured expert Pareto set, but do not make its roughly 3 ms periodic todo
flushes a default experience.

Reserve a separate finite compressed-stream unit before committing a Brotli
response. Account profile state, reusable encoder output, and body frames. If
compression capacity is unavailable, identity fallback is allowed only when
the negotiated request permits it and the policy says fallback is acceptable;
otherwise reject before commitment.

The exact repeated-FLUSH maximum output for a maximum incompressible item is
not yet proven. Observed maxima and the one-shot Brotli maximum-size function
do not establish that persistent-stream bound. This blocks production use of
the reserve-before-mutation algorithm until proved or replaced with a bounded,
resumable output design.

## Go comparison: where the target stands

| Surface | Current evidence | Decision |
| --- | --- | --- |
| Canonical Datastar framing | Roc fixtures are stricter than Go SDK v1.2.2 | Keep canonical client contract |
| HTTP negotiation and metadata | Existing platform policy handles q-values, wildcard, `Vary`, and `no-transform`; Go SDK does not | Preserve platform authority |
| Progressive Brotli | Rust and Go both expose flushed prefixes | Require real-browser generation gate |
| Normal Brotli close | Rust spike FINISHes; Go SDK API leaves stream unfinished | Keep stronger lifecycle |
| Brotli throughput | Selected Rust profiles beat matched Go by 1.22–1.47x | Focus next work on integration and bounds |
| Brotli retained state | q1 and q3 focused results meet/beat matched Go under stated accounting caveat | Use explicit profile capacity |
| Encoder allocations | q1 recycler and standard q3 reach zero steady system allocations | Integrate with owned-frame pooling |
| Roc state transition | Current speed build is 26.7 ns/event versus 1.27 ns/event unique Go at batch 1 | ABI/performance gate fails |
| Synthetic Roc allocation reuse | 16.7 ns/event at batch 1; beats Go only at batch 16 | Lower bound, not an implementation result |
| Lifecycle ownership | Explicit-state dev/speed tests balance cancellation, migration, concurrency, and nested resources | Keep topology, optimize representation |
| Boxed callable ownership | Generated dev/speed wrappers balance the full lifecycle on Roc main `1c1ceccf` | Correctness gate passes locally; retain cross-target gate |

Performance comparisons must retain equivalent flush, finish/abort,
backpressure, validation, and bounded-resource semantics. Batching is useful
for throughput but cannot be used to conceal the single-event latency gap.

## Dynamic-state ABI decision gate

The next compiler/glue spike should compare two supported end-state mechanisms:

1. Optimize the now-correct generated boxed-callable path so owned machine
   transitions do not require immutable continuation replacement on every
   step.
2. Generate a typed opaque state adapter exposing size/alignment, initialize,
   move/transfer, step, and drop wrappers without revealing layout to Rust.

Machine-code and compiler-pass tracing now explains both current allocations.
The callable callback allocates a fresh 40-byte erased continuation because
the reusable old allocation is held by the caller across an indirect call. The
representative explicit-state transition allocates a fresh 96-byte outer box
because the existing reuse recognizer does not cross its multi-branch union
match. Roc's same-procedure erased repack is also lost during ARC
materialization; a research-only ownership-complete repair passes all 201 LIR
tests but, as expected, does not affect the cross-call allocation. See the
[allocation provenance note](abi-spike/results/2026-08-01-allocation-provenance.md).

Either candidate must:

- work in development and speed builds on every supported target;
- use generated/supported ABI only, never a development runtime helper or
  hand-maintained closure layout;
- preserve nested captures and exact recursive ARC teardown;
- permit sequential thread migration and independent concurrency while
  rejecting same-stream overlap;
- release parked and in-flight-cancelled state exactly once;
- avoid an outer atomic retain/decref on owned transfer;
- reuse unique state storage or otherwise remove the per-step allocation;
- move unchanged nested ARC fields rather than retain/release them;
- meet or beat the unique Go single-event baseline within normal variance.

If neither mechanism passes, the experiment remains blocked. The fourth
`stream!` API may be retained for further research or an explicitly slower
prototype, but it is not the “absolute best” first-class design requested.

## Cross-track ownership agreement

One admitted step follows this order:

1. Reserve callback execution and the maximum uncompressed step budget.
2. Advance the owned Roc machine once.
3. Validate and frame a bounded event batch.
4. Before mutating a selected Brotli encoder, reserve the proven maximum encoded
   segment and an owned body frame; identity reserves its exact frame size.
5. PROCESS and FLUSH one logical item at a time, transferring each result into
   the bounded body queue.
6. Park the returned machine only after all step output is accepted into host
   ownership, or discard it on cancellation/failure.
7. Release callback capacity and schedule the declared wake condition.

This order prevents the host from advancing application state while a previous
step is backpressured, makes framed-but-unsent bytes host-owned, and keeps
compression CPU out of async transport workers. A prototype must determine
whether encoding shares the finite callback operation or uses a separately
bounded CPU executor without compromising ordering and cancellation.

## Next feasibility spikes

### A. Compiler/glue ownership and reuse

Implement both ABI candidates above, rerun the committed lifecycle fixture,
and compare batches 1, 4, and 16 against Go 1.26.5. Gate on the single-event
result, not the amortized batch-16 result.

### B. Production bounded body integration

Integrate the synthetic `ServerBody` semantics with the real listener,
response authority, request accounting, deadlines, graceful shutdown, and H2
flow control. Prove a fixed high-water mark for stopped readers and isolation
of an unrelated H2 stream.

### C. Persistent FLUSH bound and frame ownership

Prove the maximum encoded output of PROCESS+FLUSH for every admitted item size
and selected profile, or implement a resumable bounded encoder/body handshake.
Pool/reuse owned frames so the complete q1 and q3 paths, not just compressor
scratch, have measured steady-state allocation behavior.

### D. End-to-end scheduler and scale

Exercise idle, hot, timer-herd, slow-reader, disconnect, and shutdown workloads
with ordinary request load. Measure stream state, encoder state, task count,
queue high-water, wake latency, event latency, and ordinary p99. Run q1 scale,
q3 full-compression, and identity populations separately and mixed.

### E. API ergonomics and browser matrix

Build finite action, progressive operation, live SQLite view, durable replay,
and post-commit wake examples. Compare source complexity and error plumbing to
the official Go SDK. Run the generation-gated harness in Chromium and WebKit
and through the eventual production deployment topology.

### F. Cross-target lifecycle and decoding

Run state ownership/drop fixtures and independently decode completed and
cancelled streams for every supported target. A target-specific semantic skip
is not acceptable for release.

## Explicitly unresolved product choices

- Whether the final internal ABI is a repaired boxed callable or generated
  opaque state adapter.
- Whether the scale profile is selected by a server route table, a typed
  `Sse.Options` value, or a high-level constructor.
- Whether `Pulse` is valuable enough for the initial release; timer polling is
  sufficient to test the core stream runtime first.
- The exact callback scheduler topology and reservation split.
- The default maximum stream count and compressed-stream counts for each
  profile.
- The public maximum stream lifetime and reference reverse-proxy deployment.

These choices do not undermine the agreed architecture. Each has an objective
spike and can be decided without introducing a writer, async runtime, or
message bus.

## Evidence map

- Protocol and Go parity:
  [`research/datastar-parity/README.md`](../../research/datastar-parity/README.md)
- Initial transport:
  [`datastar-transport-findings.md`](datastar-transport-findings.md)
- Real browser/proxy:
  [`datastar-browser-transport-findings.md`](datastar-browser-transport-findings.md)
- Brotli Pareto frontier:
  [`datastar-brotli-footprint-findings.md`](datastar-brotli-footprint-findings.md)
- Callable and explicit-state ABI:
  [`roc-abi-lifecycle.md`](roc-abi-lifecycle.md) and
  [`explicit-state-spike/README.md`](explicit-state-spike/README.md)
- Research comparison rubric:
  [`datastar-research-program.md`](datastar-research-program.md)

The committed harnesses and raw observations remain the authority for exact
commands, environment, and measurement caveats. This synthesis owns the
cross-track decisions; individual reports own their evidence.
