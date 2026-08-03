# Retained Roc SSE through the production listener

Status: identity-coded listener feasibility passed; API names and resource
configuration remain experimental

Date: 2026-08-03

This is implementation research, not an accepted change to
[`design.md`](../../design.md). It deliberately tests a narrow exception to the
current non-goal for Roc-produced incremental responses.

## Result

An application can now return `Server.stream(Sse.unfold!(state, transition!))`
through the ordinary `respond!` contract. The platform converts the typed
state transition into one private retained Roc source. Rust consumes that
source from a tagged `Ordinary | File | Stream` host outcome and owns it until
the stream advances, ends, errors, is rejected, or is cancelled.

The production HTTP/1.1 listener passes a finite source that emits A, waits on
a host timer, emits B, performs a timer-only `Wait`, emits a 20,014-byte framed
event through multiple 16 KiB host frames, emits a final event, and ends. The
wire response has canonical `text/event-stream` and `no-cache` headers, ordered
bytes, and clean EOF. All 53 cross-platform specification cases pass on the
native x64musl runner, including this new case; all 181 Rust host tests and 215
Roc platform tests also pass.

## Ownership boundary

`InternalServer.OutcomeToHost` is now a tagged union instead of a flat record
with dummy ordinary and file fields. Generated consuming projections move the
selected payload into a non-`Copy` Rust owner:

- `Ordinary` moves the complete response record into the existing zero-copy
  response owner;
- `File` moves only the native file plan; and
- `Stream` moves exactly one erased callable into `OwnedSseSource`.

Every source advance consumes that callable and returns `Emit`, `Wait`, `End`,
or `Error`. `Emit` consuming-moves the Roc list and next source. The list is
transferred directly into `Bytes::from_owner`; there is no event-byte copy at
the Roc/Rust boundary. `item_drained` is the only operation that installs the
next source and its wake timer.

Dropping a parked source recursively releases its captured state. Dropping an
admission future before dispatch releases its source. Dropping an in-flight
join handle does not cancel the blocking Roc invocation or release its active
permit; the detached task whole-drops the returned step when it completes.

## Scheduling and bounds

The stream holds one permit from a fixed-capacity stream semaphore for its
complete lifetime. For this slice its capacity equals `max_handlers`; a final
API needs a separate named configuration and metrics surface.

Each finite Roc transition separately enters the existing bounded handler
admission domain and runs in Tokio's bounded blocking pool. The active permit
is released as soon as the transition returns, so a parked or backpressured
stream does not occupy a Roc execution slot. Queue admission, timeout, and
running callback ownership retain their existing non-cancellable semantics.

Each body owns one preallocated 16 KiB output frame and admits at most one
1 MiB canonically framed event. These constants are research defaults, not a
selected public contract. The body distinguishes:

- `Parked`: no callback can publish state, so return the frame reservation;
- `Advancing`: a callback owns the source, so retain the reservation;
- `Item`: move bytes into the body and drain them before installing the next
  source;
- `End`; and
- `Error`.

The live test initially found a deadlock in this distinction: after
`Advancing` retained the only reservation, the next `PollSource` attempted to
reserve a second frame. `PollSource` now consumes its held reservation first,
and a focused one-slot regression proves the completed callback can publish
without a second reservation.

## What this does not yet prove

- The first transition is not executed before response commitment, so an
  immediate application error currently becomes a body error after 200 headers.
- Stream slots, item bytes, frame bytes, callback saturation, and error policy
  are not yet application-configurable or fully observable.
- Cancellation and saturation need end-to-end Roc allocation/resource ledgers,
  not only the lower-level retained-source fixture and Rust body tests.
- The public event type currently exposes only normalized `data` events.
  IDs, event names, retry, comments/heartbeats, and first-class Datastar events
  need typed constructors and validation.
- SSE content coding remains identity-only on this application path. The
  existing inline Brotli body is intentionally not enabled because PROCESS,
  FLUSH, and FINISH still run on an async transport worker.

The next research slice is the bounded Brotli executor described in
[`datastar-next-slice.md`](datastar-next-slice.md): fixed worker threads, finite
lane admission, one finite operation per job, prompt body cancellation, and
normal FINISH only on source EOF.
