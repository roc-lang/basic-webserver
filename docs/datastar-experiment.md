# First-class SSE and Datastar experiment

- Status: design hypothesis for feasibility work
- Branch: `datastar-experiment`
- Started: 2026-08-01
- Baseline: `origin/main` at `2032390` (2026-08-01 fetch)

## Purpose

This document records a proposed product boundary, application experience, host
architecture, and research plan for making Server-Sent Events (SSE) and
Datastar first-class in `basic-webserver`.

It is intentionally not part of [`design.md`](../design.md). The current design
contract explicitly says that Roc-produced incremental response streams and
application-defined SSE runtimes are non-goals. This experiment investigates a
deliberate change to that boundary. The accepted design should change only
after the hypotheses here have been tested and the scope change has been
accepted on its merits.

This document separates four kinds of statements:

- **Candidate contract**: behaviour we currently think the finished platform
  should promise.
- **Hypothesis**: an architectural claim that needs experimental evidence.
- **Open question**: a decision for which evidence or product input is still
  missing.
- **Gate**: a condition that must pass before the experiment advances.

The illustrative Roc APIs are not expected to type-check yet. They exist to
make ownership, lifecycle, and ergonomics concrete enough to test.

## Executive hypothesis

We believe `basic-webserver` can provide a first-class Datastar experience and
production-grade persistent SSE without turning Roc into a general async
runtime, pinning one operating-system thread per connection, or introducing a
process-local application message bus.

The proposed architecture has three paths:

1. Finite Datastar actions remain complete, bounded ordinary responses.
2. Progressive and persistent SSE use a host-scheduled, pull-based
   `Sse.Stream` machine.
3. An optional payload-free, coalescing `Pulse` can wake parked stream machines,
   but SQLite or an external service remains the source of truth.

All SSE paths participate in host-owned, automatic Brotli negotiation. Finite
responses can use bounded complete-response encoding and retain the ordinary
minimum-usefulness threshold. Progressive and persistent responses must choose
their coding at commitment; when Brotli is selected they retain an encoder as
part of the backpressured body and flush it after every logical event and
heartbeat. Identity remains the fallback when negotiation does not select
Brotli or transformation is explicitly prohibited.

The stream machine is an opaque boxed Roc value containing its private state
and continuation. The host owns it between steps and invokes one finite step at
a time through a fixed platform ABI. A step emits a bounded event batch, ends,
or returns a new machine plus a declarative wake condition. No Roc stack or
native worker remains occupied while the stream is waiting.

The primary feasibility risk is whether the new Zig-based Roc compiler can
safely retain, invoke, transfer, and destroy boxed captured callables across
provided entrypoints and host worker threads on every supported target. That
claim must be proven before the public API is selected.

## Baseline implementation

This branch is based directly on `origin/main` at `2032390`, not on the earlier
response-compression development branch from which the discussion began.

That baseline already has several facilities the experiment should extend
rather than duplicate:

- [`src/response.rs`](../src/response.rs) is the protocol-independent final
  authority for response validation and framing. It accepts native response
  bodies with unknown length while rejecting application control over
  connection-specific fields, trailers, and invalid `Content-Length`.
- [`src/server_transport.rs`](../src/server_transport.rs) owns protocol
  detection and HTTP/1.1 progress deadlines. SSE slow-reader and heartbeat
  semantics must compose with those deadlines rather than install a second
  socket timeout system.
- [`src/http_server.rs`](../src/http_server.rs) has explicit request limits,
  bounded handler admission, request/response telemetry, HTTP/1.1 and HTTP/2
  connection paths, and graceful-drain accounting.
- [`src/file_server.rs`](../src/file_server.rs) demonstrates a native response
  plan whose bytes remain in a bounded host-owned streaming path.
- [`src/compression.rs`](../src/compression.rs) already centralizes
  `Accept-Encoding` negotiation and bounded Zstandard, Brotli, and gzip
  encoder configuration. SSE should reuse its negotiation and encoder policy
  where their semantics match, while adding a streaming-specific output and
  flush lifecycle instead of using the ordinary whole-body buffer path.
- [`src/telemetry.rs`](../src/telemetry.rs) and the newer test harness already
  provide homes for bounded operational accounting and real-listener protocol
  cases.

The SSE body should therefore be another validated host-owned response body
with an unknown encoded length, not an alternate HTTP server or framing path.
Its lifecycle and stream-specific limits will be new, but final headers and
wire-version invariants still pass through the common response authority.

## Pinned Datastar reference

Spike 0 pins the stable Datastar client `v1.0.2` at
`e24f04d43ca4445d662b4a035e5bfe9ed68de57c` and the official Go SDK `v1.2.2`
at `60dc10ebdaad3207d71e4bd8c1f158e65bb4acb0`. The byte fixtures, executable
Go observations, preliminary microbenchmarks, and detailed contract matrix are
in [`research/datastar-parity`](../research/datastar-parity/README.md).

The stable client is the compatibility authority. Moving documentation and
client `main` already differ from the release in request cancellation, retry
option names, visibility reopen, and DELETE signal placement, so a future pin
upgrade must regenerate fixtures and rerun browser tests rather than silently
following live prose.

Important established constraints are:

- Datastar uses a custom Fetch stream, not the browser `EventSource` API.
- Stable GET and DELETE actions send JSON signals in the `datastar` query
  parameter; POST, PUT, and PATCH send a JSON body. Form mode sends form data,
  not signals.
- The client also accepts finite `text/html`, `application/json`, and
  `text/javascript` responses. One element or signal patch need not use SSE.
- The only Datastar SSE event names are `datastar-patch-elements` and
  `datastar-patch-signals`; script execution is an element-patch convenience.
- `Last-Event-ID` is maintained only inside one action's retry/reopen loop. An
  empty `id:` clears it, and an absent ID retains it.
- Default retry mode does not reconnect after a clean status-200 EOF. A maximum
  stream lifetime cannot assume transparent reconnect.
- The stable Go SDK is an ergonomic/performance reference, not a wire
  authority: it emits an extra blank record, does not validate field injection,
  ignores `Accept-Encoding` q-values/wildcards, omits `Vary`, overwrites
  `no-transform`, and never finishes its retained Brotli encoder.

The finished Roc path should match the pinned client's logical and canonical
wire contract while deliberately improving on those Go SDK limitations.

## Proposed product boundary

### Candidate contract

`basic-webserver` supports bounded, unidirectional, request-authorized SSE
sessions whose transport, scheduling, heartbeats, backpressure, cancellation,
content coding, and lifecycle are owned by the host. Roc owns authentication,
application policy, durable queries and mutations, rendering, typed event
construction, and replay policy.

An SSE session may cause several finite, synchronous Roc invocations over the
lifetime of one HTTP response. At most one invocation for a session runs at a
time. Between invocations, its Roc state is parked as an owned opaque value and
consumes no Roc execution worker.

### Intended uses

- Finite Datastar backend actions returning one or more patches.
- Progressive feedback where the browser observes an early result before later
  work finishes.
- Live SQLite-backed views that re-query durable state after a timer or wake
  hint.
- Durable event feeds resumed from an application-owned event ID.
- Small self-contained applications with hundreds or thousands of mostly idle
  live views behind a correctly configured reverse proxy.

