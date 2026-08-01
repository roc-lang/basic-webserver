# Datastar experiment research program

Status: initial research convergence complete; follow-up feasibility spikes are
tracked in `datastar-research-synthesis.md`

Branch: `datastar-experiment`

Started: 2026-08-01

## Purpose

This document coordinates the independent feasibility work behind
[`docs/datastar-experiment.md`](../datastar-experiment.md). It records how
evidence will be compared and integrated; it is not an accepted platform
contract and does not replace [`design.md`](../../design.md).

The research target is a Roc application experience and host implementation
that meet or exceed the official Go Datastar stack on representative supported
workloads wherever the protocols and safety guarantees are equivalent. A
result that is merely functional is not enough. A faster result obtained by
dropping backpressure, cancellation, flush, validation, or bounded-resource
semantics is not equivalent.

## Independent tracks

| Track | Research branch | Primary questions | Required evidence |
| --- | --- | --- | --- |
| Roc ABI and lifecycle | `research/datastar-abi` | Can retained stream machines cross the Roc/host ABI safely and cheaply? What fallback preserves ownership and performance? | Compiler/glue inspection, ownership experiments, failure cases, ABI cost model, benchmark plan |
| Hyper and Brotli transport | `research/datastar-transport` | Can the host progressively deliver bounded Brotli SSE over HTTP/1.1 and HTTP/2 without blocking transport workers? | Rust-only prototype, flush/decode proof, memory bounds, cancellation tests, Go comparison where available |
| Datastar and Go parity | `research/datastar-parity` | What exact client and official Go SDK contract are we targeting, and what is the reference ergonomic/performance envelope? | Pinned sources, fixtures, browser/HTTP behavior matrix, reproducible Go reference benchmarks |

Each track works in its own Git worktree and commits focused artifacts to its
own branch. Research branches are not merged wholesale. Findings are reviewed
for contradictory assumptions, then the smallest coherent commits or rewritten
conclusions are integrated into `datastar-experiment`.

## Evidence classes

Every conclusion should be labeled as one of:

- **Measured**: produced by a committed reproducible command with raw results,
  tool versions, machine information, and enough samples to expose variance.
- **Observed**: demonstrated by a focused test, source inspection, wire capture,
  or compiler artifact, but not a performance measurement.
- **Specified**: required by a pinned primary protocol or implementation source.
- **Inferred**: follows from measured, observed, or specified facts but has not
  itself been tested.
- **Hypothesis**: plausible and worth testing, with no adequate evidence yet.

Search snippets, documentation prose without a pinned version, and a single
happy-path demo can identify questions but do not close a gate.

## Go comparison contract

### Two baselines

Research must report both when practical:

1. **Semantic-equivalence baseline**: Roc/Rust and Go emit the same logical
   events with the same flush points, HTTP version, connection reuse, Brotli
   quality/window, heartbeat policy, and slow-reader behavior.
2. **Idiomatic-default baseline**: the proposed zero-configuration
   `basic-webserver` path is compared with the official Go SDK's normal
   documented setup, including its default compression configuration.

The first isolates implementation performance. The second tests the actual
developer experience. Neither may silently substitute a raw socket loop for
the official Go stack or remove behavior required on the Roc side.

### Environment controls

Every performance result records:

- repository commit, Datastar client/SDK commit or tag, Roc compiler commit,
  Rust toolchain, Go toolchain, and build mode;
- operating system, architecture, CPU model/count, available RAM, and relevant
  file-descriptor limits;
- benchmark command, warmup, duration or iteration count, concurrency, event
  distribution, payload corpus, and number of repetitions;
- HTTP/1.1 or HTTP/2, identity or Brotli, direct or reference-proxy path, and
  whether TLS is deliberately excluded;
- whether connections are new, kept alive, mostly idle, backpressured, or
  reconnecting;
- median and dispersion, not only the best run.

Roc/Rust and Go runs use the same host, client, payload fixtures, concurrency,
and measurement process. They run separately rather than competing for the
same CPU. CPU frequency scaling, debug builds, logging, and telemetry exporters
must not differ unnoticed.

### Workload matrix

The minimum comparable matrix is:

