# Datastar research synthesis and spike contract

Status: production body, composite-callable reuse, Rust consuming projection,
outcome transfer, and a bounded host stream heap passed; retained typed sources
are the preferred scheduler hypothesis for the next product slice

Date: 2026-08-03

Branch: `datastar-experiment`

This document reconciles the independent Datastar protocol, Roc ABI,
transport/browser, and Brotli-footprint tracks. It records the agreed direction
for the next feasibility spikes. It is not an accepted platform contract and
does not change [`design.md`](../../design.md).

## Bottom line

The research supports a coherent first-class SSE and Datastar design for
`basic-webserver`:

- Roc constructs typed events and a typed retained `Sse.unfold!` source, whose
  sole owner is consumed into a fixed-capacity host stream heap.
- The Rust host owns scheduling, timers, admission, backpressure, heartbeat,
  cancellation, HTTP framing, compression, and shutdown.
- A parked stream retains one owned Roc source but no Roc stack, worker, native
  thread, response writer, or application scheduler. Arbitrary captured Roc
  heap remains trusted application memory rather than a per-stream byte quota.
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
Finite, precomputed SSE already fits the ordinary bounded response model.
Dynamic source stepping does not: even with a private typed source, it is a
deliberately constrained application callback runtime and therefore conflicts
with the current explicit exclusion of Roc-produced incremental responses. The
experiment can
justify that scope change only by proving a narrow exception: a closed native
response plan whose finite Roc transitions remain request-local while the host
owns and bounds every long-lived transport, scheduling, timer, compression,
and shutdown resource. A generic writer, callback registry, detached task, or
application scheduler fails the product-scope gate even if it benchmarks well.

The boxed-callable ABI candidate passes the complete local lifecycle through
generated provided wrappers. A follow-up compiler prototype on Roc main
`9b601b5dac` passes ownership of the old callable through the erased invocation
and a direct recursive callable result. That narrower optimized path requests
no calls to the instrumented Roc allocator/deallocator and measures a
representative 1.46 ns median. It is faster than the closest functional Go
source-shape fixture in these runs, while an aggressive mutable-pointer Go
reference is slightly faster.

The production-shaped result is a materially different compiler boundary. A
step returns framed bytes, its next callable, and its next wake inside a tagged
record. On compiler `debug-e1d283cb`, that composite transition allocated and
freed one 80-byte continuation envelope per emitted item even though the item
was shared static storage. The first attempted fixes exposed sibling-read and
capture-lifetime hazards rather than closing the gate.