### Continuing non-goals

- A generic async Roc runtime, futures, arbitrary background tasks, or detached
  callbacks.
- A generic response writer or arbitrary application-generated byte stream.
- WebSockets, bidirectional messaging, upgraded protocols, or HTTP/2 server
  push.
- A payload-bearing in-process pub/sub system, dynamic topic registry, actor
  system, or message bus.
- Process-local application facts or delivery guarantees.
- Reliable or exactly-once SSE delivery supplied by the host.
- An efficient general-purpose broadcast hub for high-frequency fan-out.
- Retaining request-body handles, borrowed request views, or invocation-local
  ABI state after the initial request handler returns.
- Making client disconnect an application transaction or dependable cleanup
  callback.

## What “comparable to Go” means

There are two different comparisons that must not be conflated.

### Datastar SDK parity

The platform should make all of the following straightforward:

- Read and decode Datastar signals according to the pinned client protocol.
- Return zero, one, or several Datastar events in a finite response.
- Commit an event stream before its producer is finished.
- Flush each logical event without waiting for a later event or stream close.
- Run progressive and persistent streams.
- Detect disconnect and stop future production.
- Bound slow clients and apply backpressure.
- Emit event IDs and retry fields.
- Resume from an application-owned durable cursor.
- Send transport heartbeats without waking Roc.
- Negotiate and stream Brotli automatically, without a compression writer or
  per-event compression decisions in application code.
- Work identically over HTTP/1.1 and HTTP/2.
- Behave predictably through a documented reverse-proxy configuration.

### Go language/runtime parity

Go applications also have cheap goroutines, cancellable blocking operations,
channels, `select`, and an ecosystem of in-process hubs. The current Roc
compiler does not provide suspendable stacks or tasks.

This experiment does not attempt source-level parity with a Go loop such as:

```go
for {
    select {
    case value := <-updates:
        sse.PatchElements(render(value))
    case <-request.Context().Done():
        return
    }
}
```

Instead, the goal is comparable capability, safety, and idle-stream scale
through an idiomatic functional stream machine. Claiming that an imperative
Roc writer is Go-comparable would be misleading if every stream pinned a native
thread.

## Why a synchronous writer is not the foundation

The current request handler is one synchronous native Roc invocation running
on the bounded blocking execution domain. The host waits for that invocation
before it returns the Hyper response.

A superficially ergonomic API such as:

```roc
stream = request.start_sse!()?
stream.send!(first_event)?
Sleep.millis!(1000)?
stream.send!(second_event)?
```

would have these consequences:

- One blocking worker and native thread remain occupied per live stream.
- An idle disconnect cannot wake `Sleep!` or arbitrary Roc computation.
- Enough streams consume every ordinary handler slot.
- Graceful shutdown can reach the hard process deadline while handlers sleep.
- A copyable writer capability makes response commitment and double-response
  semantics difficult to make structural.
- Adding a separate SSE thread pool moves the limit but does not fix the
  one-thread-per-stream architecture.

An imperative writer might eventually be considered for explicitly short,
low-cardinality operations, but it must not become a second persistent-stream
runtime with different lifecycle semantics. The experiment should first see
whether declarative sequences and stream combinators make that convenience
unnecessary.

## Proposed application architecture

### Module boundaries

`Sse` is generic platform HTTP infrastructure. It owns typed SSE events,
stream construction, wait descriptions, and response options.

`Datastar` is first-party Roc code shipped with and re-exported by the platform.
It owns the Datastar protocol vocabulary, signal decoding, patch construction,
and ergonomic response helpers. Rust does not know about Datastar selectors,
signals, patch modes, or client attributes.

This split gives applications a built-in experience while keeping the changing
Datastar protocol out of the host runtime.

### Existing program contract

The preferred design preserves:

```roc
program = { init!, respond!, shutdown! }
```

`Server.Outcome` gains one closed response-plan case containing an opaque
`Sse.Stream`. Applications that never use SSE do not model stream state or add
a hook.

The fallback design, used only if boxed callables are not viable, adds a fourth
provided application entrypoint with an application-defined `StreamState`:

```roc
program = { init!, respond!, stream!, shutdown! }

respond! : Request, Context
    => Try(Server.Outcome(StreamState), [ServerErr(Str), ..])

stream! : Sse.Wake, StreamState, Context
    => Try(Sse.Step(StreamState), [ServerErr(Str), ..])
```

That fallback is less ergonomic because all stream routes share one application
state type, packages cannot privately encapsulate their stream state, and every
application contract changes. It is still preferable to a pinned writer.

## Illustrative Roc API

### Generic event model

Conceptually:

```roc
Sse.Event

Sse.event : {
    name : Str,
    data : List(Str),
    id : [Absent, Set(Str), Clear],
    retry_millis : [Absent, Set(U64)],
} -> Try(Sse.Event, [InvalidEventName, InvalidEventId, InvalidRetry])
```

The exact surface can use builders and defaults. Important properties are:

- `name` and `id` cannot inject new fields or records through CR, LF, or NUL.
- Multiline data is split into separate `data:` lines.
- An event always ends with a blank line.
- Setting and clearing an event ID are distinct operations.
- Raw preframed bytes are not the primary public API.
- Any escape hatch is explicit about bypassing typed protocol construction.

### Finite Datastar response

Most backend actions should not enter the persistent stream engine:

```roc
respond! = |request, context| {
    signals = Datastar.read_signals!(request, Signals)?
    todo = create_todo!(context.db, signals.newTodo)?

    Ok(
        Datastar.respond([
            Datastar.patch_elements({
                elements: render_todo(todo),
                selector: "#todos",
                mode: Append,
                namespace: Html,
                use_view_transition: False,
            }),
            Datastar.patch_signals({
                signals: { newTodo: "", saving: False },
                only_if_missing: False,
            }),
        ]),
    )
}
```

`Datastar.respond` produces a complete bounded response with canonical headers.
It does not consume an open-stream slot or stream-callback capacity.

### Declarative progressive sequence

Known sequences should not require an application state machine:

```roc
Ok(
    Datastar.stream(
        Sse.steps([
            Sse.emit(
                Datastar.patch_elements({
                    elements: loading_view,
                    selector: "#result",
                    mode: Replace,
                }),
            ),
            Sse.after_millis(3000),
            Sse.emit(
                Datastar.patch_elements({
                    elements: complete_view,
                    selector: "#result",
                    mode: Replace,
                }),
            ),
            Sse.close,
        ]),
    ),
)
```

The first event must be observable by the client before the three-second wait
finishes. The host owns the timer; no Roc invocation is active during the wait.

### Dynamic stream

An effectful functional unfold is the advanced primitive:

```roc
stream =
    Sse.unfold!(initial_state, |wake, state| {
        snapshot = load_if_newer!(context.db, state.version)?

        match snapshot {
            NoChange =>
                Ok(
                    Sse.wait_on_pulse_or_after({
                        pulse: context.todos_changed,
                        observed: state.pulse_generation,
                        timeout_millis: 15_000,
                        state,
                    }),
                )

            Changed({ version, todos }) =>
                Ok(
                    Sse.emit_then_wait({
                        events: [
                            Datastar.patch_elements({
                                elements: render_todos(todos),
                                selector: "#todos",
                                mode: Replace,
                            }),
                        ],
                        state: { ...state, version },
                        wait: Sse.on_pulse_or_after({
                            pulse: context.todos_changed,
                            observed: state.pulse_generation,
                            timeout_millis: 15_000,
                        }),
                    }),
                )
        }
    })

Ok(Datastar.stream(stream))
```

