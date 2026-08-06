# Hot-path allocation provenance

This note identifies the allocation sites behind the two surviving
single-transition allocations in the SSE state ABI spikes. The measurements
use Roc main `1c1ceccf672248bcd367cf3b21f4daadc0afd318` on Linux x86-64 with
the speed backend. This is compiler and ABI research, not a claim about the
event framing, scheduler, or Brotli paths.

## Result

The allocations are not inherent in SSE or in the application state. They are
replacement allocations introduced by current lowering:

| Candidate | Allocation site | Request | Why it allocates |
| --- | --- | ---: | --- |
| Recursive callable | Captured callback `roc__proc_11b` | 40 bytes, alignment 16 | Returning the next immutable continuation constructs a fresh erased-callable box. |
| Explicit state | State transition `roc__proc_129` | 96 bytes, alignment 8 | Reboxing the result of a multi-branch `State` match falls outside the current local box-reuse recognizer. |

The simple `U64` explicit-state control in the retained-callable fixture
already lowers through `box_prepare_update`, requests no allocation per step,
and measures about 1.45 ns/step. That proves the host loop and generated
provided boundary do not inherently require an allocation. It is not a
representative state benchmark.

## Recursive callable trace

The benchmark constructs its next machine here:

```roc
bench_machine_from_value = |value|
    Abi.BenchMachine.BenchMachine(Box.box(|wake|
        bench_machine_from_value(value + wake + 1)
    ))
```

`roc_abi_advance_bench_machine` invokes the erased callable indirectly. The
invoked procedure computes the next captured `U64`, then performs the only
allocation in the transition:

```text
roc__proc_11b:
    ... compute value + wake + 1 ...
    mov $0x28, %edi
    mov $0x10, %esi
    call roc_alloc
    ... write refcount, proc pointer, on_drop pointer, and captured U64 ...
```

The old callable allocation is a local in the caller. The
`assign_packed_erased_fn` that creates the replacement is in the indirectly
invoked callee, which receives the raw capture pointer but not a reusable
ownership token for the outer callable allocation. The compiler therefore has
no local that it can attach to the replacement pack as `reuse`.

Roc already has the required same-procedure machinery:

- LIR `assign_packed_erased_fn` has `reuse` and `reuse_unique` fields;
- `box_reuse.zig` can fuse adjacent, same-shape erased packs in one procedure;
- `erased_callable_repack` reuses a unique allocation and performs a runtime
  uniqueness fallback when it is shared; and
- the interpreter, development, LLVM, and Wasm backends emit this operation.

The missing connection is across the erased indirect-call boundary. The
existing local rewrite cannot see a caller-owned allocation from inside the
callee that constructs its replacement.

The generated advance wrapper also performs two atomic increments and three
decrement-helper calls around the invocation. Those operations are separate
from the allocation, but an owned hot-step design must remove them as well;
repacking cannot be considered complete while temporary wrapper ownership
keeps the old allocation non-unique.

## Adjacent erased-repack ARC regression

The investigation found a narrower compiler bug adjacent to, but not causal
for, the recursive transition allocation. `box_reuse.zig` correctly writes
`reuse = old_callable` for two eligible packs in one procedure. During ARC
materialization, `arc.zig` reconstructs `assign_packed_erased_fn` without
copying `reuse` or `reuse_unique`. Its ownership planner and one liveness scan
also omit the consumed reuse operand.

A focused unit test observed:

```text
before ARC: replacement reuse = old_callable
after ARC:  replacement reuse = null, reuse_unique = false
```

A research-only compiler patch did all of the following:

- preserved `reuse` while materializing the statement;
- consumed the reused allocation in the ARC ownership state;
- retained it only when a later use requires preservation;
- marked it statically unique only when the ownership and liveness facts prove
  that runtime checking is unnecessary; and
- included the reuse operand in the read-before-rebind graph.

All 201 `lir` module tests, including the new regression, passed. Rebuilding
Roc with this patch and rerunning 100,000 callable transitions still produced
exactly one allocation and one free per step. This is the expected result: the
patch repairs already-recognized same-procedure repacks, but the SSE machine's
old and new packs are in different procedures.

