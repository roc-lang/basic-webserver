# Host-owned retained-source Datastar feasibility slice

Status: preferred product hypothesis after reconciling retained-state review
with the platform trust boundary

Date: 2026-08-03

This is implementation-specific research guidance, not an accepted platform
contract. It does not change [`design.md`](../../design.md) or select final
public names. Dynamic Roc-produced SSE remains a deliberate experiment against
an explicit current non-goal.

## Why the state model changed again

The retained-callable work proves that Roc can safely and efficiently retain,
advance, move, and destroy an arbitrary captured source machine. The subsequent
resource review correctly observed that a stream slot does not byte-bound every
transitive string, list, box, seamless backing, or opaque resource reachable
through that machine. The allocator has no per-stream domain and the erased
callable ABI has no alias-aware graph visitor.

That observation does not by itself require a byte cursor. `basic-webserver`
does not promise to contain arbitrary allocation by trusted application code.
It bounds hostile input, concurrent execution, and every resource introduced
by the platform. This is comparable to Go: a server can bound goroutines,
queues, buffers, compressors, and native resources without imposing a
transitive heap quota on each closure.

The bounded-cursor proposal applied a stronger isolation boundary than
[`design.md`](../../design.md) currently claims and imposed a real encoding and
dispatch cost on every dynamic source. The preferred hypothesis is therefore
again a typed retained source, but stored under one host-owned, fixed-capacity,
generation-checked stream heap. Arbitrary captured Roc heap is explicitly
trusted application memory; it is not described as admitted or byte-bounded.

## Candidate application shape

Keep the existing application contract:

```roc
program = { init!, respond!, shutdown! }
```

Conceptually, a handler can return a retained typed source:

```roc
respond! = |request, context| {
    user = authorize!(request, context)?

    Ok(
        Datastar.stream(
            Sse.unfold!(
                { user_id: user.id, version: 0 },
                |state, wake, context| {
                    changes = load_changes_after!(
                        context.db,
                        state.user_id,
                        state.version,
                    )?

                    Sse.emit({
                        events: render_changes(changes),
                        state: {
                            user_id: state.user_id,
                            version: changes.version,
                        },
                        wake: Sse.after(500),
                    })
                },
            ),
        ),
    )
}
```

The host keeps the application-specific `Context` as one opaque `Box(Context)`
owner. A generated source-construction wrapper receives an incremented owner,
unboxes it in Roc, and lets the private source retain the immutable context or
the fields its transition actually uses. The server root may then be dropped
before either source without invalidating them. This gives each finite
transition ordinary typed `Context` ergonomics without reconstructing context,
adding a source-ID dispatcher, or exposing its layout to Rust.

`Sse.unfold!` is the ergonomic constructor, not a callback registry. It turns a
typed state transition into one recursively typed private source. Application
code returns typed events and waits, never a response writer, compressor,
socket, task, or arbitrary byte stream.

Finite Datastar actions remain ordinary complete responses and consume no
stream slot. Declarative finite progressive sequences may use the same native
body without requiring applications to write a state machine.

## Host-owned stream heap

Before committing the initial response, the host reserves one stable slot from
a finite heap. Conceptually:

```text
StreamSlot {
    generation,
    phase,
    one OwnedRocSource or one in-flight completion,
    wake generation and timer,
    body/frame and byte reservations,
    optional Brotli lane,
    cancellation and shutdown accounting,
}
```

The source returned through `Server.Outcome` is consumed into the slot. The
host owns exactly one reference; it is not copied into a second registry or
left owned by the returned outcome shell. Generated consuming projections move
the value into a non-`Copy` Rust owner.

Advancement is one affine transaction:

```text
Precommit { source, reservations }
Parked    { source, wake generation }
Advancing { non-cancellable completion owner }
Draining  { next source, wake, item, byte token }
Ended
Closed
```

Only `Parked` may consume its source and enter `Advancing`. A successful
`Emit` or `Wait` moves the returned next source into `Draining`; it cannot be
advanced until `item_drained` releases the current item and installs the next
wake generation. `End` releases the slot. A stale slot generation or wake
generation cannot act on a reused source.

Cancellation of `Parked` or `Draining` drops every host and Roc owner
immediately. Cancellation during `Advancing` marks the slot and returns; the
synchronous Roc call remains accounted and its completion whole-drops the
returned result instead of parking or publishing it. Dropping a join handle
must not release callback admission or active-request accounting before the
call actually returns.

## What is and is not bounded

Admission reserves finite capacity for:

- global and per-connection stream slots;
- active callbacks and queued ready work;
- timers or other typed wake registrations;
- maximum uncompressed event batches and transport frames;
- encoded-byte high-water and backpressure state;
- Brotli lane and scratch storage when selected; and
- active request, shutdown, and lifecycle accounting.

Opaque SQLite, TCP, file, and readiness resources remain bounded by their
existing type-specific host heaps. Host-originated request and effect bytes
retain their configured input bounds even if ARC extends their lifetime.