The callback may run finite request-scoped effects. It must return a wait
description rather than using `Sleep!`, waiting on a TCP stream, or otherwise
occupying the stream callback execution domain while idle.

### Candidate step vocabulary

The public API should make these outcomes easy to express while keeping the
host ABI smaller and closed:

- End successfully.
- Abort with an operational log detail.
- Emit a bounded list of events and end.
- Emit events and continue immediately.
- Emit events and continue after a duration.
- Wait until a duration without emitting.
- Wait for `Pulse` generation change or a fallback duration.

Immediate continuation needs a per-stream burst budget. A machine must not be
able to hot-loop indefinitely without yielding to the scheduler.

## Datastar API hypotheses

The first-party module should at least provide:

- `Datastar.is_request` or equivalent access to `Datastar-Request`.
- `Datastar.read_signals!` with typed decoding and request-body limits,
  reading stable GET/DELETE query signals and POST/PUT/PATCH JSON bodies.
- Ordinary finite HTML element-patch and JSON signal-patch responses.
- `Datastar.respond` for finite actions.
- `Datastar.stream` for persistent responses.
- `Datastar.patch_elements`.
- `Datastar.patch_signals`.
- All eight closed patch modes and all three namespace choices.
- Selector, view-transition, view-transition-selector, and `onlyIfMissing`
  options.
- JSON null signal removal.
- Event ID and retry integration inherited from `Sse.Event`.
- Clearly named unsafe HTML/script escape hatches where unavoidable.

The module must be tested against the actual pinned Datastar client and
official SDK fixtures for every supported request method. Documentation prose
is not a sufficient executable protocol contract, especially where query/body
behaviour or retry rules have changed across releases.

Authentication and authorization occur before selecting the SSE outcome.
`Datastar-Request` and client signals are untrusted input, not authentication or
server state.

Form action mode contains ordinary form fields rather than Datastar signals and
uses the platform's bounded form parsing. A one-patch response should use the
ordinary response path; multi-event finite SSE remains a complete bounded
response and does not consume a persistent stream slot.

## Stream-machine runtime model

### Candidate host state

Each open stream owns one bounded host record containing approximately:

- A generation-checked stream slot.
- An explicit lifecycle state.
- One current boxed Roc machine or one in-flight advance.
- A response-body sender and cancellation signal.
- At most a small fixed number of framed or content-coded output chunks.
- One host-owned streaming Brotli encoder with a fixed window and bounded
  pending-output storage when `br` was negotiated.
- A timer or `Pulse` waiter registration.
- A heartbeat deadline.
- A slow-reader and maximum-lifetime deadline.
- Per-stream counters and an active-request accounting guard.

The lifecycle is conceptually:

```text
Uncommitted
    |
    +-- admission/initial failure --> OrdinaryResponse
    |
    `-- commit --> Waiting <--> Ready --> Advancing --> Backpressured
                    |          |          |                 |
                    `----------+----------+-----------------+
                                           |
                                      Closing --> Closed
```

All transitions must be host-enforced. Application convention is not an
acceptable defense against double advance, use-after-drop, or post-close
output.

### Stream advance

One advance:

1. Acquires stream-callback execution capacity before entering the host
   blocking pool.
2. Transfers or retains exactly one owned machine reference for the call.
3. Invokes the fixed Roc wrapper synchronously.
4. Receives one closed step result and, where applicable, one next machine.
5. Validates event counts, byte limits, wait bounds, and state consistency.
6. Makes returned event storage independently live until Hyper releases it.
7. Releases the previous machine exactly once.
8. Enqueues output into the bounded transport path.
9. Registers the next wait only when legal under backpressure and lifecycle
   state.

No stream has overlapping advances. Different streams may advance concurrently
within the configured limit.

### Initial advance and commitment

**Open question:** Should the first stream step run before headers are committed,
or must `respond!` return the initial events explicitly?

Running one initial step before commitment has an important advantage: its
authentication-independent query or encoding failure can still become an
ordinary 500 rather than a silently closed event stream. It also delays header
commit until callback admission and output limits are known.

Returning initial events in the SSE outcome makes commitment and ownership more
obvious and avoids a second callback before the response begins.

The spike should prototype both and compare API complexity, time-to-first-byte,
error semantics, and ABI shape. Regardless of choice, all authorization and
input validation must be complete before commitment.

## Boxed callable ABI hypothesis

### Preferred representation

`Sse.Stream` privately owns an erased callable or equivalent boxed machine. The
host treats it as an opaque pointer and interacts through fixed platform
provided functions, conceptually:

```text
roc_sse_advance_for_host(owned_machine, wake_reason) -> StepToHost
roc_sse_drop_for_host(owned_machine) -> {}
```

The drop wrapper is important. Rust must not reproduce application-specialized
recursive decref logic for captured Roc values. The wrapper consumes and
releases the machine in Roc-generated code.

### Ownership protocol candidate

- Returning an SSE outcome transfers one owned machine to the host.
- A parked stream owns exactly one machine.
- An advance consumes or temporarily retains that machine according to one
  documented ABI convention.
- A successful continuing step transfers exactly one new machine to the host.
- The old and new machine may not alias unless the ABI explicitly retains the
  shared value.
- A disconnected stream discards any result returned by an already-running
  advance and drops all returned Roc values.
- Event storage remains owned until the body no longer references it.
- Shutdown does not release application context or subsystem heaps while an
  advance can still execute.

### ABI hypothesis

The generated Rust glue already contains machinery for erased callable
allocation, invocation metadata, capture destruction, and atomic box
refcounting. We hypothesize that the new compiler can support the complete
cross-entrypoint lifecycle required here.

That mechanism existing in generated code is evidence that the spike is
worthwhile; it is not proof of:

- safe escape from `respond!`;
- repeated invocation after the original Roc stack is gone;
- recursive return of the next boxed callable;
- invocation from a different host worker thread;
- concurrent invocation of different captured callables;
- correct destruction of nested captured ARC values on every target;
- identical behaviour in development and optimized backends.

Failure of this gate selects the explicit `stream!` application-entrypoint
fallback. It must not select a long-running writer.

## Backpressure and output ownership

### Candidate contract

Success from a stream step means that its event batch was accepted into the
host's bounded response-body path. It does not prove that bytes reached the
peer.

The host must not keep scheduling production while the per-stream output path
is full. Slow-client isolation requires:

- a very small bounded number of pending frames per stream;
- a global bound on all buffered SSE bytes;
- Hyper HTTP/2 flow control and body polling to propagate demand;
- a finite slow-reader deadline;
- independent state and output buffers for unrelated streams;
- no global lock held while waiting for one client.

### Event storage

Two implementations should be compared:

1. Roc privately frames each typed `Sse.Event` into its own owned byte buffer;
   Rust validates structure and retains the buffer zero-copy through Hyper.
