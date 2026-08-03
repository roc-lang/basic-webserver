# Host-owned Context and retained source result

Date: 2026-08-03

## Question

Can `basic-webserver` keep one opaque application `Context` owner in Rust,
allow Roc to construct ergonomic typed retained sources from it, and preserve
the allocation-free optimized source transition?

The intended application-facing shape remains the existing generic handler:

```text
respond!(Request, Context) -> Result(Response, Error)
```

`Sse.unfold!` is a Roc-side typed constructor. Rust neither knows the context
layout nor calls an application-wide `advance_sse!` dispatcher.

## Ownership shape exercised

The reduced platform wrapper accepts `Box(State)`, matching the production
platform's boxed application context boundary. Rust stores one non-`Copy`
`OwnedContext`. Before calling Roc it increments that box once and transfers
the new owner into the generated wrapper. Roc unboxes the value and constructs
a source whose closure captures the context fields it needs.

The fixture constructs two sources from the same host root, consumes both from
their `Response | Stream(SourceMachine)` outcomes, and then drops the host root
first. One source advances through `Emit`; its item and next machine are
dropped. The other source is cancelled while parked. The final live Roc
allocation count is zero, including the captured opaque resource.

This is deliberately ownership of an opaque Roc allocation, not Rust
allocation of a guessed `Context` layout. It is analogous to the typed heaps:
the host controls the finite owner slots and lifecycle while generated Roc ABI
functions remain the authority for sharing and destruction.

## Compiler regression found by the exact shape

Fast-forwarding the Roc research branch exposed two compiler issues rather
than a context-API limitation.

First, lazily expanding recursive types while traversing the solved lambda
graph could grow a backing store and invalidate slices held by the recursive
walk. The exact `Context -> Outcome(Stream)` glue shape exposed this as an
invalid `Type.Store` index. Roc commit `939715902e` changes those walks to keep
stable spans and reload elements by index.

Second, compiler commit `794da02959` had intentionally removed heuristic
whole-body return-flow scans, but the replacement recognized only a pack whose
target was already the final return local. A recursive source written
idiomatically as `next = recur(...)` and then boxed or aliased therefore lost
the affine erased-callable reuse destination and allocated a new continuation
envelope every step.

Roc commit `6d65420689` records explicit lexical return-destination provenance
during backward lowering. It transfers the one reuse destination through
representation-preserving aliases, `let` producers, and the explicit `Box`
boundary. If two eager producers compete for one later result, both decline
the affine reuse owner. Repeatable loop and recursive-join regions suppress
forwarding because one lexical producer can execute more than once. There is no
completed-body scan, arbitrary walk limit, or intermediate owner selected after
exhaustion.

## Commands and result

```sh
ROC=/home/lbw/Documents/Github/roc-main-datastar-check/zig-out/bin/roc \
ROC_SRC=/home/lbw/Documents/Github/roc-main-datastar-check \
python3 scripts/spike_retained_callable.py \
  --opt all --iterations 100000 --mode wrapper --host rust

ROC=/home/lbw/Documents/Github/roc-main-datastar-check/zig-out/bin/roc \
ROC_SRC=/home/lbw/Documents/Github/roc-main-datastar-check \
python3 scripts/spike_retained_callable.py \
  --opt all --iterations 100000 --mode wrapper --host c
```

Generated Rust passed with warnings denied, including its affine-owner
compile-fail check. Development and release-speed C and Rust lifecycle runs
passed. The optimized C measurements were:

```text
machine: 0 allocator/deallocator calls per step, approximately 5.1 ns/step
state:   0 allocator/deallocator calls per step, approximately 1.44 ns/step
source:  0 allocator/deallocator calls or requested bytes per step,
         approximately 63.2 ns/step
sink:    0 allocator/deallocator calls per step, approximately 57.7--58.8 ns/step
final:   174 allocations, 174 deallocations, 0 live allocations
```

Development mode still allocates while preserving exact ownership. The
zero-allocation claim is for the optimized unique-compatible hot path.

## API consequence

The preferred API does not need a new application-level `advance_sse!`
entrypoint. Applications can keep `{ init!, respond!, shutdown! }` and use a
typed `Sse.unfold!` transition that receives ordinary `Context` ergonomically.
The private platform wrapper closes over the immutable context when it builds
the source; the fixed-capacity host stream heap subsequently owns the one
opaque source value.

This bounds stream count and every host-introduced slot, callback, timer,
buffer, frame, Brotli lane, and opaque native resource. It does not claim a
transitive byte quota for arbitrary Roc values deliberately retained by trusted
application code.

The next feasibility gate is composition through the real generic
`Server.Outcome`, listener, scheduler, cancellation, and bounded Brotli
executor rather than another callable ABI redesign.