The exact research patch is preserved as
[`2026-08-01-arc-repack-prototype.patch`](2026-08-01-arc-repack-prototype.patch).
It is a feasibility artifact, not a compiler-ready change: it has only the LIR
module coverage above and still needs adversarial ownership review, full
compiler tests, and backend/runtime cases before proposing it upstream.

This regression should be fixed independently. Merely copying the two fields
is not sound because ARC would still regard the old allocation as live and
could release it after the repack.

## Explicit-state trace

The representative fallback wrapper is:

```roc
bench_state_for_host = |boxed_state, wake, event_count|
    Box.box((program.bench_stream)(wake, event_count, Box.unbox(boxed_state)))
```

`roc_explicit_bench_state` calls `roc__proc_129`, then decrements the old outer
box. `roc__proc_129` unpacks the tagged union, switches over its route variants,
advances and moves the selected nested fields, and finally requests a 96-byte
replacement allocation:

```text
mov $0x60, %edi
mov $0x08, %esi
call roc_alloc
```

It writes the replacement union into that fresh box and returns it. Roc's
`box_prepare_update` primitive already has the right unique-or-copy runtime
semantics, but `box_reuse.zig` deliberately recognizes straight-line
unbox/produce/rebox and limited single-join forms. It does not currently carry
the reusable box through a general switch and merge the branch results into an
in-place store.

## Elimination hypotheses

### Owned erased-call replacement

This preserves the most ergonomic application API: a stream is an opaque
callable and each invocation returns its next continuation. It requires an
owned erased-call operation or equivalent generated adapter that:

1. passes a reusable outer callable allocation to the invoked procedure as a
   hidden ownership token, not merely its raw capture pointer;
2. keeps the old capture readable until the invocation has computed the new
   capture;
3. lets the final same-shape pack repack that allocation after the last old
   capture read;
4. proves the input unique for the common single-owner stream, with the
   existing runtime uniqueness fallback for shared values;
5. allocates normally when size or alignment changes;
6. runs the old capture's `on_drop` exactly once before overwriting it; and
7. expresses consumed ownership in LIR/ARC so generated provided wrappers do
   not surround the call with temporary outer retains and decrefs.

This changes the internal erased-call convention and must be implemented and
tested consistently in the interpreter, development, LLVM, and Wasm backends.
It is the direct route to the desired closure ergonomics, but it has the wider
compiler blast radius.

### Generated opaque state update

This separates stable transition code from replaceable state. The host retains
an opaque machine; a generated typed wrapper consumes its unique state cell,
calls the application transition, and writes the next state back into the same
allocation. It can be implemented by either:

- extending box reuse through switches and joins; or
- introducing a supported owned `Box.update`-like LIR/glue operation whose
  lowering makes the reusable allocation explicit across an arbitrary typed
  transition.

The public API can still be constructor-oriented, for example a typed initial
state plus transition function, while the generated host ABI erases the state
type. The compiler must preserve package-private state, exact nested ARC moves,
and a runtime copy fallback if a state cell is shared. This route has a smaller
call-convention change but needs a credible ergonomic story for route-local
state rather than forcing every application into one central union.

## Next spikes and gates

The next feasibility work should proceed in this order:

1. Land the adjacent ARC repack regression with a post-ARC unit test.
2. Prototype owned erased-call replacement for the one-`U64` continuation and
   require zero allocations plus zero temporary outer ARC operations.
3. In parallel, prototype a generated owned state update across the existing
   four-variant representative `State` match.
4. Run both mechanisms through nested strings, lists, package-private nominal
   state, opaque resources, cancellation, thread migration, and independent
   concurrency.
5. Compare batch 1 against the matched unique Go fixture before choosing the
   public application contract.

Acceptance is not “the allocator is pooled” or “batching amortizes the cost.”
The selected unique-owner transition must request zero hot-path allocations,
avoid temporary outer atomic ARC, move unchanged nested fields, preserve the
shared-value fallback, and balance every parked, returned, cancelled, and
dropped state exactly once.