2. Roc returns structured event fields; Rust validates and encodes them into a
   bounded host buffer.

The first keeps protocol construction in the trusted platform Roc layer and
can avoid copying large HTML patches. The second makes the Rust host the final
wire-format authority but necessarily performs more assembly at the boundary.

The spike should measure copies, allocations, ABI complexity, validation
coverage, and the ability to flush one logical event at a time. A raw
application-constructed byte stream is not an acceptable third option.

## Scheduling and fairness

Open streams and active Roc callbacks are different resources.

An idle stream owns a stream slot but no Roc execution permit. Ready callbacks
must use a bounded execution class that cannot starve ordinary requests.

Candidate approaches:

- A dedicated fixed stream-callback worker budget.
- One shared Roc worker pool with hard class reservations and a fair scheduler.

SSE framing and Brotli encode/flush work are part of the same admitted,
finite production operation as the stream step, or use an independently
bounded native production permit before leaving that worker. Hyper body polls
only move already-produced bounded chunks; they never run the compressor on an
asynchronous transport worker.

The implementation must not enqueue work into Tokio's hidden blocking queue
before acquiring explicit platform admission.

Required scheduler properties:

- At most one ready or running callback per stream.
- `Pulse` bursts coalesce rather than queue repeated callbacks.
- Timers and notifications that fire under backpressure record readiness but do
  not continue generating output.
- Ordinary requests retain configured forward progress during a stream wake
  storm.
- One HTTP/2 connection cannot consume all global stream slots.
- Immediate steps have a bounded burst and then yield.
- Shutdown can prevent new callbacks without racing an already-running one.

## HTTP semantics

### Response headers

The host should own protocol-critical headers and reject conflicts. Candidate
defaults are:

- Status `200`.
- `Content-Type: text/event-stream`.
- `Cache-Control: no-cache`.
- No `Content-Length`.
- No application-supplied transfer coding.
- No `Connection` header exposed to Roc or emitted on HTTP/2.
- `X-Accel-Buffering: no` by default, with a documented opt-out if necessary.

If an application supplies `Cache-Control: no-transform`, the host preserves
that directive and sends the stream with identity coding. It must not add
`no-transform` merely because the response is SSE, because doing so would
disable the default Brotli contract below.

Applications may still supply validated cookies, CSP, CORS, and application
metadata headers before commitment.

### Heartbeats

The host sends an idle comment such as:

```text
: keepalive

```

The candidate default interval is approximately 15 seconds and is configurable
within finite minimum and maximum bounds. Heartbeats:

- do not invoke Roc;
- do not carry application meaning;
- pass through the same backpressured body path;
- reset the relevant host/proxy idle activity;
- stop immediately when the body is closed;
- count against bounded output memory.

### Compression

#### Candidate contract

SSE negotiates Brotli by default using the platform's `Accept-Encoding` quality
and wildcard rules. If the request accepts `br`, negotiation does not prefer an
explicitly higher-quality identity representation, and transformation is not
prohibited by `Cache-Control: no-transform`, the host emits:

```text
Content-Encoding: br
Vary: Accept-Encoding
```

Otherwise it emits identity coding and still varies on `Accept-Encoding` when
the selected representation could differ for another request. Applications do
not select `Content-Encoding`, call a compressor, tune it per event, or need a
different `Datastar.stream` API. Compression is a host transport property just
as it is for ordinary and native-file responses.

This is a deliberate improvement over the pinned Go SDK, whose compression is
opt-in and whose parser treats `br;q=0` as accepted, does not match wildcard,
ignores quality ranking under server priority, and omits `Vary`. Go SDK wire
behavior must not replace the platform's existing RFC-aware negotiation as the
contract.

A finite SSE response with a known body may use the ordinary minimum-size
threshold and remain identity when compression would not be useful. A
progressive or persistent stream cannot switch coding after commitment or
buffer early events until a size threshold is crossed, so it selects Brotli at
commit whenever the negotiation above permits it.

The initial SSE capability is deliberately Brotli plus identity, rather than
promising every ordinary-response coding. Brotli is the required first-class
path. Zstandard and gzip can be admitted later only by passing the same
streaming latency, boundedness, browser, and proxy gates; their existence in
the complete-response implementation is not sufficient evidence.

#### Streaming and flush semantics

One response is one continuous Brotli stream. A fresh independently finished
Brotli stream per event is not the contract. Retaining the encoder dictionary
across repetitive Datastar HTML and signal patches is a major source of the
expected bandwidth benefit.

For each logical event or heartbeat the host:

1. frames the complete uncompressed SSE item;
2. waits for enough bounded output capacity to encode that item without
   advancing the Roc machine again;
3. writes it into the persistent Brotli encoder;
4. performs a Brotli flush that makes all input through that item decodable;
5. offers the resulting bounded encoded bytes to the Hyper body; and
6. relies on the normal transport backpressure and progress deadlines before
   producing more output.

The observable guarantee is that event one can be decoded and processed by the
browser before event two exists. `flush` cannot mean only flushing a Rust
writer into another private buffer. The gate must demonstrate delivery through
the actual encoder, Hyper, HTTP/1.1 and HTTP/2, a real browser, and the reference
reverse proxy.

Encoder input, history window, scratch memory, and pending encoded output are
all finite per-stream resources. Because a standard `Write`-based compressor
may not be safely resumable after a partial `WouldBlock`, the likely design is
to reserve a proven worst-case output budget for one bounded event plus flush
overhead before mutating the encoder. The Brotli spike must establish that
bound for the selected library and parameters rather than assume compressed
output is always smaller than input.

Stream completion finishes the encoder and sends its bounded tail before the
body closes. Disconnect drops the encoder without trying to finish output.
After headers have committed to `br`, an encoder error or impossible output
bound closes the stream and records a compression failure; it cannot fall back
mid-response to identity.

The pinned Go SDK flushes a progressively decodable prefix after every event
but never calls its compressor's required close operation, so handler return
leaves an unfinished Brotli stream. Semantic-equivalence performance tests may
record that behavior, but the platform's normal-close gate requires a valid
finished stream and correct encoder release.

#### Defaults, value, and security

The encoder should use one measured, host-owned low-latency configuration with
a fixed quality and window. Exposing Brotli quality in the Roc application API
would make CPU and retained memory part of route policy without improving the
common experience. A server-level expert setting is justified only if the
scale spike shows materially different deployment needs.

Flushing every small item has a ratio and CPU cost, so the experiment must
compare identity and Brotli over realistic finite, progressive, and persistent
Datastar traces. The required benefit is end-to-end bytes saved without
material event-latency or ordinary-request tail-latency regression, not merely
a favorable whole-buffer compression benchmark.

Dynamic compression can amplify compression-oracle attacks when secrets and
attacker-controlled values share a response. Documentation must explain that
risk and recommend `Cache-Control: no-transform` for sensitive routes whose
content creates such an oracle. This opt-out composes with the platform's
existing response-compression contract.

The existing negotiation, header, and encoder configuration should remain the
single source of truth where possible. The ordinary whole-response buffering
path is not reusable as the SSE body implementation, and the current
`ContentEncoder::flush` behavior is a hypothesis until progressive decoding is
proven by the spike.

