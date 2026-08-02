# Bounded-cursor Datastar feasibility slice

Status: preferred product hypothesis after retained-state adversarial review

Date: 2026-08-02

This is implementation-specific research guidance, not an accepted platform
contract. It does not change [`design.md`](../../design.md) or select final
public names.

## Why the state model changed

The callable work proves that Roc can safely and efficiently retain, advance,
move, and destroy an arbitrary captured machine. It does not prove that
`basic-webserver` can admit the retained resources of that machine.

A stream slot bounds one callable descriptor, timer, body, and encoder. It does
not bound the transitive strings, lists, boxes, seamless backings, or opaque
resources reachable through the capture. The host allocator records the size
of each allocation but not which stream owns or reaches it. The callable ABI
exposes invoke and drop operations, not an alias-aware graph visitor.

The tempting substitutes are unsound:

- outer callable size measures only its inline capture descriptors;
- allocation deltas miss pre-existing captured values, aliases, and concurrent
  allocations and cannot separate returned items from next state;
- an application-declared estimate is not enforcement; and
- `Context` is not a precedent for arbitrary per-stream state: it is one
  startup root, while streams are request-created, attacker-multiplicative, and
  can grow on every step.

The preferred product hypothesis therefore does not retain an arbitrary Roc
graph. It retains one host-owned bounded cursor and invokes one fixed provided
application callback with fresh `Context` on every step.

## Candidate application shape

Conceptually:

```roc
program = { init!, respond!, advance_sse!, shutdown! }

advance_sse! : Sse.Wake, Sse.SourceId, Sse.Cursor, Context
    => Try(Sse.Step, [ServerErr(Str), ..])

Sse.Step =
    [ Emit { events : List(Sse.Event), next : Sse.Cursor, wake : Sse.NextWake }
    , Wait { next : Sse.Cursor, wake : Sse.NextWake }
    , End
    ]
```

`SourceId` is a closed scalar or other fixed host representation. `Cursor` is
bounded owned bytes selected from named size classes, not an arbitrary Roc
type, callable, box, seamless slice, or opaque resource handle. The host owns
and validates it between calls. First-party helpers should make encoding and
decoding small typed route cursors routine; realistic Datastar cursors are
usually row/version/user IDs, retry position, and `Last-Event-ID`, while fresh
domain state comes from SQLite through `Context` on each callback.

The source entrypoint is fixed generated ABI, not a callback registry. The
initial `respond!` invocation authorizes the stream and returns source ID,
cursor, and typed options. Later invocations receive no request body or
borrowed request views.

This deliberately revisits the earlier preference to keep the program shape at
three entrypoints. The extra fixed callback is justified if it is the narrowest
way to satisfy the platform's resource invariant. API ergonomics must be tested
against realistic Roc and Go applications before acceptance.

## Admission and ownership

Before the initial response commits, reserve:

- one stream slot and per-connection stream slot;
- the selected cursor class's full byte capacity;
- callback and ready/waiter capacity;
- maximum uncompressed step bytes;
- body frames;
- selected compression lane/profile state; and
- active request/shutdown accounting.

The initial cursor is copied or moved into independently owned host storage and
must fit the reserved class. On `Emit` or `Wait`, validate `next.len` before
parking it. Initial overflow is an ordinary precommit error. Postcommit overflow
logs and closes the stream after dropping the returned item and cursor exactly
once. Replacing a cursor never holds two reserved cursor capacities after the
atomic step result has been validated and moved.

Opaque resources cannot appear in the cursor. Stable capabilities arrive only
through freshly retained `Context`; transient handles created during one step
must be released before return. Each host subsystem keeps its own global finite
heap and saturation policy rather than pretending handles are byte-equivalent.

The scheduler owns exactly one state:

```text
Precommit { source, cursor, reservations }
Parked    { source, cursor, generation, timer }
Admitting { source, cursor, generation }
Advancing { generation, non-cancellable completion owner }
Draining  { source, next cursor, wake, item, byte token }
Ended
Closed
```

The first slice can reuse the existing bounded handler admission and its exact
Tokio blocking-thread ceiling. An in-flight operation retains its active permit
and active-request reference until the synchronous Roc callback actually
returns. Dropping a join handle must not release either early. The final design
may need class reservations or a distinct callback domain so hot streams cannot
occupy every ordinary handler slot.

`item_drained` alone releases the item/byte token, installs the next cursor,
increments the generation, and arms the typed wake. It is infallible,
nonblocking, and never calls Roc. Timer-only behavior is sufficient for this
slice; `Immediate` yields through the scheduler, and `Pulse` remains deferred.

Cancellation of parked/draining state drops host owners immediately.
Cancellation during a callback marks the operation and returns; completion
then whole-drops its result and releases callback/request accounting. Repeated
cancel/drop and stale timer wakeups are idempotent.

