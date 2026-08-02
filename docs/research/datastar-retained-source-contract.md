# Retained Roc SSE source contract

Status: composite-return compiler feasibility and Rust consuming projection
are proven by Roc candidates `d4921d8658` and `be78e95c42`; research has
resumed at the production scheduler adapter and retained-resource bound.

Date: 2026-08-02

This work does not change `design.md` and does not select the public API.

## Why the next gate changed

The earlier retained-callable fixture proved an important but narrower shape:
one owned callable consumes a wake value and returns its next callable. A real
SSE transition does more. It returns owned framed bytes, a next machine, and a
typed next-wake decision, or it ends or fails without a continuation.

The new composite fixture exercises that distinction. Its effectful machine
captures an opaque host resource and an immutable item, returns
`Emit({ item, machine, wait_millis })`, and also has an `End` branch. Parked
drop, whole returned-step drop, normal end, and cancellation while the Roc call
is blocked all balance the machine, item, and nested resource exactly once.

On the original compiler checkpoint `e1d283cbff`, the direct `machine ->
machine` release-speed transition was allocation-free, but the
production-shaped composite transition allocated and freed one 80-byte
continuation per emitted step. A less representative version without the
captured opaque resource allocated 72 bytes. The allocation was the next
callable envelope, not the returned item.

The first broad attempt to pass reuse through the composite result was
incorrect: it repacked the old callable before sibling result fields had
finished reading the old capture. The optimized fixture returned the new
sequence as the current wait value. This establishes an additional compiler
invariant: a nested continuation may consume and overwrite the old callable
only after every non-continuation result field has been evaluated.

Staging the continuation record field last was necessary but not sufficient.
The next candidate still had an `erased_capture_load` borrowing the old capture
on the flow from the newly packed callable to the returned aggregate. ARC had
already treated the old outer callable as consumed, freed that hidden owner,
and the optimized fixture segfaulted. This established that the safe compiler
transformation must model the remaining borrow explicitly and prove all
old-capture reads complete before repacking; merely reordering result fields is
not a sufficient proof.