### Reverse proxy

Hyper accepting a frame does not prove that a reverse proxy delivered it. The
release contract needs:

- documented NGINX or equivalent buffering configuration;
- read/idle timeout guidance;
- forwarded HTTP/2 expectations;
- a real proxy smoke test showing that a small first event is visible before a
  later event exists.

## Disconnect, failure, and commitment

### Candidate failure phases

Before commitment:

- authorization, validation, signal decoding, stream admission, and initial
  work may return ordinary HTTP errors;
- saturation should be an ordinary 503;
- no stream slot or machine remains live after failure.

After commitment:

- status and ordinary error bodies can no longer change;
- an `Abort` or invalid step is logged and closes the stream;
- a user-visible error must be an explicit Datastar/SSE event selected by the
  application;
- internal error details are never sent automatically.

Client disconnect:

- cancels timers and `Pulse` waits;
- prevents new advances;
- releases parked state and buffered output;
- causes any already-running result to be discarded safely;
- does not roll back effects already performed;
- does not guarantee an application callback.

### Cooperative cancellation during a step

An invocation cannot be safely preempted. A connection-status view may let
longer callbacks ask whether the stream has been cancelled, but that is a
cooperative optimization only. The design must not imply that every effect is
cancellable or that disconnection undoes it.

## Graceful shutdown

Candidate shutdown order:

1. Stop accepting new requests and SSE starts.
2. Mark every stream stopping and close its response body.
3. Cancel timers and `Pulse` waiters.
4. Prevent new stream advances.
5. Drop parked machines and output after no callback can race them.
6. Wait for already-running stream advances and ordinary handlers.
7. Invoke `shutdown!` exactly once.
8. Release context and remaining subsystem resources.

An active stream callback is a synchronous Roc invocation and remains
unpreemptable. If it prevents the configured hard drain deadline, the existing
policy of process termination is safer than releasing resources underneath it.

Idle streams must not normally cause shutdown to reach that hard deadline.

## Payload-free `Pulse`

### Candidate contract

`Pulse` is a narrowly scoped host capability used only to accelerate durable
re-query. It is safe to retain in immutable context and may be used by
concurrent handlers.

Conceptually:

```roc
observed = Pulse.observe!(context.todos_changed)
snapshot = load_todos!(context.db)?

wait = Sse.on_pulse_or_after({
    pulse: context.todos_changed,
    observed,
    timeout_millis: 15_000,
})

# After a successful SQLite commit:
Pulse.notify!(context.todos_changed)
```

The host stores only:

- a monotonically changing generation;
- a bounded set of waiting stream slots;
- bounded accounting and diagnostics.

`notify!` carries no bytes, key, topic string, ordering, or delivery count.
Several calls may coalesce into one generation change and one wake per stream.

### Lost-wakeup avoidance

The intended sequence is:

1. Observe generation `G`.
2. Query durable state.
3. Produce the current representation.
4. Register a wait for generation different from `G`.
5. The host rechecks the generation while registering.

If notification occurs anywhere after step 1, registration returns immediately
rather than sleeping through it.

### Distributed semantics

`Pulse` is local and unreliable by design. If a mutation occurs on instance A
while a stream is attached to instance B, B learns through its fallback query
or an external notification source. Sticky sessions do not make `Pulse`
durable or distributed.

Correctness must survive:

- missed notifications;
- coalesced notifications;
- process restart;
- reconnect to another instance;
- delayed stream callbacks.

Dynamic topics, payloads, delivery queues, replay, or ordering would turn
`Pulse` into the message bus this design is intended to avoid.

### Scaling limitation

One broad `Pulse` may wake thousands of streams, each of which re-queries and
renders. Admission prevents an immediate resource explosion, but not the
thundering herd or repeated computation. Applications may need several fixed,
coarsely scoped Pulses, jittered fallback queries, indexed revision checks, or
an external fan-out system for high-frequency workloads.

`Pulse` is optional acceleration, not a requirement for correctness or for the
basic SSE transport.

## Replay, IDs, retries, and durable state

SSE event IDs and Datastar retries do not provide exactly-once processing.

Candidate API behaviour:

- Expose the request's last event ID through a typed helper.
- Support event ID set and clear operations.
- Support a bounded retry-millisecond field.
- Never claim host-managed replay.
- Document that event IDs are application cursors.

Datastar's pinned Fetch client retains and clears the header inside one action's
retry or hidden-page reopen loop; a new independent action has no cursor unless
the application supplies one through another mechanism. Its default `auto`
retry mode finishes after clean status-200 EOF and retries Fetch/network
exceptions. Only `retry: always` reconnects after a clean EOF. This differs
from native `EventSource` and must be exercised explicitly.

A replayable feed stores events or monotonically revisioned facts in SQLite or
an external service. On reconnect, the handler validates the cursor and returns
events or a current representation after it.

Mutating backend actions may be retried after ambiguous network failure.
Reference examples should demonstrate idempotency keys or transactional
deduplication rather than imply that SSE makes POST effects exactly once.

## Security

- Datastar signals, selectors, IDs, and request headers are untrusted.
- `Datastar-Request` is a client hint, not authentication or CSRF protection.
- Authorization completes before the stream commits.
- Signal decoding observes bounded request-body limits and rejects malformed
  or duplicate protocol inputs deliberately.
- Event name, event ID, header, and retry validation prevents protocol/header
  injection.
- Signal values use JSON encoding by default.
- HTML rendering must escape untrusted text; unsafe raw HTML and scripts are
  explicit.
- Stream admission, lifetime, event sizes, retry behaviour, and reconnect rates
  must remain bounded under hostile clients.
- A stream must not retain usable request-body or borrowed request metadata
  beyond the initial handler.

## Resource configuration

Exact defaults are intentionally open until measurement, but the contract needs
finite controls for all of these resources:

| Resource | Candidate unit | Saturation or bound |
| --- | --- | --- |
| Open SSE streams | Stream slots | Reject before commit, normally 503 |
| SSE streams per HTTP/2 connection | Stream slots | Refuse excess without consuming global capacity |
| Active Roc stream advances | Invocations | Wait in explicit fair scheduler or reject start |
| Ready stream advances | Stream IDs | At most one per stream, globally bounded |
| Events per step | Events | Reject step and close stream |
| Framed SSE bytes per event | Uncompressed bytes | Reject step and close stream |
| Framed SSE bytes per step | Uncompressed bytes | Reject step and close stream |
| Buffered frames per stream | Frames | Backpressure production |
| Total buffered SSE output | Bytes | Backpressure and/or slow-reader close |
| Brotli output per event/flush | Content-coded bytes | Reserve proven worst-case capacity or close deliberately |
| Brotli encoder state | Bytes per encoded stream | Fixed window, scratch, and pending-output ceilings |
| Concurrent Brotli work | Encoder operations or CPU time | Bound within the SSE production domain; never consume async transport workers |
| Immediate advances | Consecutive steps | Yield or close after finite budget |
| Timer frequency | Milliseconds | Clamp/reject below finite minimum |
| Heartbeat interval | Milliseconds | Finite configured range |
| Slow-reader duration | Milliseconds | Close stream |
| Stream lifetime | Milliseconds | Optional close; do not assume default client reconnect |
| Pulse capabilities | Handles | Typed saturation during initialization |
| Pulse waiters | Waiter slots | Reject wait/close stream deliberately |

