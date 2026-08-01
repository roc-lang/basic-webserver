# Datastar research synthesis and spike contract

Status: production body transaction is the critical path; compiler feasibility passed locally

Date: 2026-08-02

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
not enough to accept the scope change in `design.md` or ship a public API.

The preferred boxed-callable ABI passes the complete local lifecycle through
generated provided wrappers. A follow-up compiler prototype on Roc main
`9b601b5dac` also passes ownership of the old callable through the erased
invocation and recursive constructor. Its unique compatible optimized path
requests no calls to the instrumented Roc allocator/deallocator and measures a
representative 1.46 ns median. It is faster than the closest functional Go
source-shape fixture in these runs, while an aggressive mutable-pointer Go
reference is slightly faster. This supports advancing the callable shape to
transport integration research, subject to controlled performance, upstream
compiler design, cross-target, and end-to-end gates. The allocating
explicit-state path remains only a lifecycle fallback.

The research is therefore refocused. Retained callable allocation is no longer
the leading feasibility question. The critical path is one production body
transaction which carries a bounded Roc item through validation, canonical SSE
framing, optional Brotli, an owned output frame, Hyper flow control, and
cancellation without unbounded buffering or steady-state allocation. Compiler
upstreaming remains a parallel release dependency, not the work which should
hold up transport integration research.

## Refocused objective hierarchy

The next work is ordered by the earliest uncertainty which could invalidate the
architecture:

1. **P0 — bounded production body transaction.** Prove in the real
   `ServerBody` path that encoder state advances only after one fixed output
   frame is reserved, that PROCESS and FLUSH can pause across frames, and that
   stopped readers bound retained bytes. Cancellation must release the pending
   framed item, encoder, frame reservation, and returned Roc machine through
   one idempotent close path.
2. **P0 — owned-frame steady state.** Replace per-frame allocation/copying with
   a fixed-capacity owned-frame pool or an equally bounded ownership transfer.
   Measure the complete identity, q1, and q3 paths after warmup. Zero encoder
   allocations alone does not close this objective.
3. **P1 — listener and scheduler isolation.** Carry the transaction through
   the response authority, request accounting, deadlines, graceful shutdown,
   HTTP/1.1, and HTTP/2. A stopped stream must not grow its queue or degrade an
   unrelated HTTP/2 stream or ordinary-request p99 beyond the comparison gate.
4. **P1 — compiler upstream and portability.** Complete review of the retained
   callable compiler change, controlled batch-1 timing, and supported-target
   lifecycle coverage in parallel with host work. Fall back to a generated
   typed opaque-state adapter only if compiler review invalidates the callable
   mechanism.
5. **P2 — application ergonomics and browser coverage.** Select the public API
   only after the body ownership model is real, then compare representative Roc
   applications with Go and finish the Chromium/WebKit/proxy matrix.

The P0 gate closes only with a real-body test which forces multiple output
frames, repeatedly reaches backpressure, proves incremental decode after
FLUSH, proves normal FINISH and cancellation-without-FINISH, and reports live
frame/byte/encoder/machine accounting returning to zero. A compressor-only
test or an observed maximum output size is insufficient.

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
2. Before every encoder call, reserve one fixed-capacity owned output frame.
3. Advance PROCESS or FLUSH only into that frame, commit any produced bytes,
   and pause when the next frame is backpressured.
4. FINISH through the same resumable frame handshake on normal EOF.
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
stream. Its measured encoder time is 1.22–1.25 times faster than matched Go,
but its encoded/identity ratio is 0.889 for the tiny official-fixture mix and
1.231 for heartbeat-only traffic. It is not a universal compression default.

Standard q3/LGWin12 needs no recycler. Its measured encoder time is 1.44–1.47
times faster than matched Go at the selected settings, while its wire output is
not identical to Go's. It retains 4.7% less mature todo state under the
documented non-identical accounting methods and saves roughly 90–92.6% on the
official and changing-content corpora, but only 23% on heartbeat-only traffic.
It retains much more state than q1, so it requires separate compressed-stream
admission and cannot be the profile for an unconstrained 10,000-stream promise.

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

The disposable transport spike now demonstrates the bounded, resumable option
with seven-byte body frames for both q1/LGWin11 and q3/LGWin12 over a 64 KiB
item. Every encoder call follows a successful one-frame reservation; PROCESS,
FLUSH, and FINISH span as many frames as required; every reservation is released
by body polling; and the flushed and finished streams independently decode to
the exact input. This removes the need to prove a whole-item repeated-FLUSH
maximum for correctness. It does **not** close production integration or the
allocation gate: the disposable queue still creates `Bytes` with a copy and is
not wired through the real listener/accounting/cancellation path.

## Go comparison: where the target stands

