# Explicit application stream-state spike

This disposable fixture tests the supported fallback from
[`docs/datastar-experiment.md`](../../datastar-experiment.md): a fourth
application `stream!`-like entrypoint whose application-defined state crosses
fixed generated provided functions as `Box(StreamState)`.

It deliberately does not invoke, inspect, or drop erased callable payloads.
It is research evidence, not platform implementation, and does not change
[`design.md`](../../../design.md).

## Reproduce

The complete development, optimized, and Go comparison is:

```sh
taskset -c 2 python3 scripts/spike_explicit_state.py \
  --opt all --iterations 1000000 --repetitions 9
```

The script regenerates C glue using the Roc compiler from `PATH`, compiles the
host fixture for x64 Linux musl, builds development and speed Roc executables,
and builds the Go reference with `/tmp/go1.26.5/bin/go`. `ROC_SRC`, `ROC`,
`ZIG`, and `GO_BIN` can override tool discovery.

The committed run used source commit `785b425`, Roc compiler
`159b5e9583132178ff2c71d715058c334e26ab16`, and the environment recorded in
[`results/2026-08-01-environment.txt`](results/2026-08-01-environment.txt).
Raw samples are in
[`results/2026-08-01-pinned-cpu.tsv`](results/2026-08-01-pinned-cpu.tsv).

## Lifecycle result

**Observed:** both development and speed builds pass, using only these
generated provided symbols:

- initialize an application state box;
- consume one state box and return the next;
- transfer a state box unchanged as a diagnostic; and
- consume and drop a parked state box.

The host fixture demonstrates:

- parked-state and just-returned-state destruction;
- twelve sequential ownership-consuming advances across four newly joined
  pthreads;
- deterministic overlap of two independent states inside a blocked hosted
  effect;
- host-side rejection of a second advance while one stream slot is busy;
- cancellation while a step is blocked in a hosted effect, followed by drop of
  the returned state instead of reparking it;
- nested heap strings and lists surviving repeated state transitions;
- an opaque host resource closing exactly once on final Roc ARC release; and
- allocation and resource counts returning exactly to zero after each case.

The final correctness line in each backend was:

```text
CORRECTNESS ok observed_calls=18 resource_allocations=7 resource_deallocations=7 max_independent=2
```

Development ended with `300044` allocations and deallocations; speed ended
with `300064` of each. Both reported zero live allocations and zero reallocs.
The different totals are backend initialization details; balance, not equality
between backends, is the invariant.

This is strong local evidence for the explicit-state ownership topology. It is
not yet cross-target or memory-sanitizer evidence.

## Package encapsulation result

**Observed:** a sibling Roc package defines the opaque nominal
`FeedRoute.FeedRoute`, including its private nested record. The application can
put that type inside its shared route union, initialize it through public
package methods, dispatch a step to the package, and return it through the
same generated `Box(State)` ABI. Development and speed builds both compile and
execute this branch.

Therefore the experiment's statement that packages cannot privately
encapsulate explicit stream state is too strong. A realistic shape is:

```roc
StreamState : [Dashboard(Dashboard.StreamState), Todos(Todos.StreamState)]
```

Package payload representation and transition logic can remain private. The
real ergonomic cost remains: the application must centrally enumerate every
stream route in one union and centrally dispatch the fourth entrypoint. A
package cannot install a new private state case without application wiring,
and all SSE applications still expose one shared `StreamState` to the platform.

A platform-owned closed dynamic bag such as route ID plus lists of words,
strings, and handles would hide neither this wiring nor the concrete payload
problem. It would discard Roc's static types and package APIs. It is not a good
replacement for the route union.

## Performance comparison

### Contract

The transition advances the same wrapping checksum once per logical event and
carries a roughly equivalent rich state containing two strings and a list.
The Roc state is a tagged application union; the optimized outer box allocation
is 96 bytes. The Go reference state is 72 bytes.

The comparison reports two Go implementations:

- `unique` mutates the transferred, uniquely owned state and returns the same
  pointer. This is the semantic-equivalence baseline and the behavior Roc
  should aspire to.
- `replace` allocates a new state every step. It diagnoses the cost class of
  current Roc lowering, but it is not the target because Go does not require
  replacement under unique ownership.

`transition_pool` is a synthetic Roc lower bound. During the single-threaded
timing region only, the fixture recycles one known 96-byte state allocation.
It does not change compiler-visible allocation or ARC behavior, does not prove
a safe cross-thread production allocator, and is not counted as current
behavior.