The default open-stream count need not be 10,000. A 10,000-idle-stream run is
an architecture and memory experiment on appropriately configured hardware,
not necessarily a portable default.

## Observability

The host should expose bounded-cardinality metrics or structured diagnostics
for:

- active and high-water SSE streams;
- starts, admission rejections, and close causes;
- active and high-water stream callbacks;
- ready-callback delay and scheduler fairness;
- events and application bytes emitted;
- heartbeats emitted;
- streams negotiated as Brotli versus identity;
- Brotli input/output bytes, achieved ratio, encode/flush time, and failures;
- Brotli encoder-state and pending-output high-water bytes;
- output-buffer high-water bytes;
- time spent backpressured;
- slow-reader closures;
- disconnects, callback aborts, invalid steps, and shutdown closures;
- stream lifetime distribution;
- Pulse notifications, coalescing, waiters, and wake latency;
- Roc/host payload bytes copied versus retained/transferred.

Long-lived SSE responses should not appear only as ordinary requests with
multi-hour latency. Request and stream lifecycle metrics need distinct but
reconcilable accounting.

## Alternatives considered

### Finite SSE formatting only

Useful and should still be implemented as the fast path, but it does not
provide progressive delivery or persistent live views.

### Long-running request-scoped writer

Closest to Go source syntax, but pins one native worker per stream and makes
disconnect and shutdown unresponsive. Rejected as the persistent foundation.

### Deferred callback receiving a writer

Commits at a cleaner point but still holds a native thread while the callback
loops. Rejected.

### Fourth application `stream!` entrypoint

Architecturally sound and the preferred fallback if boxed callables fail. It is
less composable and changes all application contracts, so it is not the first
choice.

### Generic host pub/sub or payload channels

Provides efficient local broadcast but introduces process-local data,
ordering, routing, restart, multi-process, and slow-subscriber semantics.
Rejected from this experiment.

### Suspendable Roc tasks or stack continuations

Could eventually provide imperative source ergonomics without pinned threads,
but requires compiler/runtime capabilities far beyond a normal platform
feature. Not a dependency of this experiment.

### External SSE service

Can provide excellent scale and durable fan-out while preserving the current
platform boundary, but does not meet the goal of built-in first-class support.
It remains the recommendation for workloads beyond the constrained facility.

### Host-native Datastar rendering or policy

Would couple the Rust host to frontend protocol evolution and move application
presentation policy out of Roc. Rejected. Only generic SSE transport belongs
in the host.

## Feasibility program

Each spike should be small enough to discard. It should record exact compiler
commit, target, build mode, commands, measurements, and artifacts. Passing a
happy-path demo is not enough; every gate includes ownership and failure cases.

### Spike 0: Pin and characterize Datastar

**Question:** What exact wire and request behaviour must the built-in module
match?

Work:

- Use the pinned Datastar client `v1.0.2` commit and Go SDK `v1.2.2` commit;
  record any later pin change as a fixture-affecting decision.
- Record its supported backend response content types.
- Extract event fixtures for patch elements and patch signals.
- Characterize signal transport for every backend action method and content
  option.
- Characterize request cancellation, hidden-page closure/reopen, retry policy,
  last-event-ID behaviour, and response EOF.
- Compare the official Go SDK's framing, headers, flush, compression, and
  errors.
- Distinguish canonical client fixtures from harmless Go SDK wire differences,
  including the SDK's extra LF record.
- Exercise clean EOF, abrupt reset, HTTP errors, 204, visibility changes,
  automatic replacement, cleanup cancellation, and explicit AbortController
  under every applicable retry mode.
- Exercise finite HTML/JSON/JavaScript responses in addition to SSE.

Pass evidence:

- A versioned protocol fixture directory independent of browser timing.
- Browser integration cases exercising the pinned client in Chromium, Firefox,
  and available WebKit/Safari coverage.
- A list of behaviours owned by Datastar versus generic SSE.
- Byte-exact canonical events terminating with one blank line, plus explicit
  `id` set/retain/clear and multiline Unicode cases.
- A request matrix covering GET, POST, PUT, PATCH, and DELETE in JSON and form
  modes, including cross-origin preflight where applicable.
- A retry/cancellation matrix that proves whether each close condition reopens
  and what `Last-Event-ID` is sent.

Stop condition:

- The protocol cannot be versioned or tested without importing a rapidly
  unstable private client contract. Reconsider whether Datastar should be a
  separately versioned first-party package rather than re-exported directly.

### Spike 1: Retained boxed Roc callable ABI

**Question:** Can a captured Roc stream machine safely escape one provided
entrypoint and be repeatedly invoked and dropped later?

Minimum prototype:

- `respond!` returns a box containing a callable that captures nested strings,
  lists, records, another callable, and at least one opaque host resource.
- Rust retains the box after `respond!` returns.
- A fixed Roc wrapper advances it several times and returns a next machine.
- Calls occur on a different worker thread from the original handler.
- Two independent machines advance concurrently; one machine never overlaps
  itself.
- Host-triggered drop occurs while parked, after validation failure, after a
  returned next machine, on disconnect, and during shutdown.

Instrumentation:

- Debug ARC ledgers and canaries.
- AddressSanitizer or available target-native memory instrumentation.
- Allocation/refcount balance and resource-heap active counts.
- Development and optimized compiler backends.

Pass criteria:

- Exact one-owner transitions are demonstrated.
- Captures remain valid and immutable across calls.
- Final recursive drop releases every captured allocation/resource exactly
  once.
- Concurrent independent machines do not race shared compiler/runtime state.
- Behaviour is equivalent on x64/arm64 Linux, x64/arm64 macOS, and Windows
  target validation as applicable to the repository's supported matrix.
- Generated glue has a reviewable stable ABI rather than depending on an
  undocumented layout accident.

Failure response:

- Prototype the explicit application `stream!` entrypoint with boxed
  application state. Do not implement the synchronous writer fallback.

### Spike 2: Minimal progressive Hyper body

**Question:** Can the host commit and flush bounded SSE frames progressively
over HTTP/1.1 and HTTP/2?

Minimum prototype:

- A synthetic host stream emits event one, waits on a host timer, and emits
  event two.
- No Roc callback loop is required yet.
- The response body uses the same `ServerBody` abstraction as ordinary and
  native-file responses.

Pass criteria:

- A client observes headers and event one before event two exists.
- There is no `Content-Length` or invalid H2 connection header.
- One slow H2 stream does not block an unrelated stream on the same connection.
- Body drop promptly cancels the timer and releases the stream record.
- A non-reading client reaches a fixed memory high-water mark.
- A proxy smoke test demonstrates non-buffered first-event delivery.

### Spike 3: End-to-end stream machine

**Question:** Does the boxed machine integrate with transport backpressure,
cancellation, and the bounded execution domain?

Minimum prototype:

- `Server.Outcome` has an experimental SSE kind.
- One machine emits, waits on a timer, advances, and closes.
- A separate stream-callback admission gate exists.
- The body owns request accounting until close.

