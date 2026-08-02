# Composite retained-source result

Date: 2026-08-02

Status: composite lifecycle passes; Roc compiler candidate `d4921d8658`
eliminates the optimized continuation allocation; production adapter research
remains paused and the private one-shot alternative is not selected.

## Question

The previous fixture returned only the next retained callable. A production SSE
advance instead needs a closed result containing an owned framed item, the next
callable, and a next-wake decision, or a terminal outcome. This follow-up asks
whether that nested callable retains the direct result's zero-allocation reuse
and whether a private one-shot result cell is a viable internal alternative.

## Reproduction

The allocation baseline used clean Roc branch `datastar-erased-repack-arc` at
`e1d283cbff4230e8354f72959a0367a8200771ad`. The successful compiler candidate
is the same branch at `d4921d86584bb2b7b4e1b62d9dfc0e9bf6d43abc`:

```sh
cd /path/to/roc
zig build roc

cd /path/to/basic-webserver
ROC=/path/to/roc/zig-out/bin/roc \
ROC_SRC=/path/to/roc \
python3 scripts/spike_retained_callable.py \
  --opt all --iterations 100000 --mode wrapper
```

The compiler version string remains `debug-e1d283cb` because it describes the
last commit in the build metadata, so the source commit above is authoritative.
The run was not CPU-pinned, so timing is diagnostic; allocation counts and
lifecycle assertions are the strong evidence.

## Fixture shapes

The composite reference is conceptually:

```text
advance(owned SourceMachine, wake) ->
    Emit { item: List(U8), machine: SourceMachine, wait_millis: U64 }
  | End
```

It captures a static canonical Datastar-shaped item, an opaque host resource,
sequence, and remaining count. Tests cover parked drop, whole returned-result
drop, normal end, and cancellation while the callback is blocked in a hosted
effect.

The alternative returns its next callable directly and deposits one Emit or
End result into a preallocated host cell through one hosted call. The fixture
models the low-level platform wrapper; a public application API must not expose
the cell token or turn it into a repeatable writer.

The fixture's `Abi.SinkMachine` does expose that `U64` token to its Roc test
closure, so it does not yet prove platform-only visibility or unforgeability.
The host cell is isolated to one synchronous advance and invalidated when
consumed, which removes stale process-global slot reuse from the measurement,
but a production feasibility spike must move the sole deposit into generated
platform code and ensure user transition code never receives the capability.

The focused
[`private-sink-spike`](../../private-sink-spike/README.md) now demonstrates
that corrected source boundary. An exposed `Sse.unfold!` wraps a user
transition returning next application state; a hidden platform capability is
available only to the wrapper's `advance_for_host!` conversion hook. Roc
`check`, an optimized archive build, and C glue generation pass on
`debug-e1d283cb`. Runtime lifecycle and allocation measurement of that corrected
wrapper remain deliberately open while work moves to the preferred composite
compiler fix.

## Observations

Both development and speed runs pass the complete lifecycle matrix:

```text
CORRECTNESS ok observed_calls=57 resource_allocations=16
resource_deallocations=16 max_independent=2
```

Representative seven-run medians from the original 100,000-step diagnostic
and the final compiler candidate are:

| Build and shape | Median ns/step | Allocations/step | Frees/step | Requested bytes/step |
| --- | ---: | ---: | ---: | ---: |
| speed, direct callable | 1.982 | 0 | 0 | not recorded |
| speed, composite source | 264.659 | 1 | 1 | 80 |
| speed, composite source, `d4921d8658` | 61.506 | 0 | 0 | 0 |
| speed, private one-shot cell | 211.533 | 0 | 0 | 0 |
| dev, direct callable | 175.810 | 1 | 1 | not recorded |
| dev, composite source | 1103.486 | 1 | 1 | 80 |
| dev, private one-shot cell | 1251.488 | 1 | 1 | 88 |

The final source samples ranged from 61.450 to 61.577 ns/step. Process-wide
instrumentation remained balanced at 174 allocations and 174 deallocations,
with zero reallocations and zero live allocations after the run.

The source and one-shot timings include the opaque-resource hosted call,
atomic allocation instrumentation, and validation checks. The one-shot result
uses a stack-embedded cell scoped to one synchronous advance; cancellation does
not inspect or destroy that cell before the call joins. These are not
Go-relative acceptance measurements. The item is shared static storage, so the
composite's 80 bytes are attributable to its next callable envelope rather
than event construction.

Generated C glue exposes `AbiSourceStep_payload_emit(const AbiSourceStep*)` by
value. That bit-copies the owning list and callable fields. The fixture treats
the returned copy as a manual move and never drops the shell afterward, which
is adequate for this diagnostic but is not a production ownership API. A real
adapter needs a generated consuming `take_emit` projection or an equivalent
opaque move wrapper.

## Compiler diagnosis, rejected optimization, and resolution

The baseline reuse demand reached an erased callee only when the whole result
representation is one erased callable. It does not identify the sole owned
callable slot nested in this tagged record, so the constructor allocates a new
continuation.

A broad experiment classified any result with one erased-callable ownership
slot as reusable. It was unsound. Repacking the old callable before sibling
result fields finished reading its capture changed `wait_millis` from the old
sequence to the new sequence. Staging the continuation field last still left
an `erased_capture_load` borrowing the old capture after ARC had consumed and
freed the outer allocation, and the speed fixture segfaulted.

Those experimental edits were removed before the final implementation. The
successful compiler change instead:

1. derives a whole-result demand for exactly one erased-callable ownership
   slot, treating aggregate fields as simultaneous and tag variants as
   alternatives;
2. snapshots the old capture record before any selected result slot can
   consume the outer callable, with the outer owner carried as an explicit
   sequencing/liveness operand;
3. gives the snapshot independent ownership of refcounted children before
   repacking;
4. propagates the selected destination through records, tuples, tags, boxes,
   nominal wrappers, and return-position finite helpers; and
5. records transparent ownership provenance while lowering, resolving it over
   a finite local graph rather than scanning completed LIR or using a fixed
   hop limit.

Ambiguous, cyclic, multi-slot, list, shared, and incompatible paths decline
reuse or take the runtime copy fallback. Adversarial review also found and
fixed whole-result/per-variant demand mismatch, callable-dispatch ambiguity,
and a guarded procedure-argument span that became stale after body lowering.

The compiler fix is committed and pushed to draft Roc PR
[`roc-lang/roc#10530`](https://github.com/roc-lang/roc/pull/10530).

## Design consequence

The composite result remains the semantic reference. Compiler feasibility now
has evidence for the required properties:

1. an explicit destination demand for one selected erased-callable slot inside
   an aggregate result;
2. materialization of every sibling value borrowed from the old capture before
   repacking;
3. explicit owner sequencing that keeps the old outer alive through capture
   snapshotting, with independent ownership for the snapshot; and
4. reuse only for the callee/result path proven to satisfy those conditions.

The compiler candidate satisfies these properties in the lifecycle fixture and
removes the continuation-envelope allocation. This does not select a public
API or resume production server implementation: generated consuming result
projection, the bounded scheduler/body adapter, Brotli drain acknowledgement,
and end-to-end allocation/latency gates remain open. The private one-shot cell
is retained only as historical fallback evidence and is not the selected ABI.

The complete scheduler and body contract is in
[`../../datastar-retained-source-contract.md`](../../datastar-retained-source-contract.md).