Roc candidate `d4921d8658` now closes that compiler feasibility question. It
threads one selected aggregate callable destination through lowering with
explicit ownership provenance and snapshots every old-capture dependency
before reuse. Seven 100,000-step samples report zero allocator calls, frees,
or requested bytes per transition at 61.45--61.58 ns/step. The lifecycle run
ends with 174 allocations, 174 deallocations, and zero live allocations, and
the compiler's interpreter, development, Wasm, LLVM, eval, and build-ci suites
pass. The candidate is under review in
[`roc-lang/roc#10530`](https://github.com/roc-lang/roc/pull/10530).

Roc candidate `be78e95c42` and the matched Rust fixture now close the consuming
projection feasibility gate. Generated Rust exposes unsafe borrowed-reference
and consuming-move primitives; non-`Copy` framework owners validate the tag,
invalidate the shell after extraction, and whole-drop unextracted results.
Dynamic aliased and unique list items balance under both destruction orders,
and projection preserves pointer/refcount identity with no allocator activity.
The full 48-case native/Wasm glue suite passes. See the
[consuming projection result](abi-spike/results/2026-08-02-consuming-rust-projection.md).

Adversarial resource review then established an important limit: arbitrary
captured Roc state cannot be truthfully byte-admitted with the current ABI.
Allocator metadata has no stream ownership domain, and an erased callable has
no alias-aware graph visitor. Stream count, outer callable size, allocation
deltas, and application estimates do not bound its transitive graph.

That limit was initially treated as requiring a bounded byte cursor. Rechecking
the platform trust boundary showed that this was stronger than `design.md`:
the platform bounds hostile input, execution concurrency, and resources it
introduces, but does not contain arbitrary allocation by trusted application
code. The preferred hypothesis is therefore a typed retained `Sse.unfold!`
source consumed from `Server.Outcome` into a fixed-capacity, generation-checked
host stream heap. A bounded cursor remains an opt-in stricter model. See the
[next-slice contract](datastar-next-slice.md) and
[retained-source contract](datastar-retained-source-contract.md).

## Refocused objective hierarchy

The next work is ordered by the earliest uncertainty which could invalidate the
architecture:

1. **P0 — retained-source stream heap.** Consume one outcome-owned source into
   a fixed-capacity, generation-checked host heap. Prove saturation, stale
   generations, cancellation while advancing, and exactly one drain
   acknowledgement before the next wake is armed. The disposable two-slot
   Rust fixture now passes this sub-gate.
2. **P0 — real identity listener slice.** Carry that retained source through
   `respond!`, generated consuming Step ownership, `SseBody`, the response
   authority, and an actually bound HTTP/1.1 listener. Do not expose the public
   API yet.
3. **P1 — listener and scheduler isolation.** Carry the transaction through
   the response authority, request accounting, deadlines, graceful shutdown,
   HTTP/1.1, and HTTP/2. A stopped stream must not grow its queue or degrade an
   unrelated HTTP/2 stream or ordinary-request p99 beyond the comparison gate.
   Brotli PROCESS/FLUSH/FINISH currently execute synchronously inside
   `SseBody::poll_frame`; the spike must place meaningful compression CPU in an
   explicitly bounded execution domain.
4. **P1 — compiler portability and complete path.** Complete controlled
   batch-one timing, supported-target lifecycle coverage, and full
   Hyper/socket allocation attribution. A direct callable-only result is not
   sufficient evidence for this gate.
5. **P2 — application ergonomics and browser coverage.** Select the public API
   only after the body ownership model is real, then compare representative Roc
   applications with Go and finish the Chromium/WebKit/proxy matrix.

The host-only parts of these P0 gates now pass: the real body forces multiple
output frames, repeatedly reaches backpressure, incrementally decodes after
FLUSH, normally FINISHes, cancels without FINISH, and returns frame/item/encoder
accounting to zero. The body now acknowledges `item_drained` only after the
final identity frame is committed or Brotli FLUSH completes. The remaining P0
proof needs the retained Roc source, bounded host slot, generated consuming
Step projection, admission, request tracking, and shutdown accounting. The
source poll vocabulary must distinguish a parked timer from an in-flight
advance so the body retains its pre-reserved frame only for the latter.

## Gate status ledger

| Gate | Current evidence | Status | Next falsifying test |
| --- | --- | --- | --- |
| Product scope | Finite precomputed SSE fits the ordinary response path; dynamic retained-source stepping is a real, deliberate exception to the accepted design | Open | Prove the exception stays one private typed source and a closed native plan with no writer, callback registry, detached work, or application scheduler |
| Composite Roc transition | Candidate `d4921d8658` is allocation-free and lifecycle-balanced in the production-shaped fixture | Passed for feasibility; upstream review open | Cross-target generated-wrapper lifecycle and controlled batch-one comparison |
| Consuming result ownership | RustGlue candidate `be78e95c42` plus affine wrappers pass move, whole-drop, wrong-tag, dynamic alias/unique, both drop-order, no-allocation, native, and Wasm checks | Passed for Rust-host feasibility; upstream/C/Zig completeness open | Add exact Wait/Error terminal paths to the retained source result |
| Body/frame ownership | One-slot identity and Brotli body reaches zero steady allocations and balanced cancellation | Passed for host-only fixture | Compose one retained Roc transition across repeated body `Pending` states |
| Admission and scheduler | A two-slot host heap proves saturation, slot/wake generations, overlap rejection, drain acknowledgement, normal end, and parked/draining/in-flight cancellation | Partial | Real timer/immediate scheduler through the listener with stale-wake, cancellation, and herd tests |
| Dynamic state contract | Stream count and host resources are bounded; arbitrary captured Roc heap is explicitly trusted application memory, matching the existing design boundary | Retained-source hypothesis selected | Verify host-originated input bounds survive retention and expose allocation/high-water observability |
| Listener/shutdown isolation | H1/H2 body paths and stalled-reader deadline pass without retained Roc state | Partial | Mixed ordinary/SSE load, global accounting, graceful drain, and unrelated-H2 isolation |
| Brotli value and CPU isolation | Progressive Firefox/proxy delivery and q1/q3 footprint evidence exist; encoder work currently runs in Hyper body polling | Partial | Compose scheduler, move meaningful encoder CPU behind explicit admission, then test cross-target decode, browsers, and scale |
| Public API and scope change | Candidate Roc API is documented only | Deferred | Realistic applications and Go comparison after the ownership/runtime gates pass |

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
- a typed `Sse.unfold!` helper that retains application state behind one private
  source owner for dynamic streams;
- typed element and signal patch constructors;
- typed event ID, retry, wait, close, and application-error outcomes;
- no compressor or response writer in application code.

The preferred program remains `{ init!, respond!, shutdown! }`. Initial
`respond!` authorizes a stream and returns a typed retained source plus options.
The host consumes its sole owner into a bounded stream slot. Route packages can
define typed state and transitions without a root source-ID dispatcher or
cursor codec. Realistic examples must establish whether this is sufficiently
ergonomic compared with Go before names or exact shape become contract.

Do not add a dynamic state bag, general callback registry, arbitrary byte
writer, application pub/sub bus, or one-thread-per-stream API to hide an ABI
limitation.

### Host runtime topology

Use one host-owned record per admitted stream. It contains one owned Roc source
or one in-flight completion, wake description and generation, cancellation
state, body reservation, optional Brotli encoder, accounting, and lifecycle
metadata.

Only one advance for a stream may run at a time. A finite step returns a
bounded event batch, a wait/continue decision, a normal end, or an error. The
host does not advance again until output reservation and backpressure permit
it. Independent streams may advance concurrently within an explicit fair
admission unit reserved separately from ordinary request work.

Run the first step before committing headers unless an API explicitly requests
immediate commitment. This preserves ordinary pre-commit errors and prevents
admitting a stream that fails before producing a valid plan.

On cancellation while parked, drop the source and encoder without invoking Roc. On
cancellation during an advance, allow the finite call to return, then release
the returned source and output rather than parking or publishing it. Body drop,
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
maximum for correctness.

The owned-frame follow-up isolates and removes the remaining allocation in the
disposable path. The former `ServerBody::Data = Bytes` could preserve the frame
drop callback only through `Bytes::from_owner`, whose pinned implementation
allocates a 56-byte owner box per output frame. A candidate internal
`ServerData::{Bytes, Pooled}` sum type implements `Buf` directly. After 2,048
warmup events, 10,000 identity, recycled-q1, and standard-q3 events through the
bounded queue and resumable body made zero global allocator/deallocator calls;
every run ended at one free slot, zero in use. The `Bytes` compatibility runs
made exactly one allocation/free per output frame. Cancellation tests release
abandoned, queued, and transport-owned frames and wake a blocked producer.

The internal sum type is now used by the real listener, tracked body, native
file body, telemetry, and manual H2 sender. A 4,096-byte pooled frame passes a
seven-byte H2 flow-control window and returns its sole pool slot; all 172 host
tests and all 52 live runtime specification cases pass. This closes the
body-data compatibility seam. The live-body follow-up below then joins
resumable encoding, pool accounting, and response deadlines; retained Roc
state and global request/shutdown accounting remain outside that fixture. See
[`datastar-frame-ownership-findings.md`](datastar-frame-ownership-findings.md).

The production-body follow-up connects that seam to a pull source and the
resumable encoder. With one seven-byte slot, normal q3 responses pass the real
H1 path and the manual H2 path under a seven-byte flow-control window. A stalled
H2 reader hits the response deadline, cancels the source exactly once, aborts
Brotli without FINISH, and returns pending item, encoder, reserved-frame, and
transport-owned-frame accounting to zero.

After 2,048 warmup events, a 10,000-event counted window through the production
body makes zero allocation/deallocation calls for identity, recycled
q1/LGWin11, and standard q3/LGWin12. The controlled standard-q1 comparison
makes 40,000 allocations requesting 140,960,000 bytes; the production 256 KiB
fixed-slot scratch recycler removes them without changing frame or wire counts.
See
[`datastar-production-body-findings.md`](datastar-production-body-findings.md).

## Go comparison: where the target stands

| Surface | Current evidence | Decision |
| --- | --- | --- |
| Canonical Datastar framing | Roc fixtures are stricter than Go SDK v1.2.2 | Keep canonical client contract |
| HTTP negotiation and metadata | Existing platform policy handles q-values, wildcard, `Vary`, and `no-transform`; Go SDK does not | Preserve platform authority |
| Progressive Brotli | Rust and Go both expose flushed prefixes | Require real-browser generation gate |
| Normal Brotli close | Rust spike FINISHes; Go SDK API leaves stream unfinished | Keep stronger lifecycle |
| Brotli encoder time | Selected Rust profiles beat matched Go by 1.22–1.47x at non-identical wire sizes | Focus next work on integration and bounds |
| Brotli retained state | q1 and q3 focused results meet/beat matched Go under stated accounting caveat | Use explicit profile capacity |
| Production SSE body | Identity, recycled q1, and standard q3 reach zero measured steady allocations; normal H1/H2 and stalled-H2 cancellation pass with one slot | Connect the retained Roc source heap and global admission/shutdown accounting; then count the complete Hyper/socket path |
| Direct Roc retained-callable transition | Representative 1.46 ns/step; zero instrumented allocator/free calls on the unique compatible path | Useful lower bound, not the production result shape |
| Composite Roc source transition | Candidate `d4921d8658` reports zero steady allocations at 61.45--61.58 ns/step and balances the complete lifecycle | Selected state transition for the retained-source hypothesis |
| Outcome-to-stream-heap transfer | Candidate Rust glue moves one outcome-owned source into a capacity-two host heap without allocator activity; saturation, stale tokens, acknowledgement, normal end, and cancellation balance | Passed as a disposable ownership proof; compose with `SseBody` and the real listener |
| Go references | Functional source-shape fixture allocates once; aggressive mutable-pointer fixture does not and is slightly faster | Neither fixture alone is the production acceptance contract |
| Roc explicit-state transition | Current representative speed build is 26.7 ns/event versus 1.27 ns/event unique Go at batch 1 | Keep only as lifecycle fallback |
| Synthetic Roc allocation reuse | 16.7 ns/event at batch 1; beats Go only at batch 16 | Lower bound, not an implementation result |
| Lifecycle ownership | Explicit-state dev/speed tests balance cancellation, migration, concurrency, and nested resources | Keep topology, optimize representation |
| Boxed callable ownership | Generated native dev/speed wrappers balance the full lifecycle | Correctness gate passes locally; retain cross-target gate |

Performance comparisons must retain equivalent flush, finish/abort,
backpressure, validation, and bounded-resource semantics. Batching is useful
for throughput but cannot be used to conceal the single-event latency gap.

## Retained-state ABI research result

The compiler/glue research evaluated two mechanisms before the resource-model
review:

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

The callable candidate had to:

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

The composite boxed-callable candidate passes the local unique-allocation and
lifecycle portion of this gate. Its generated Rust consuming projection also
passes local native and Wasm glue coverage. The reduced outcome/stream-heap
fixture now additionally proves that the source owner can cross the
`respond!`-shaped boundary into finite host capacity without copying or adding
a fixed application entrypoint.

This does not create a transitive heap quota. The selected contract instead
matches `design.md`: host-introduced stream, callback, buffer, timer,
compression, and opaque-resource capacity is admitted and bounded; arbitrary
Roc allocation by trusted application code is not isolated. Allocation domains
and graph visitation remain prerequisites only if a future product requirement
adds hard per-stream application-heap containment. Upstream callable review and
cross-target coverage remain required compiler work.

## Cross-track ownership agreement

One admitted step follows this order:

1. Reserve callback execution and the maximum uncompressed step budget.
2. Move the owned source out of its host slot into one finite Roc call once.
3. Validate and frame a bounded event batch.
4. Hold the returned source and framed item in a host-owned draining-step
   record; do not invoke the source again.
5. Reserve one fixed output frame before each encoder call. Advance PROCESS and
   FLUSH resumably, committing each frame before waiting for more capacity.
   Identity chunks through the same body reservation boundary.
6. Park the returned source only after the whole logical item is flushed into
   host ownership, or discard it with the pending item on cancellation/failure.
7. Release callback capacity at the defined CPU boundary and schedule the
   declared wake condition only after draining completes.

This order prevents the host from advancing application state while a previous
step is backpressured, makes framed-but-unsent bytes host-owned, and keeps
compression CPU out of async transport workers. A prototype must determine
whether encoding shares the finite callback operation or uses a separately
bounded CPU executor without compromising ordering and cancellation.

## Remaining feasibility spikes

### A. Consuming generated step ABI and compiler upstreaming

The Rust host feasibility portion passes at `be78e95c42`: generated unsafe
borrow/take primitives sit behind non-`Copy` owners and pass whole-step,
wrong-tag, item-first/machine-first, aliased, unique, zero-allocation, native,
and Wasm tests. Add exact `Wait` and `Error` shapes while integrating the real
adapter. Keep both compiler candidates and the fifth erased-call ownership
argument under upstream review; no platform code may depend on a development
helper or hand-maintained callable layout. Equivalent C and Zig move APIs are
upstream glue completeness work rather than blockers for this Rust host spike.

### B. Retained-source Roc transaction

Implement the production scheduler adapter around the outcome-owned source and
fixed-capacity host stream heap. Preserve the body's
reservation-before-poll invariant and prove that parked, in-flight, and
returned source owners, framed items, callback capacity, byte-budget tokens,
and transient Roc resources are released exactly once on body error, deadline,
disconnect, and shutdown. Do not arm the next wake until `item_drained`
acknowledges the final identity frame or Brotli FLUSH. Start timer-only: `Pulse`
adds no information needed to validate the ownership transaction and would
enlarge the wake-state surface prematurely. The first falsifying test is an
identity-only retained source through the actually bound HTTP/1.1 listener; see
[`datastar-next-slice.md`](datastar-next-slice.md).

### C. Real listener and H2 isolation

Admit that body and its encoder through finite host resources before response
commitment. Integrate request accounting, declarative wakes, heartbeat, and
graceful shutdown. Prove a fixed high-water mark for stopped readers and
isolation of an unrelated H2 stream and ordinary requests. The current body
calls Brotli directly from `poll_frame`; retain its resumable frame handshake
while moving meaningful encoder work to a fixed set of compression threads,
preallocated per-stream lanes, and a bounded queue of lane IDs. Per-frame
`spawn_blocking` is only a comparison because it allocates task state and
competes with Roc handler admission.

### D. End-to-end scheduler and scale

Exercise idle, hot, timer-herd, slow-reader, disconnect, and shutdown workloads
with ordinary request load. Measure stream state, encoder state, task count,
queue high-water, wake latency, event latency, and ordinary p99. Run q1 scale,
q3 full-compression, and identity populations separately and mixed.

### E. Compiler portability and cross-target ownership

Resolve review of the callable candidate and its host-visible fifth argument.
Rerun the lifecycle fixture on supported targets and compare batches 1, 4, and
16 against Go 1.26.5 under controlled repeated-process timing. Gate on batch 1
and end-to-end results, not amortized batch 16 alone.

### F. API ergonomics and browser matrix

Build finite action, progressive operation, live SQLite view, durable replay,
and post-commit wake examples. Compare source complexity and error plumbing to
the official Go SDK. Run the generation-gated harness in Chromium and WebKit
and through the eventual production deployment topology.

### G. Cross-target transport and decoding

Run state ownership/drop fixtures and independently decode completed and
cancelled streams for every supported target. A target-specific semantic skip
is not acceptable for release.

## Explicitly unresolved product choices

- Whether `Context` can be supplied to a retained typed transition without
  making `Server.Outcome` awkwardly generic or retaining an unnecessary copy
  of the application root.
- Whether realistic progressive, live-query, and replay examples match or
  improve on Go source complexity while keeping the source private and typed.
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

Each choice has an objective spike and can be decided without introducing a
writer, async runtime, arbitrary retained graph, or message bus.

## Evidence map

- Protocol and Go parity:
  [`research/datastar-parity/README.md`](../../research/datastar-parity/README.md)
- Initial transport:
  [`datastar-transport-findings.md`](datastar-transport-findings.md)
- Real browser/proxy:
  [`datastar-browser-transport-findings.md`](datastar-browser-transport-findings.md)
- Brotli Pareto frontier:
  [`datastar-brotli-footprint-findings.md`](datastar-brotli-footprint-findings.md)
- Owned frame allocation and `ServerData` decision:
  [`datastar-frame-ownership-findings.md`](datastar-frame-ownership-findings.md)
- Callable and explicit-state ABI:
  [`roc-abi-lifecycle.md`](roc-abi-lifecycle.md) and
  [`explicit-state-spike/README.md`](explicit-state-spike/README.md)
- Production-shaped source ownership and acknowledgement:
  [`datastar-retained-source-contract.md`](datastar-retained-source-contract.md)
- Preferred retained-source stream heap, first listener slice, and compression
  executor hypothesis:
  [`datastar-next-slice.md`](datastar-next-slice.md)
- Research comparison rubric:
  [`datastar-research-program.md`](datastar-research-program.md)

The committed harnesses and raw observations remain the authority for exact
commands, environment, and measurement caveats. This synthesis owns the
cross-track decisions; individual reports own their evidence.
