# Outcome-owned source and bounded host stream heap

Date: 2026-08-03

Roc compiler checkout:

```text
/home/lbw/Documents/Github/roc-main-datastar-check
d4921d8658 Reuse erased callables in aggregate results
be78e95c42 Generate consuming Rust tag payload projections
```

The binary reports `debug-d4921d86`; RustGlue is read from the same checkout at
`be78e95c42`.

## Question

Can the ergonomic retained-source design keep the existing
`{ init!, respond!, shutdown! }` application contract while giving Rust finite,
stable, cancellation-safe ownership comparable to the platform's typed resource
heaps?

The reduced production-shaped boundary is:

```text
SourceOutcome = Response(status) | Stream(owned SourceMachine)

SourceMachine(wake) = Emit { item, next machine, wait } | End
```

Rust consumes the `Stream` payload from the owned outcome shell into a
fixed-capacity host heap. Each slot has a slot generation, wake generation,
phase, and exactly one parked source or in-flight completion.

## Command

```sh
ROC=/home/lbw/Documents/Github/roc-main-datastar-check/zig-out/bin/roc \
ROC_SRC=/home/lbw/Documents/Github/roc-main-datastar-check \
python3 scripts/spike_retained_callable.py \
  --opt all --iterations 100000 --mode wrapper --host rust
```

The generated-Rust development and speed executables both passed. The same
application and changed public glue surface also passed the existing C host
lifecycle in development and speed builds:

```sh
ROC=/home/lbw/Documents/Github/roc-main-datastar-check/zig-out/bin/roc \
ROC_SRC=/home/lbw/Documents/Github/roc-main-datastar-check \
python3 scripts/spike_retained_callable.py \
  --opt all --iterations 100000 --mode wrapper --host c
```

The optimized C-host run retained the prior source result:

```text
source: 61.849--62.162 ns/step
source allocator calls: 0/step
source deallocator calls: 0/step
source requested bytes: 0/step
final accounting: 174 allocations, 174 deallocations, 0 live
resource accounting: 16 allocations, 16 deallocations
```

## Proven lifecycle

The generated-Rust fixture now checks:

- ordinary outcomes whole-drop through the generated provided wrapper;
- the `Stream` source is consuming-moved out of its outcome shell;
- outcome projection changes neither allocator calls, deallocator calls, nor
  requested bytes;
- a capacity-two heap admits exactly two streams and preserves ownership of the
  rejected third outcome;
- cancellation frees a slot and increments its generation before reuse;
- stale slot handles and stale wake generations cannot advance a replacement;
- moving a source into `Advancing` prevents a second simultaneous advance;
- only drain acknowledgement drops the current item, increments the wake
  generation, and returns the next source to `Parked`;
- normal `Emit` followed by `End` releases the slot;
- parked and draining cancellation recursively drop the source/item once; and
- cancellation during an advance retains capacity until the finite call
  completes, then whole-drops its returned Step instead of parking it.

Every Rust test group ends with zero live Roc allocations. Captured opaque
resources are included in that recursive accounting.

## Interpretation

This falsifies the claim that a fixed application-level `advance_sse!`
entrypoint or byte cursor is required to give the host bounded stream capacity
and exact lifecycle ownership. The host can own one arbitrary typed Roc source
inside a finite stream heap using supported generated wrappers.

It does not prove a transitive byte quota for the Roc capture. That stronger
property is outside the platform's current trusted-application allocation
model and would require allocator-domain/compiler work.

## Remaining gaps

- Compose this owner with `Server.Outcome`, `SseBody`, request accounting, and
  an actually bound listener rather than the reduced ABI sum.
- Add exact `Wait` and application-error payloads.
- Prove timer and immediate wake scheduling under real concurrency and herds.
- Compose the proven host-owned `Box(Context)` source construction with the
  real `respond!` wrapper and listener.
- Retain native/Wasm and supported-target compiler/glue gates after upstream
  review.
- Measure the full listener path and integrate bounded Brotli CPU execution.