Pass criteria:

- No worker remains occupied during the wait.
- Event production stops while the bounded body path is full.
- Disconnect while parked drops the machine without a callback.
- Disconnect during an advance safely discards and releases the returned step.
- Callback failure before commitment becomes an ordinary error according to the
  chosen initial-step design.
- Callback failure after commitment logs and closes deterministically.
- Ordinary handlers make progress during a synchronized stream wake storm.
- Shutdown closes idle streams and waits only for genuinely running callbacks.

### Spike 4: Event representation and framing

**Question:** Should final framing occur in trusted platform Roc code or Rust?

Compare:

- private Roc encoding plus host scanning and retained zero-copy buffers;
- structured ABI fields plus bounded Rust encoding.

Pass criteria:

- Byte-exact fixtures match the pinned Datastar SDK.
- Multiline Unicode and empty data are correct.
- CR/LF/NUL injection attempts fail safely.
- Each logical event can flush independently.
- Copies, allocations, retained bytes, and ABI crossings are measured.
- An HTML patch near the event-size limit has an explicit bounded memory story.

### Spike 5: Streaming Brotli

**Question:** Can one bounded Brotli stream preserve event-level latency and
produce worthwhile end-to-end savings under backpressure?

Minimum prototype:

- Reuse the platform's `Accept-Encoding` parser and response-header authority.
- Negotiate `br` automatically for SSE, with identity for unsupported clients
  and `Cache-Control: no-transform`.
- Retain one encoder across a synthetic sequence of repetitive Datastar HTML
  and signal patches.
- Flush after every event and heartbeat, and finish on normal stream close.
- Place the encoder behind the same bounded `ServerBody` and slow-reader path
  as the identity prototype.
- Instrument encoder input, output, scratch/history memory, CPU time, and each
  buffer between framing and socket transport.
- Compare both the Go SDK's idiomatic Brotli quality-6/automatic-window path
  and an exactly matched quality/window path. Measure encoder construction and
  retained idle state separately from per-event work.

Pass criteria:

- A real browser processes event one before event two is generated over both
  HTTP/1.1 and HTTP/2 with `Content-Encoding: br`.
- The reference reverse proxy preserves that progressive behavior.
- `Vary: Accept-Encoding`, `Content-Encoding: br`, the identity fallback, and
  `no-transform` opt-out are byte-for-byte correct.
- A proven bound covers one maximum-size incompressible event plus flush
  overhead; a non-reading client cannot grow encoder or body memory beyond the
  configured ceilings.
- Disconnect drops encoder state promptly, normal EOF produces a valid Brotli
  tail, and injected encoder failure closes without emitting identity bytes.
- The selected fixed quality/window has measured per-stream retained memory
  and does not starve ordinary Roc handlers or async transport workers.
- Representative Datastar traces show material wire-byte savings without a
  material regression in event latency or ordinary-request tail latency.
- Changing realistic patches, heartbeat-only streams, and incompressible
  maximum events are included; repeated identical patches are not accepted as
  the only compression corpus.
- All supported native targets produce streams decoded by independent Brotli
  implementations and browsers.

Failure response:

- Try a lower quality/window or a different streaming Brotli adapter while
  preserving the same contract. If the browser/proxy latency or a finite
  worst-case output bound cannot be demonstrated, keep identity temporarily
  and treat first-class Brotli as a release blocker rather than silently
  weakening flush semantics.

### Spike 6: `Pulse`

**Question:** Can local wake acceleration remain race-free, bounded, and
clearly non-durable?

Minimum prototype:

- Fixed-capacity resource heap and opaque ARC handle.
- Generation observe, notify, and wait registration.
- Wait registration rechecks generation atomically with respect to notify.
- At most one pending wake per stream.
- Mandatory fallback timer.

Pass criteria:

- No lost wake between observe, query, and waiter registration.
- Burst notifications coalesce.
- Waiter and resource capacities saturate deliberately.
- Drop and shutdown remove waiters exactly once.
- A multi-process or restart test remains correct through fallback polling.
- Documentation and types make it difficult to mistake Pulse for message
  delivery.

### Spike 7: Roc and Datastar ergonomics

**Question:** Can the functional API be as pleasant as the Go SDK for the
target applications?

Build realistic examples:

- Form or button action returning a finite element and signal patch.
- Progressive three-stage operation.
- Long-lived SQLite-backed todo/dashboard view.
- Durable event-ID replay after reconnect.
- Mutation with transactional idempotency and a post-commit Pulse.
- User-visible error event followed by close.

Evaluate:

- Required annotations and error plumbing.
- Whether `Sse.steps` covers common progressive cases.
- Whether `Sse.unfold!` state and wake handling are understandable.
- Whether packages can encapsulate reusable stream state.
- Whether the three-function application contract truly remains unchanged.
- Whether users are tempted to block inside callbacks and how the API/docs
  discourage it.

### Spike 8: Scale, overload, and shutdown

**Question:** Are retained memory, scheduling, and lifecycle behaviour
consistent with the platform goals?

Scenarios:

- 10,000 idle streams on an appropriately configured Linux reference host.
- The same retained-state measurements at smaller portable scales on every
  native runner target.
- HTTP/1.1 file-descriptor and per-connection memory accounting.
- HTTP/2 many-stream behaviour and per-connection fairness.
- Slow-reader population mixed with fast clients.
- Mixed Brotli and identity streams carrying realistic compressible and
  incompressible event traces, including an encoder CPU saturation case.
- Timer herd and Pulse herd.
- Continuous ordinary request load during stream callbacks.
- Mass client disconnect.
- Graceful shutdown with idle, backpressured, and actively advancing streams.
- Callback that never returns, confirming the documented hard-shutdown limit.

Record:

- Fixed and per-stream retained bytes.
- Host tasks/timers/waiters.
- Active and queued Roc invocations.
- Output high-water memory.
- Ordinary request tail latency.
- Stream wake-to-event latency.
- Brotli CPU time, compression ratio, encoder-memory high-water mark, and
  event-flush latency.
- Shutdown duration and final accounting.

Gate:

- No unbounded structure is found.
- Idle streams do not consume worker threads.
- Ordinary requests retain configured capacity.
- Disconnect/shutdown returns all stream accounting to zero.
- Results are sufficient to choose safe finite defaults.

## Cross-platform and release test matrix

The eventual feature needs coverage for:

- HTTP/1.1 and cleartext prior-knowledge HTTP/2.
- Finite, progressive, timer-driven, and Pulse-driven streams.
- Zero, one, and multiple events.
- Event IDs set, retained by client, cleared, and replayed from durable state.
- Datastar signal decoding for every supported action method and content mode.
- Finite HTML, JSON, and explicit JavaScript response handling.
- Hidden-page cancellation/reopen and explicit request cancellation.
- Same-method-and-URL automatic cancellation, cleanup cancellation, and
  disabled overlap.
- Clean EOF, abrupt reset, HTTP error, and 204 behavior under each retry mode.
- Disconnect before commitment, while waiting, under backpressure, and during a
  callback.