Roc candidate `d4921d8658` now implements that proof with whole-result
single-slot demand, an entry-time owned capture snapshot, destination
propagation through aggregate constructors and return-position helpers, and
explicit lowering-time ownership provenance. The final seven 100,000-step
source samples report zero allocations, zero frees, and zero requested bytes
per step at approximately 61.45–61.58 ns/step. Full lifecycle accounting ends
with 174 allocations, 174 deallocations, and zero live allocations. The Roc
draft is [`roc-lang/roc#10530`](https://github.com/roc-lang/roc/pull/10530).

Roc candidate `be78e95c42` and the matched generated-Rust fixture also close
the projection part of the first proof. Unsafe generated borrow/take
primitives sit behind a non-`Copy` owner; whole-step, wrong-tag, aliased,
unique, both drop-order, no-allocation, native, and Wasm checks pass. Details
are in the
[consuming projection result](abi-spike/results/2026-08-02-consuming-rust-projection.md).

The research objective is therefore no longer simply “implement
`SseItemSource`.” Its compiler and Rust ownership prerequisites have local
candidates; the production transaction remains open:

1. validate and land the composite internal step ABI/compiler/glue support that
   preserves one atomic functional transition without per-step continuation
   allocation; and
2. implement a bounded asynchronous adapter whose state, retained capture
   admission, and acknowledgements match the body transaction exactly.

## Preferred internal ABI

The semantic reference remains a composite result:

```text
advance(owned Machine, WakeReason) -> StepToHost

StepToHost =
    Continue { framed_item, next: Machine, wake: NextWake }
  | Wait { next: Machine, wake: NextWake }
  | End
  | Error { detail }
```

The platform wrapper, not application code, produces this closed ABI value.
The public callback may return richer typed events and convenience outcomes;
the wrapper validates and canonically frames them before crossing to Rust.
`framed_item` is a distinct trusted internal owner, not an application-provided
raw byte stream.

`WakeReason` and `NextWake` must be closed types. The timer-only first slice
needs `Initial`, `Immediate`, and `Timer` reasons and `Now` or `After(duration)`
next wakes. Zero is not an overloaded duration sentinel. Pulse generation can
be added only with its stale-wake and waiter-capacity contract. Heartbeats are
host-produced transport items and do not require invoking Roc.

The generated Rust ABI candidate now provides the required consuming
projection. A borrowed owning-field copy remains forbidden. After tag
validation, the unsafe raw `take_payload_*_unchecked` moves the payload and
logically invalidates the shell; a non-`Copy` framework wrapper enforces that
contract for ordinary host code. Failed tag-specific extraction returns the
still-owned shell, while unextracted results whole-drop through `drop_step`.
Fixed generated wrappers remain the authority for dropping machines, items,
errors, and complete steps. Exact `Wait` and `Error` integration remains part
of the production adapter test matrix.

## Private one-shot result-slot alternative

A private one-shot step result slot is retained only as a measured ABI
alternative if the safe composite compiler implementation cannot meet the
allocation and batch-one latency gates. It may be considered an ABI
out-parameter, not a writer, only if all of these remain true:

- the slot is an unforgeable preallocated cell owned by one admitted advance;
- application code cannot see, retain, inspect, or invoke it;
- the platform wrapper must complete it exactly once with one closed
  Continue/Wait/End/Error value;
- it exposes no repeated write, flush, socket, backpressure, or capacity API;
- completion only deposits ownership and cannot publish, validate, wake the
  body, or arm the next wait while Roc is still executing; and
- callback return atomically joins the deposited result with the returned
  continuation before cancellation or success is resolved.

The direct callable return may preserve the already proven reuse path, but it
adds one hosted crossing and splits one logical result across two ABI actions.
It is selected only by equivalent lifecycle tests and a material measured win,
never merely because it is easier for the current compiler.

A minimal source-only fixture now proves the intended privacy topology is
expressible: `Sse.unfold!` wraps a user transition whose result contains next
application state rather than a next machine; the platform-owned wrapper alone
receives the hidden sink capability, deposits the lowered result, and directly
returns its next stream. Check, optimized archive build, and generated C ABI
pass. Runtime ownership and allocation measurements remain open, so this does
not select the alternative. See
[`private-sink-spike`](private-sink-spike/README.md).

## Production adapter state

One admitted source owns exactly one of these states:

```text
Precommit { input machine, initial budget, callback permit }
Parked    { machine, wake registration }
Advancing { in-flight record; body may only mark cancellation }
Draining  { next machine, framed item, next wake, budget token }
Ended
Closed
```

The in-flight record outlives body cancellation. Once a synchronous Roc call
starts, cancellation marks it and returns without destroying the input or any
context/resource heap the call may still use. Completion then whole-drops the
returned step if cancelled, or moves it to `Draining`. It releases callback
accounting exactly once in either case.

`SseItemSource::poll_item` alone was insufficient for this lifecycle. The body
now has an explicit `item_drained` acknowledgement after the final identity
frame is committed or Brotli FLUSH completes. Only that acknowledgement may
move `Draining -> Parked` and arm `NextWake`. Cancellation before it drops the
next machine and item without a wake or a second Roc invocation.

The acknowledgement is required, infallible, and nonblocking. It cannot invoke
Roc synchronously. Waiter/timer capacity is admitted before advance so the
transition cannot partially park or arm a wake and then report failure. Test
sources must implement an explicit no-op rather than inheriting a default that
could hide an omitted production transition.

The first advance runs before response commitment. It must acquire the stream
slot, callback permit, maximum uncompressed-step budget, and any selected
compressed-stream unit before entering Roc. An immediate validation, framing,
or application error therefore remains an ordinary pre-commit response. The
body is constructed only with a validated initial result or a parked wait.

The maximum uncompressed-step budget is a real admission token, not a
post-return length check. `max_item_bytes` remains defense in depth, but cannot
prevent many simultaneous callbacks from each returning their maximum payload.
The token is acquired before scheduling Roc, follows the returned bytes through
`Draining`, and is released on drain or every terminal path. It may shrink to
actual bytes after validation without changing the configured worst-case
admission bound.

The parked machine is itself a resource-bearing value. A stream slot bounds
the number of machines but does not bound application-selected Roc strings,
lists, boxes, or opaque host resources captured by each machine. Before the
scope change can be accepted, the platform needs either an enforceable
per-stream capture/resource admission unit or a narrower public construction
contract whose maximum retained weight is known. Observing allocation counts
after creation is not sufficient admission, and an opaque resource must expose
its configured weight without revealing its representation. The selected
token follows the machine through `Precommit`, `Parked`, `Advancing`, and
`Draining` and is returned exactly once on every terminal path.

## Ordering contract

One successful emitted transition is:

1. reserve callback execution and maximum uncompressed output budget;
2. ensure the body has capacity for progress;
3. move the sole input machine into a non-overlapping synchronous Roc call;
4. validate the closed result and move its item, next machine, wake, and budget
   into one `Draining` record;
5. release the callback permit at the defined CPU boundary;
6. reserve one fixed body frame before every identity copy or Brotli PROCESS
   and FLUSH operation;
7. after the final frame is host-owned, call `item_drained` exactly once;
8. release the item and uncompressed budget, park the next machine, and only
   then arm its typed wake; and
9. acquire fresh admission before any subsequent advance.

No wake is armed and no second advance begins while the prior logical item is
draining. Success means accepted into bounded host ownership, not delivered to
the peer.

## Required acceptance evidence

The retained-source gate is not closed until one production adapter proves:

- direct and composite ABI behavior in development and release-speed builds;
- zero steady continuation-envelope allocations on the unique hot path, with
  dynamic item allocations reported separately;
- generated Rust consuming result projection rather than borrowed
  owning-field copies (passed locally; production integration remains);
- aliased captured items and unique changing items, with machine-first and
  item-first destruction orders;
- Continue, Wait, End, Error, oversized item, and invalid framing cleanup;
- batch-one latency plus batches 4 and 16 without using batching to conceal the
  single-item result;
- no advance before a timer, exactly one after it, stale wake rejection, and
  bounded immediate-step fairness;
- no wake or re-entry before `item_drained`, including repeated body `Pending`
  during identity, Brotli PROCESS, and Brotli FLUSH;
- cancellation in Precommit, Parked, Advancing, returned-before-validation,
  Draining, PROCESS, FLUSH, End, and Error;
- lost/replaced waker races and repeated cancel/drop idempotence;
- callback, byte-budget, item, machine, frame, encoder, request, and waiter
  accounting all returning to zero;
- retained Roc capture/opaque-resource admission with a fixed high-water mark
  and exact terminal release; and
- a real one-slot `SseBody` composition where one Roc advance spans multiple
  identity frames and multiple Brotli PROCESS/FLUSH frames without blocking a
  Hyper/Tokio worker.

After this P0 gate, the next stage remains mixed HTTP/2 isolation, graceful
drain/shutdown, full Hyper/Tokio/socket allocation accounting, changing-corpus
latency, and ordinary-request p99 under stopped readers.