| Surface | Current evidence | Decision |
| --- | --- | --- |
| Canonical Datastar framing | Roc fixtures are stricter than Go SDK v1.2.2 | Keep canonical client contract |
| HTTP negotiation and metadata | Existing platform policy handles q-values, wildcard, `Vary`, and `no-transform`; Go SDK does not | Preserve platform authority |
| Progressive Brotli | Rust and Go both expose flushed prefixes | Require real-browser generation gate |
| Normal Brotli close | Rust spike FINISHes; Go SDK API leaves stream unfinished | Keep stronger lifecycle |
| Brotli encoder time | Selected Rust profiles beat matched Go by 1.22–1.47x at non-identical wire sizes | Focus next work on integration and bounds |
| Brotli retained state | q1 and q3 focused results meet/beat matched Go under stated accounting caveat | Use explicit profile capacity |
| Encoder allocations | q1 recycler and standard q3 reach zero steady system allocations | Integrate with owned-frame pooling |
| Roc retained-callable transition | Representative 1.46 ns/step; zero instrumented allocator/free calls on the unique compatible path | Allocation feasibility passes; controlled and end-to-end performance remain |
| Go references | Functional source-shape fixture allocates once; aggressive mutable-pointer fixture does not and is slightly faster | Neither fixture alone is the production acceptance contract |
| Roc explicit-state transition | Current representative speed build is 26.7 ns/event versus 1.27 ns/event unique Go at batch 1 | Keep only as lifecycle fallback |
| Synthetic Roc allocation reuse | 16.7 ns/event at batch 1; beats Go only at batch 16 | Lower bound, not an implementation result |
| Lifecycle ownership | Explicit-state dev/speed tests balance cancellation, migration, concurrency, and nested resources | Keep topology, optimize representation |
| Boxed callable ownership | Generated native dev/speed wrappers balance the full lifecycle | Correctness gate passes locally; retain cross-target gate |

Performance comparisons must retain equivalent flush, finish/abort,
backpressure, validation, and bounded-resource semantics. Batching is useful
for throughput but cannot be used to conceal the single-event latency gap.

## Dynamic-state ABI decision gate

The compiler/glue research evaluated two end-state mechanisms, but implemented
only the first:

1. The generated boxed-callable path now reuses owned machine storage across
   the erased call and recursive return in the research compiler.
2. A typed opaque state adapter exposing size/alignment, initialize,
   move/transfer, step, and drop wrappers without revealing layout to Rust
   remains an unimplemented alternative.

Machine-code and compiler-pass tracing explains both original allocations. The
callable case is now eliminated by preserving ARC reuse, passing an owned
destination through the erased ABI, specializing finite return-position calls,
and inlining LLVM's runtime-unique fast path. The representative explicit-state
transition still allocates a fresh 96-byte outer box because the existing reuse
recognizer does not cross its multi-branch union match. See the
[allocation provenance note](abi-spike/results/2026-08-01-allocation-provenance.md)
and [zero-allocation result](abi-spike/results/2026-08-01-zero-allocation-reuse.md).

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
- make no steady allocator/deallocator calls on the unique compatible path and
  stay in the same cost class as the aggressive mutable Go reference; and
- meet the end-to-end Go Datastar latency/throughput target under equivalent
  framing, compression, backpressure, cancellation, and resource bounds.

If neither mechanism passes, the experiment remains blocked. The fourth
`stream!` API may be retained for further research or an explicitly slower
prototype, but it is not the “absolute best” first-class design requested.

## Cross-track ownership agreement

One admitted step follows this order:

1. Reserve callback execution and the maximum uncompressed step budget.
2. Advance the owned Roc machine once.
3. Validate and frame a bounded event batch.
4. Hold the returned machine and framed item in a host-owned draining-step
   record; do not invoke the machine again.
5. Reserve one fixed output frame before each encoder call. Advance PROCESS and
   FLUSH resumably, committing each frame before waiting for more capacity.
   Identity chunks through the same body reservation boundary.
6. Park the returned machine only after the whole logical item is flushed into
   host ownership, or discard it with the pending item on cancellation/failure.
7. Release callback capacity at the defined CPU boundary and schedule the
   declared wake condition only after draining completes.

This order prevents the host from advancing application state while a previous
step is backpressured, makes framed-but-unsent bytes host-owned, and keeps
compression CPU out of async transport workers. A prototype must determine
whether encoding shares the finite callback operation or uses a separately
bounded CPU executor without compromising ordering and cancellation.

## Remaining feasibility spikes

### A. Production body transaction and owned frames

Move the resumable one-frame handshake into a disposable adapter around the
real `ServerBody` type. Add reusable owned frames and explicit live accounting
for framed input, queued output, encoder state, and the returned Roc machine.
Force PROCESS, FLUSH, and FINISH across multiple frames; cancel in each phase;
measure steady-state allocations for identity, q1, and q3. This is the current
highest-value spike.

### B. Real listener and H2 isolation

Integrate that adapter with the response authority, request accounting,
deadlines, graceful shutdown, and HTTP/1.1 and HTTP/2 flow control. Prove a
fixed high-water mark for stopped readers and isolation of an unrelated H2
stream and ordinary requests.

### C. End-to-end scheduler and scale

Exercise idle, hot, timer-herd, slow-reader, disconnect, and shutdown workloads
with ordinary request load. Measure stream state, encoder state, task count,
queue high-water, wake latency, event latency, and ordinary p99. Run q1 scale,
q3 full-compression, and identity populations separately and mixed.

### D. Compiler/glue upstream and cross-target ownership

Resolve review of the callable candidate or replace its host-visible fifth
argument with a generated adapter. Rerun the lifecycle fixture on supported
targets and compare batches 1, 4, and 16 against Go 1.26.5 under controlled
repeated-process timing. Gate on batch 1 and end-to-end results, not amortized
batch 16 alone.

### E. API ergonomics and browser matrix

Build finite action, progressive operation, live SQLite view, durable replay,
and post-commit wake examples. Compare source complexity and error plumbing to
the official Go SDK. Run the generation-gated harness in Chromium and WebKit
and through the eventual production deployment topology.

### F. Cross-target transport and decoding

Run state ownership/drop fixtures and independently decode completed and
cancelled streams for every supported target. A target-specific semantic skip
is not acceptable for release.

## Explicitly unresolved product choices

- Whether the final internal ABI is a repaired boxed callable or generated
  opaque state adapter.
- Whether encoding retains the Roc execution permit while a step drains or
  moves to a separately bounded CPU admission unit.
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