## Source/body poll correction

The current `SseItemSource::poll_item` uses ordinary `Poll::Pending`, which
cannot distinguish:

- a parked timer, where the body's pre-reserved output frame should be returned;
  from
- an advancing callback, where the reservation must remain held so completion
  cannot advance application state without bounded output capacity.

The adapter needs a small private poll vocabulary such as
`Parked | Advancing | Item | End | Error`. `SseBody` returns the reservation on
`Parked`, retains it on `Advancing`, and does not poll the source again until
completion wakes it. Source cancellation must be required rather than a
default no-op.

## First real-listener slice

Use identity coding and a fixed-size cursor through the actual bound HTTP/1.1
listener. The research application produces:

1. initial event A;
2. a visible timer wait;
3. event B only after that timer;
4. a `Wait` transition with no item;
5. a large event spanning many tiny body frames; and
6. `End`.

A raw client must prove that headers/A arrive before the timer, no B bytes
arrive early, later events remain ordered, no next callback runs before
`item_drained`, and clean EOF balances every cursor, item, callback, frame,
request, timer, and resource owner.

Focused tests cover maximum+1 initial and next cursors, length overflow before
allocation, `Emit`/`Wait`/`End`/error, oversize item, stale wake, repeated
cancel, cancellation while parked/admitting/advancing/draining, completion
after body drop, and 10,000 maximum-class idle cursors reaching exactly the
configured high-water before the next precommit rejection.

The first slice may make one explicit bounded copy from the Roc event list into
host `Bytes` after holding the maximum-item token. Report it as temporary. A
later performance slice can transfer the Roc item as a transport-owned `Buf`
without complicating the scheduler proof.

## Brotli CPU follow-up

Do not add Brotli to the timer slice. The current body executes PROCESS, FLUSH,
and FINISH synchronously inside `Body::poll_frame`. A frame bound is not a CPU
bound: one call can consume substantial input, and the body loop can traverse
multiple zero-output phases without yielding. Selected q1/LGWin11 measurements
reach about 210 us median and 252 us p99 for a 64 KiB event; a rejected profile
showed roughly 3 ms stalls. Enough hot streams can occupy every Tokio worker.

The preferred follow-up is a fixed preallocated compression executor:

- start `K` named compression threads;
- preallocate `M` lanes and a bounded queue of lane IDs, with `M` equal to
  compressed-stream admission;
- one stream owns one reusable lane containing encoder, item/offset,
  cancellation, waker, and one operation/result cell;
- after reserving one output frame, `poll_frame` submits one lane operation and
  returns `Pending`;
- PROCESS consumes at most a configured input quantum; FLUSH and FINISH use one
  reserved frame; and
- the next poll commits output or submits the next operation, never continuing
  an unbounded encoder loop inline.

Queued cancellation skips work. Running cancellation returns promptly from the
body; the worker destroys the encoder without FINISH and releases the lane when
the finite operation returns. Compression uses separate CPU admission and never
retains a Roc callback permit while output drains.

Per-frame `spawn_blocking` is only a comparison: it allocates task state,
competes with the blocking pool capped for Roc handlers, and cannot preserve
the zero-steady-allocation target. A worker per stream becomes one thread per
connection.

The fixed-executor gate covers blocked-operation isolation, thread affinity,
queued/running/completed cancellation, one job per lane, exact queue/lane/frame
high-water, 10,000 warmed zero-allocation items, input-quantum timing, decoded
FLUSH/FINISH output, and mixed hot Brotli/ordinary/H2 load. Fix the p99 gate
before measuring; the current candidate is no worse than
`max(identity * 1.10, identity + 1 ms)` for ordinary requests with no starvation.

Only the measured named `Scale` q1/LGWin11 and `Full` q3/LGWin12 profiles enter
this executor. Raw quality/window parameters would silently admit untested CPU
and memory costs.

## Alternative required for arbitrary typed unfold

If arbitrary typed `Sse.unfold!` state is non-negotiable, keep it blocked on a
compiler/runtime feature: allocation-domain IDs for Roc allocations,
pre-reserved per-stream domains, generated alias-aware retained-graph visitation,
explicit seamless-backing treatment, Context-root exemptions, and a policy for
whether each opaque handle can be retained and at what weight. Validate every
returned machine before parking it.

Even that feature would bound retained state only. Transient callback allocation
would remain under the existing trusted-application computation model. A
host-only post-hoc counter or application estimate is not an acceptable
substitute.

## Non-claims

Passing the cursor slice would not yet establish Brotli CPU isolation, HTTP/2
fairness, public API ergonomics, `Pulse`, cross-target behavior, or the
deliberate `design.md` scope change. It would establish the bounded dynamic
state and production scheduler/body seam needed to investigate those questions.