- Slow client isolation.
- Stream and callback saturation before commitment.
- Immediate-step loop protection.
- Automatically negotiated Brotli and identity, including `br;q=0`, wildcard,
  quality-weight, absent-header, and `Cache-Control: no-transform` cases.
- Progressive Brotli decode after each event and heartbeat, clean encoded EOF,
  disconnect without finish, and an incompressible maximum-size event.
- Reverse-proxy buffering and timeout configuration.
- Graceful shutdown and hard-deadline behaviour.
- Debug ownership assertions and native memory instrumentation.
- Every active example maintaining exactly one `scripts/test_spec.json` entry.
- Every supported release target without platform-specific semantic skips.

## Evidence required before changing `design.md`

The experiment is ready to propose an enduring design change only when:

1. The retained-machine ABI or explicit-state fallback passes ownership and
   cross-target tests.
2. Progressive delivery, cancellation, backpressure, and shutdown work through
   the real listener under HTTP/1.1 and HTTP/2.
3. Resource units, bounds, saturation, ownership, and release points are known.
4. Idle-stream retained memory and callback scheduling have been measured.
5. The first-party Datastar API has been exercised by realistic examples and
   compared with the pinned official SDK.
6. Streaming Brotli passes progressive browser/proxy delivery, finite memory,
   CPU-isolation, cross-target, and useful-compression gates.
7. `Pulse` either passes its non-durable bounded contract or is removed from the
   base design.
8. The scope change can be expressed without weakening the continuing
   non-goals.

At that point, `design.md` should be updated to describe the accepted WHAT and
WHY:

- bounded pull-generated SSE as a supported exception;
- parked request-local Roc stream state and its owner;
- host scheduling, backpressure, cancellation, and shutdown responsibilities;
- the narrow role of any accepted Pulse-like subsystem;
- generic response streams, WebSockets, background tasks, and message buses
  remaining outside scope.

Spike mechanics, migration status, temporary limitations, and benchmark
results should remain in focused documents and code rather than being copied
into the design contract.

## Open research questions

1. Can a recursive boxed stream machine be represented without exposing erased
   callable layout directly to Rust?
2. Does a fixed Roc advance/drop wrapper provide all required recursive ARC
   teardown, or should glue generate an explicit payload destructor callback?
3. Can returned event buffers be retained zero-copy as independent Hyper frames
   without holding unrelated captures longer than necessary?
4. Should the first step run before response commitment?
5. Is a dedicated callback pool simpler and safer than a fair shared Roc
   scheduler with reservations?
6. What is the right semantic result of a step whose events are accepted by the
   body channel but never reach the peer?
7. After first-class Brotli, is there measured value in adding streaming
   Zstandard or gzip, or would additional codings only multiply test and
   operational surface?
8. Should `X-Accel-Buffering: no` be unconditional, configurable, or documented
   application metadata?
9. Should there be any default maximum stream lifetime, given that the pinned
   Datastar client's default retry mode does not reconnect after clean EOF?
10. Is `Pulse` sufficiently valuable for the initial release, or should timer
    polling be the first complete contract?
11. How should callback-ready work be scheduled so 10,000 simultaneous wakes
    do not starve ordinary requests or allocate 10,000 queued jobs?
12. Can Datastar remain re-exported by the platform while being versioned and
    tested independently of the generic SSE transport?
13. Does the pinned Datastar client send, retain, and clear last-event-ID in all
    retry modes we intend to document?
14. What reference deployment and proxy configuration should define the
    end-to-end progressive-delivery smoke test?

## Candidate implementation sequence after the gates

This is not an implementation plan yet, but it records dependency order:

1. Pin Datastar protocol fixtures.
2. Prove the boxed-machine ABI and fallback decision.
3. Build the bounded Hyper SSE body and lifecycle state machine.
4. Add explicit callback admission and fairness.
5. Add the generic typed `Sse` Roc API and internal ABI conversions.
6. Add finite `Datastar.respond` and typed patch/signal helpers.
7. Add and gate the backpressured streaming Brotli body.
8. Add host-scheduled dynamic streams and timers.
9. Add optional `Pulse` only after its independent gate passes.
10. Add proxy, reconnect, observability, and scale validation.
11. Propose the enduring `design.md` scope change with measured evidence.

## Source material

Local architecture and implementation:

- [`design.md`](../design.md)
- [`platform/Server.roc`](../platform/Server.roc)
- [`platform/InternalServer.roc`](../platform/InternalServer.roc)
- [`platform/main.roc`](../platform/main.roc)
- [`src/http_server.rs`](../src/http_server.rs)
- [`src/compression.rs`](../src/compression.rs)
- [`src/response.rs`](../src/response.rs)
- [`src/server_transport.rs`](../src/server_transport.rs)
- [`src/file_server.rs`](../src/file_server.rs)
- [`src/telemetry.rs`](../src/telemetry.rs)
- [`src/shutdown.rs`](../src/shutdown.rs)
- [`src/roc_platform_abi.rs`](../src/roc_platform_abi.rs)

External protocol references to pin during Spike 0:

- [Datastar backend actions](https://data-star.dev/reference/actions)
- [Datastar SSE events](https://data-star.dev/reference/sse_events)
- [Datastar backend requests guide](https://data-star.dev/guide/backend_requests)
- [Official Datastar Go SDK](https://github.com/starfederation/datastar-go)
- [Datastar Go SSE implementation](https://github.com/starfederation/datastar-go/blob/main/datastar/sse.go)
- [Datastar Go v1.2.2 compression API](https://pkg.go.dev/github.com/starfederation/datastar-go/datastar#WithCompression)
- [Datastar Go v1.2.2 SSE compression source](https://github.com/starfederation/datastar-go/blob/v1.2.2/datastar/sse-compression.go)
- [WHATWG Server-Sent Events](https://html.spec.whatwg.org/dev/server-sent-events.html)
- [RFC 7932: Brotli Compressed Data Format](https://www.rfc-editor.org/rfc/rfc7932.html)
- [NGINX proxy buffering](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)

The experiment should record exact source commits rather than assuming these
moving pages remain the same throughout the research.

## Decision log

### 2026-08-01: Initial convergence

Three adversarial design reviews focused separately on Roc application
ergonomics, host/runtime correctness, and Datastar compatibility. They
independently converged on a host-scheduled stream machine rather than a
long-running writer.

The preferred representation is an opaque boxed Roc machine, conditional on an
ABI spike. The agreed fallback is a fourth `stream!` application entrypoint,
not an imperative persistent writer.

A payload-free coalescing Pulse is considered compatible only as optional local
wake acceleration backed by mandatory durable re-query and a fallback timer.

### 2026-08-01: Brotli is part of the first-class SSE target

SSE and Datastar responses automatically negotiate host-owned streaming
Brotli when the client accepts `br`; identity is the fallback and
`Cache-Control: no-transform` is the explicit opt-out. One bounded encoder is
retained for the response and flushed after every event and heartbeat.

This is a release hypothesis, not an assumption that the existing whole-body
compressor is already sufficient. Progressive browser and proxy delivery,
worst-case encoded-output bounds, CPU isolation, useful compression on real
Datastar traces, clean completion, and cross-target decoding are an explicit
feasibility gate.

These experiment decisions have not yet changed code or the accepted
`design.md` contract.