Allocation counters run separately from latency timing. Timed Roc operations
disable the fixture's atomic allocation ledger, and all implementations perform
10,000 warmup transitions before each of nine one-million-step samples.

### Optimized medians

All values are median nanoseconds from the pinned-CPU run.

| Implementation | Batch | ns/step | ns/event | Allocations/step |
| --- | ---: | ---: | ---: | ---: |
| Roc current | 1 | 26.702 | 26.702 | 1 |
| Roc current | 4 | 27.472 | 6.868 | 1 |
| Roc current | 16 | 27.414 | 1.713 | 1 |
| Roc synthetic allocation reuse | 1 | 16.744 | 16.744 | 1 compiler request, recycled storage |
| Roc synthetic allocation reuse | 4 | 17.083 | 4.271 | 1 compiler request, recycled storage |
| Roc synthetic allocation reuse | 16 | 16.917 | 1.057 | 1 compiler request, recycled storage |
| Go unique | 1 | 1.271 | 1.271 | 0 |
| Go unique | 4 | 5.115 | 1.279 | 0 |
| Go unique | 16 | 20.403 | 1.275 | 0 |
| Go replace | 1 | 16.916 | 16.916 | 1 |
| Go replace | 4 | 18.055 | 4.514 | 1 |
| Go replace | 16 | 28.982 | 1.811 | 1 |

The current Roc fallback is about 21.0x, 5.4x, and 1.34x slower per event than
unique Go at batches 1, 4, and 16 respectively. It is slightly faster than
allocation-matched Go only at batch 16. Synthetic allocator reuse beats unique
Go by about 17% per event at batch 16, but remains 13.2x slower for the
single-event case.

Batching is still worth supporting when several events are already available:
one ownership transition and one ABI entry can return the bounded batch, after
which transport can flush every event independently. The scheduler must not
wait to fill a batch, and batch-16 throughput cannot be used to hide failed
single-event latency or weaken backpressure.

### Gap attribution

**Observed:** the speed backend requests exactly one outer allocation and one
free per step at every batch size. It requests zero for the identity
roundtrip. Event batching therefore amortizes outer state reconstruction to
`1/N` allocations per event but does not remove it.

Optimized disassembly makes the lower bound clearer:

```sh
nm -S --size-sort build/explicit-state-spike/explicit-state-speed \
  | rg 'roc_explicit_(bench|roundtrip)|roc_llvm_rc_decref'
objdump -d build/explicit-state-spike/explicit-state-speed \
  | sed -n '/<roc_explicit_roundtrip_state>:/,/^$/p'
objdump -d build/explicit-state-spike/explicit-state-speed \
  | sed -n '/<roc_explicit_bench_state>:/,/^$/p'
```

The 41-byte identity wrapper executes an atomic `lock incq` of the outer box,
then calls its generated decref helper before returning the same pointer. Thus
even an unchanged owned state is lowered as temporary sharing rather than a
pure ownership transfer. Its median is 7.844 ns versus Go's 0.907 ns.

The 57-byte transition wrapper calls a 2,311-byte application-specialized
procedure and then decrefs the old box. That procedure contains branch-specific
atomic retains for nested ARC values and a `roc_alloc` call for the new 96-byte
box. The allocation ledger, disassembly, roundtrip lower bound, and synthetic
pool together attribute the gap to outer box reconstruction plus ARC ownership
traffic, not the checksum loop.

## Design recommendation

The current explicit `stream!` plus `Box(StreamState)` fallback passes the
local lifecycle gate and is viable for further transport integration, but it
does **not** pass the meet-or-exceed-Go hot-step performance gate. Do not select
it as the final first-class API on the basis of batching or allocator caching.

Keep it as the supported feasibility fallback while pursuing a generated
owned-state adapter with these semantics:

1. input ownership is consumed without an outer retain/decref pair;
2. a uniquely owned state allocation may be updated/repacked in place;
3. nested unchanged ARC fields move rather than retain then release;
4. generated code remains responsible for application-specialized move/drop;
5. the host sees an opaque typed adapter, not application layout bytes; and
6. cross-thread movement remains sequential and synchronized by the host.

If in-place box reuse cannot be added, a generated opaque-storage ABI exposing
size, alignment, move, step, and drop adapters is worth a separate compiler
spike. A dynamically typed platform state bag is not.

The experiment document should change its fallback assessment to say that
package payload encapsulation works through an application route-tag union,
while central enumeration and dispatch remain. Spike 1 should add explicit
pass criteria for no temporary outer ARC pair and unique state-storage reuse;
the batch-1 result remains decisive.