The platform does not claim a per-stream byte bound for arbitrary Roc values
created and captured by trusted application code. A program can retain a large
list in a source just as it can deliberately allocate one in `respond!`. The
API should make the efficient pattern natural by supplying `Context` to every
transition and showing IDs, versions, and `Last-Event-ID` as state, while
documentation and allocation instrumentation make accidental retention
observable.

If hard application-heap isolation becomes a product requirement, the host
box is not sufficient. That would require allocation domains, cross-domain
ownership rules, safe quota exhaustion, and likely compiler-generated graph or
region support. It is a separate Roc runtime project, not a prerequisite for a
Go-comparable trusted-application API.

## Current disposable proof

The generated-Rust ABI fixture now includes the reduced outcome:

```text
SourceOutcome = Response(status) | Stream(owned SourceMachine)
```

and a two-slot host stream heap. Against Roc candidates `d4921d8658` and
`be78e95c42`, the fixture proves:

- ordinary outcomes whole-drop and stream outcomes consuming-move their source;
- outcome projection performs no allocation, deallocation, or payload copy;
- capacity two admits exactly two sources and preserves the rejected owner;
- slot generations reject handles after cancellation and reuse;
- wake generations reject duplicate and stale advances;
- only one advance owns the machine at a time;
- drain acknowledgement is the only transition back to `Parked`;
- normal `Emit`/`End`, parked cancellation, draining cancellation, and
  cancellation during an advance return all Roc allocations and opaque
  resources to zero; and
- two sources can retain fields from one host-owned `Box(Context)`, outlive the
  host's root owner, and independently advance or cancel to zero live
  allocations; and
- optimized unique transitions can reuse the same callable allocation.

This is still a disposable ownership model, not the production scheduler. Its
purpose is to falsify the claim that a fixed `advance_sse!` entrypoint is
required merely to give the host stable ownership and bounded stream capacity.

## Source/body poll correction

The current `SseItemSource::poll_item` uses ordinary `Poll::Pending`, which
cannot distinguish:

- a parked timer, where the body's pre-reserved output frame should be returned;
  from
- an advancing callback, where the reservation must remain held so completion
  cannot advance application state without bounded output capacity.

The adapter needs a private vocabulary such as
`Parked | Advancing | Item | End | Error`. `SseBody` returns the reservation on
`Parked`, retains it on `Advancing`, and does not poll again until completion
wakes it. Source cancellation is required rather than a default no-op.

## First real-listener slice (passed)

Compose the retained outcome and stream heap through the actual bound HTTP/1.1
listener using identity coding first. The research application produces:

1. initial event A before commitment;
2. a visible timer wait;
3. event B only after that timer;
4. a `Wait` transition with no item;
5. a large event spanning many tiny body frames; and
6. `End`.

A raw client must prove that headers/A arrive before the timer, no B bytes
arrive early, events remain ordered, no source advances before
`item_drained`, and clean EOF balances every source, item, callback, frame,
request, timer, and resource owner.

Focused tests cover slot saturation before commitment, `Emit`/`Wait`/`End` and
application error, oversize event batches, stale wakes, repeated cancellation,
cancellation while parked/admitting/advancing/draining, completion after body
drop, and configured maximum idle streams reaching exactly the expected
high-water before the next rejection.

The implemented slice transfers the Roc event list directly into a
`Bytes::from_owner` value, then copies from that owner into the already selected
fixed host frames. Results, including the reservation handoff bug found by the
live listener, are recorded in
[`datastar-listener-findings.md`](datastar-listener-findings.md).

## Brotli CPU follow-up

Do not add Brotli to the first timer slice. The current body executes PROCESS,
FLUSH, and FINISH synchronously inside `Body::poll_frame`; bounded memory alone
does not bound CPU time on an async transport worker.

The preferred follow-up remains a fixed preallocated compression executor:

- start `K` named compression threads;
- preallocate `M` lanes and a bounded queue of lane IDs, with `M` equal to
  compressed-stream admission;
- let one stream own one reusable lane containing encoder, item/offset,
  cancellation, waker, and one operation/result cell;
- submit at most one finite PROCESS/FLUSH/FINISH operation at a time; and
- never retain a Roc callback permit while compressed output drains.

Queued cancellation skips work. Running cancellation returns promptly from the
body; the worker destroys the encoder without FINISH and releases the lane when
the finite operation returns. Only measured named compression profiles enter
this executor.

## Bounded-cursor fallback

A host-owned byte cursor remains a valid opt-in stricter state model when an
application wants serializable continuation state, durable replay, or an
auditable per-stream state-size limit. It is no longer the default mechanism
or a reason to add `advance_sse!` to every application's platform record.

The retained-source hypothesis is falsified if the real boundary cannot move
one outcome-owned source into a slot without leaks/copies, cannot compose the
proven `Box(Context)` ownership with `respond!`, cannot preserve scheduler
bounds under cancellation, or materially loses to the bounded cursor in
realistic Roc-versus-Go examples.

## Non-claims

Passing this slice would not yet establish Brotli CPU isolation, HTTP/2
fairness, browser/proxy coverage, `Pulse`, cross-target behavior, public API
names, or acceptance of the deliberate `design.md` scope change. It would
establish the retained source and production scheduler/body seam needed to
investigate those questions.
