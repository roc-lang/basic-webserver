# Composite retained-source result

Date: 2026-08-02

Status: composite lifecycle passes; optimized continuation allocation remains
open; private one-shot alternative is allocation-free but not selected.

## Question

The previous fixture returned only the next retained callable. A production SSE
advance instead needs a closed result containing an owned framed item, the next
callable, and a next-wake decision, or a terminal outcome. This follow-up asks
whether that nested callable retains the direct result's zero-allocation reuse
and whether a private one-shot result cell is a viable internal alternative.

## Reproduction

The compiler was rebuilt from clean Roc branch
`datastar-erased-repack-arc` at `e1d283cbff4230e8354f72959a0367a8200771ad`:

```sh
cd /path/to/roc
zig build roc

cd /path/to/basic-webserver
ROC=/path/to/roc/zig-out/bin/roc \
ROC_SRC=/path/to/roc \
python3 scripts/spike_retained_callable.py \
  --opt all --iterations 100000 --mode wrapper
```

The resulting compiler reports `debug-e1d283cb`. The run was not CPU-pinned,
so timing is diagnostic; allocation counts and lifecycle assertions are the
strong evidence.

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

Representative seven-run medians from the 100,000-step diagnostic are:

| Build and shape | Median ns/step | Allocations/step | Frees/step | Requested bytes/step |
| --- | ---: | ---: | ---: | ---: |
| speed, direct callable | 1.982 | 0 | 0 | not recorded |
| speed, composite source | 264.659 | 1 | 1 | 80 |
| speed, private one-shot cell | 211.533 | 0 | 0 | 0 |
| dev, direct callable | 175.810 | 1 | 1 | not recorded |
| dev, composite source | 1103.486 | 1 | 1 | 80 |
| dev, private one-shot cell | 1251.488 | 1 | 1 | 88 |

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

## Compiler diagnosis and rejected optimization

The current reuse demand reaches an erased callee only when the whole result
representation is one erased callable. It does not identify the sole owned
callable slot nested in this tagged record, so the constructor allocates a new
continuation.

A broad experiment classified any result with one erased-callable ownership
slot as reusable. It was unsound. Repacking the old callable before sibling
result fields finished reading its capture changed `wait_millis` from the old
sequence to the new sequence. Staging the continuation field last still left
an `erased_capture_load` borrowing the old capture after ARC had consumed and
freed the outer allocation, and the speed fixture segfaulted.

The experimental compiler edits were removed. The Roc checkout and rebuilt
compiler are back at the safe `e1d283cb` source. No unsafe compiler change is
part of either draft PR.

## Design consequence

The composite result remains the semantic reference. A principled compiler
implementation needs:

1. an explicit destination demand for one selected erased-callable slot inside
   an aggregate result;
2. materialization of every sibling value borrowed from the old capture before
   repacking;
3. an ARC borrow edge keeping the old outer alive through that staging; and
4. reuse only for the callee/result path proven to satisfy those conditions.

Until that feature exists, the safe composite result costs one allocation and
free per emitted item. The private one-shot cell is the only measured
allocation-free speed-path alternative, but it splits the logical result over a
hosted deposit and direct return. It may be selected only after removing the
low-level fixture's application-visible capability and proving exactly-once
deposit, post-return join, cancellation, and the corrected platform wrapper's
allocation cost in the production adapter. The source-only private fixture now
proves the intended visibility boundary, not those runtime properties.

The complete scheduler and body contract is in
[`../../datastar-retained-source-contract.md`](../../datastar-retained-source-contract.md).