| Workload | Variants | Primary measurements |
| --- | --- | --- |
| Finite Datastar action | 1 event at 256 B, 4 KiB, and 64 KiB | Requests/s, p50/p95/p99 latency, CPU/request, allocations, wire bytes |
| Progressive response | 3 events separated by fixed host timers | Time to headers and each event, flush correctness, wire bytes |
| Hot persistent stream | 1, 10, 100, and 1,000 events/s with small and HTML-patch payloads | Event throughput, p50/p95/p99 delivery latency, CPU/event, allocations, compression ratio |
| Mostly idle streams | 100, 1,000, and reference-host 10,000 connections/streams | Fixed and per-stream RSS, tasks/threads, file descriptors, heartbeat CPU/bytes |
| Slow readers | Fixed fraction of clients that stop or rate-limit reads | Buffered high-water bytes, unaffected-client latency, closure time, released accounting |
| Wake herd | Many timers or notifications becoming ready together | Scheduler delay distribution, ordinary-request p99, queue high-water, fairness |
| Disconnect and reconnect | Before commit, during callback, while parked, and while backpressured | Cleanup latency, leaked resources, replay behavior, wasted work |
| Graceful shutdown | Idle, active, and backpressured populations | Drain time, forced closures, final resource accounting |

HTTP/1.1 and HTTP/2, identity and Brotli, and direct and reference-proxy paths
are exercised wherever the combination is meaningful. A browser integration
test proves that compressed event one is processed before event two exists;
command-line decompression alone does not prove the browser experience.

### Performance decision rule

The target is for `basic-webserver` to equal or beat Go in throughput, event
latency, and retained memory on the semantic-equivalence workloads while
preserving the stronger platform bounds. Results must report all three axes;
winning one does not hide a regression in another.

If a result is slower than Go outside normal run variance:

1. profile before changing the API or architecture;
2. attribute the gap to Roc computation, ABI crossings, allocation/copying,
   scheduling, HTTP transport, compression, or added safety semantics;
3. test the smallest optimization that could remove the gap;
4. repeat the controlled comparison; and
5. leave the gate open if the gap remains unexplained.

An intentional performance tradeoff is accepted only when it enforces a named
platform invariant that the Go baseline lacks, the cost is measured, and no
lower-cost design satisfies the invariant. “Fast enough” is not evidence that
the meet-or-exceed target was reached.

## Cross-track questions to reconcile

The coordinator must not accept a track conclusion until these interfaces
agree:

1. Does the ABI emit one event or a bounded batch per Roc invocation, and how
   does that choice affect latency, crossing cost, and backpressure?
2. Who owns framed but not yet Brotli-encoded bytes while transport capacity is
   unavailable?
3. Can encoding occur in the admitted stream-production operation without
   unfairly extending a Roc execution permit?
4. What exact flush operation makes one persistent Brotli stream incrementally
   decodable, and what is its worst-case event output bound?
5. Which Datastar actions are genuinely persistent versus finite SSE responses,
   and should both use the same outcome kind?
6. Does browser cancellation map promptly enough to body drop to release the
   retained Roc machine and encoder?
7. Which Go measurements reflect SDK/runtime advantages that Roc should match,
   and which reflect unbounded behavior that the platform deliberately rejects?
8. Are automatic Brotli and its `no-transform` escape hatch compatible with
   the pinned client, caches, reverse proxy, and compression-oracle guidance?

Contradictory findings are recorded explicitly and resolved with a focused
experiment. They are not averaged into vague prose.

## Integration checklist

Before research changes are pushed to the draft PR:

- [x] The research branch has coherent commits and a clean worktree.
- [x] Commands and raw observations are reproducible from committed files.
- [x] Primary sources are pinned to versions or commits.
- [x] Measurements satisfy the comparison contract or clearly state why they
      are preliminary.
- [x] Findings distinguish hard evidence from inference and hypothesis.
- [x] Negative results and failed preferred designs are preserved.
- [x] Recommended changes identify exact experiment sections and gate wording.
- [x] No research result silently changes `design.md` or expands the accepted
      platform contract.
- [x] Integrated prose has one owner and no conflicting duplicate source of
      truth.
- [x] The draft PR status and unresolved gates are updated after each milestone.

## Completion condition

This research phase is complete only when the three tracks have returned
reviewable evidence, cross-track contradictions have been resolved or captured
as explicit blocking spikes, the experiment document reflects the findings,
and the next feasibility spikes have reproducible commands and objective
performance/correctness gates.

It does not mean first-class SSE is implemented or that `design.md` should yet
accept the scope change.

This condition was met on 2026-08-01. The cross-track owner is
[`datastar-research-synthesis.md`](datastar-research-synthesis.md); its open
spikes remain release gates rather than unfinished coordination work.
