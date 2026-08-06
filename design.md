# basic-webserver design

## Purpose of this document

This document describes the intended end-state architecture of
`basic-webserver`. It is a design contract, not an implementation plan or a
record of the current implementation.

The document concentrates on what the platform is responsible for, why those
responsibilities belong here, and which use cases are deliberately outside its
scope. Proposed changes should be evaluated against these boundaries. This
document should change only when experience reveals a conflict between its
goals, invalidates an assumption, or provides important new information about
the desired architecture.

## Product definition

`basic-webserver` is a dependable, high-performance, cross-platform Roc
platform for conventional HTTP request/response applications and bounded
server-sent event responses.

It is intended to be especially good for:

- JSON and HTML APIs;
- CRUD applications backed by SQLite;
- server-rendered pages and form handling;
- Datastar actions, progressive feedback, and timer-driven server-sent events;
- webhooks and integrations with other HTTP services;
- bounded uploads;
- public static assets and authorized file downloads handled by the host;
- small, self-contained services deployed behind a reverse proxy.

It is not intended to be a general asynchronous application runtime, an edge
proxy, or a full-stack web framework. Breadth of use cases is less important
than making the supported use cases safe, predictable, fast, and pleasant.

## Design goals

### Rock solid

For workloads inside the supported scope, behaviour must be explicit and
predictable under concurrency, overload, partial input, startup failure, and
shutdown. Memory safety and resource safety must not depend on application
authors following unenforceable conventions.

Queues, bodies, concurrency, and other resource-consuming operations must have
finite limits. Failure should be typed or converted into a deliberate HTTP or
process outcome rather than producing silent corruption or uncontrolled
resource growth.

### High performance

The common request path should avoid global serialization and unnecessary
copies, allocations, thread hand-offs, and transitions across the Roc/host
boundary.

Operations that are naturally transport-heavy or operating-system-heavy, such
as serving a file, should remain in the host. High performance means good
throughput and tail latency under realistic bounded load, including graceful
behaviour at saturation; it does not mean maximizing a benchmark while allowing
unbounded resource use.

### Ergonomic

An ordinary application should describe startup, handle a request using
immutable configuration, and return an outcome. Applications that do not need a
facility should not have to model it.

The platform should provide a small number of strong, composable primitives.
Application policy, routing conventions, validation, and domain modelling stay
in Roc unless moving a narrowly defined operation into the host provides a
clear safety or performance benefit.

### Cross-platform

Supported features must have one documented semantic contract across the
platform's release targets. Platform-specific optimizations are welcome behind
that contract, but applications should not need different architectures for
Linux, macOS, and Windows.

When these goals conflict, correctness, boundedness, and clear semantics take
priority over feature breadth and peak benchmark results.

## Architectural boundaries

The system assigns each kind of state to an explicit owner:

| Kind of state | Owner | Examples |
| --- | --- | --- |
| Request-local state | Roc request handler | Parsed input, authorization decisions, response construction |
| Immutable application context | Roc application | Paths, secrets, endpoint URLs, templates, feature configuration |
| Durable domain state | SQLite or an external service | Users, sessions, orders, jobs |
| Operational server state | A typed host subsystem | Open files, connection pools, metrics, readiness, active transfers |
| Arbitrary process-local domain state | Not provided by the platform | Mutable application dictionaries, reducers, actors |

This separation is central to the design:

- Roc owns application policy and pure computation.
- SQLite or an external service owns durable application facts.
- The host owns concurrency, transport, operating-system resources, and
  narrowly scoped operational facilities.

The platform does not provide a general mutable application model. In
particular, request handlers do not send actions through a global reducer or
state coordinator. Such a coordinator introduces a process-local source of
truth, a serialization point, and a deployment model that does not extend to
multiple processes.

## Application contract

The conceptual application contract is:

```roc
program = { init!, respond!, shutdown! }

init! : () => Try(
    { config : Server.Config, context : Context },
    [Exit(I64), ..],
)

respond! : Server.Request, Context
    => Try(Server.Outcome, [ServerErr(Str), ..])

shutdown! : Server.ShutdownReason, Context
    => Try({}, [Exit(I64), ..])
```

The exact surface syntax may evolve, but the semantics are intentional.

### Initialization

`init!` runs exactly once before the listener becomes active. It:

- validates application configuration;
- chooses server configuration;
- performs startup checks or migrations;
- opens dormant host subsystem resources;
- produces the immutable context used by handlers.

No listener, route, or subsystem created during initialization becomes
externally active unless initialization and complete server configuration
validation succeed. Failed initialization releases its resources.

### Immutable context

`Context` is the application's immutable startup data. A context containing
only `{}` has effectively zero application state.

The host retains the context safely for the server lifetime and gives each
concurrent handler a valid owned reference. It must not turn the value into
static leaked data. Reference ownership, nested refcounted values, and final
destruction must remain correct under concurrent requests.

An opaque subsystem capability may appear in `Context`, but the capability
refers to host-owned, concurrency-safe state. The apparent immutability of a Roc
value must never be used to justify sharing an unsynchronized mutable host
pointer.

### Request handling

`respond!` calls may execute concurrently. A handler receives only its request,
immutable context, and explicitly invoked platform effects. It may return an
ordinary response, a typed native response plan, or one typed SSE
source. A returned source represents request-authorized functional state; it
does not create shared mutable application state or ordering between otherwise
independent requests.

The compiled Roc application is treated as a synchronous, reentrant native
library rather than as an asynchronous executor. Each `respond!` invocation
runs synchronously from entry through return on one host execution thread.
Request-local Roc values, borrowed host views, and ABI call state remain
confined to that invocation unless the ABI explicitly defines a safe ownership
transfer. The platform does not expose thread identity or promise that the
network lifecycle surrounding the invocation remains on that thread.

Synchronous Roc execution must not block the host's asynchronous transport
workers. The host admits Roc invocations to a distinct, bounded execution
domain and waits for their results without preventing unrelated connections or
HTTP/2 streams from making progress. Ordinary handlers and ready SSE
transitions compete in the same bounded FIFO execution domain; parked SSE
sources consume no Roc worker. The number of active invocations and the amount
of queued work are explicit server resources with finite limits and documented
saturation behaviour; an executor's implicit worker or blocking pool limits
are not the server's capacity policy.

There is no implicit ordering between handlers. Any ordering or atomicity
required for domain state comes from a SQLite transaction or an external
service. Any ordering required by a host subsystem is part of that subsystem's
documented contract.

### Shutdown

Graceful shutdown is a lifecycle concern, not application state management.
The host stops accepting work, cancels parked and queued SSE work, drains active
native transfers and Roc invocations within finite deadlines, calls
`shutdown!` once when it is safe to do so, and then releases the context and
subsystems.

Subsystems required by `shutdown!` remain available until the hook completes.
Once draining begins, operations that cannot safely start during shutdown
return a stopping error.

The platform does not promise that arbitrary Roc computation, a blocking
effect, or an already-running SSE transition can be safely preempted. Transport
cancellation prevents future work but an executing invocation remains
request- and handler-accounted until it returns. If work exceeds a hard drain
deadline, process termination is preferable to concurrently destroying
resources that the work may still use.

Applications that need no shutdown action should be able to use a trivial
platform-provided implementation.

## Resource ownership and allocation model

High performance means that the platform has explicit control over the
resources it introduces. It does not mean removing safety checks for external
input or relying on executor, allocator, or operating-system defaults.

Every resource-bearing path has a documented:

- owner;
- unit and finite bound;
- saturation behaviour;
- lifetime and release point;
- observable usage and high-water mark.

This applies to allocations, byte buffers, active handlers, queued work,
connections, HTTP/2 streams, child processes, file transfers, SQLite
connections and statements, capability registries, route tables, caches, and
metrics cardinality. There are no implicitly unbounded queues, pools, caches,
registries, or worker sets.

The server's capacity should be understandable as bounded fixed state plus the
configured per-connection, per-handler, per-transfer, and per-subsystem
budgets. Configuration controls resources that applications have a meaningful
reason to tune; finite defaults remain safe under overload.

### Host resource handles

Long-lived native resources exposed to Roc, such as SQLite statements, buffered
file readers, and TCP streams, are represented by opaque refcounted handles.
The handle payload contains a host lifecycle token rather than a native
pointer. Its identity is valid only while the caller owns a live Roc ARC
reference. The host owns the native resource in a bounded, type-specific,
concurrency-safe resource heap and validates the live handle before every
operation.

Roc ARC defines the handle lifetime. At the host allocator boundary, the
deallocator recognizes each resource heap's handle-allocation range, and the
final Roc reference release routes through the owning heap to close and destroy
the native resource exactly once.

This applies equally to handles retained in application context and to
request-local handles; correctness does not depend on application code calling
`close`. The public API does not expose an explicit close operation; final Roc
ARC release and orderly shutdown are the resource lifecycle.

Each resource heap has a finite capacity, reports a typed saturation error, and
tracks active and high-water counts. A live ARC handle pins its stable slot,
which is never reused while any valid reference exists. Final release
invalidates the handle, closes the native resource, and only then permits slot
reuse. Using its raw payload pointer after final release is invalid ABI
behaviour, not a supported stale-capability lookup. Cross-type and structurally
invalid live handles are rejected.

Resource-specific synchronization protects concurrent operations without
serializing unrelated resources.

Graceful shutdown first drains handlers, then runs the Roc shutdown hook and
releases application context. Final ARC release closes resources retained by
that context before host teardown completes. Resource heap backing storage
remains valid until no Roc code can run; hard process termination relies on the
operating system only after safe in-process teardown is no longer possible.

### Host/Roc byte ownership

The host calls Roc and controls the complete lifecycle of a request. Byte
storage passed from the host into Roc is therefore represented as a
reference-counted seamless `Str` or `List` slice whenever its representation
allows it. The slice points at existing immutable backing storage, and ARC
keeps that backing allocation alive for every Roc value that can still refer
to it.

This is the preferred boundary because it creates only the small Roc value
describing the view and does not allocate and copy the payload. It applies to
request targets, headers, body chunks, and bounded effect results where the
host owns suitable backing storage.

The host retains its ownership until the provided Roc call and every value
escaping from it have transferred, retained, or released their references. A
response may contain a seamless slice of request or effect data: ARC keeps the
backing allocation alive while the host converts or transmits that response.
The end of the Roc handler is not assumed to be the end of a backing
allocation's lifetime.

Roc operations may create further seamless slices into the same allocation.
An operation that requires independently mutable or growable storage
materializes an owned allocation rather than modifying seamless backing
storage. The platform and compiler ABI must agree on allocation-base recovery,
atomic reference counting for host-visible values, and which operations may
reuse storage.

Byte-oriented boundaries use one of four explicit strategies:

| Strategy | Purpose |
| --- | --- |
| Reference-counted seamless slice | Share existing immutable backing storage with Roc |
| Ownership transfer | Move a compatible allocation across the boundary |
| Native host plan | Keep large transport data out of Roc entirely |
| Bounded copy | Handle an incompatible representation or lifetime |

A bounded copy is a deliberate fallback, not the default. A change that adds a
payload copy to the common request path must justify why seamless sharing,
ownership transfer, or a native plan cannot provide the required lifetime and
representation.

### Allocation and buffer policy

Network-controlled lengths are validated before they cause proportional host
or Roc allocation. Chunk sizes and buffered-chunk counts bound streaming
memory independently of total body or file size.

Ordinary Roc responses, individual Roc-produced SSE events, and materialized
effect results are for bounded data. Large files, downloads, uploads, and other
transport-oriented byte flows remain in native host streams under protocol
backpressure. Outbound HTTP and command output enforce their byte limits before
exposing results to Roc.

SSE configuration independently bounds admitted streams and the maximum framed
event returned by one transition. Admitted streams bound host-owned source
slots, timers, response-body state, and optional compression state. Arbitrary
Roc values captured by a source remain trusted application memory, just like
values allocated by an ordinary handler; the platform does not claim to trace
or byte-quota their transitive graph.

Pools and caches have finite capacities and explicit eviction or saturation
behaviour. In particular, prepared-statement caches and metrics label sets do
not grow once for every application-controlled string.

The host supplies Roc's allocator and may select, configure, and instrument an
allocator appropriate to the supported targets. The design does not require a
particular allocator implementation. It does require exact ownership transfer,
balanced ARC operations, correct alignment and allocation-base recovery, and
no context or resource leaks.

The application is trusted code rather than an isolation boundary. The
platform bounds resources derived from hostile network input and bounds the
concurrency with which handlers can consume resources. It does not promise to
contain arbitrary allocation, infinite computation, or deliberate resource
abuse performed directly by application code.

### Debug validation of invariants

Internal ownership and lifecycle invariants are checked aggressively in debug
host builds and tests. Debug instrumentation should make incorrect unsafe code
and lifetime assumptions fail close to their cause rather than becoming rare
release-only corruption.

As applicable, debug builds validate:

- allocation alignment, headers, allocation-base recovery, and canaries;
- live-allocation registration and balanced allocation/deallocation;
- ARC retain/release balance, underflow, and expected static-data treatment;
- every seamless slice range against a live backing allocation;
- the continued lifetime and immutability of seamless backing storage;
- ownership transfer at hosted and provided ABI boundaries;
- resource-handle type, generation, and lifecycle state;
- request, connection, queue, transfer, and subsystem accounting;
- legal transitions through configuring, running, draining, and stopped
  lifecycle states;
- cleanup of request-scoped resources and the absence of unexpected live
  resources at test completion.

Tests exercise the instrumented debug host so lifetime, ownership, and cleanup
properties are verified under concurrency, cancellation, errors, overload, and
shutdown. Tests that deliberately retain a seamless slice through a response
or effect boundary verify that its backing allocation remains live until the
last reference is released.

On targets where dynamic native memory instrumentation is available, tests
also execute complete compiled applications through their real HTTP listener
under that instrumentation. Validation must cover the Rust host, generated ABI
glue, Roc allocations, hosted callbacks, and shutdown cleanup. An
instrumentation build is valid only when the tool can observe the allocator and
executed request path; a run that silently observes no relevant allocation or
memory activity is not accepted as evidence of safety.

Debug assertions and diagnostic bookkeeping do not define correctness. The
ownership protocol and release behaviour are identical in release builds, but
expensive ledgers, canaries, repeated invariant checks, and diagnostic
metadata are absent from optimized release hosts.

Validation of untrusted input, bounds checks needed for memory safety,
resource-limit enforcement, stale-capability rejection, and externally
observable error handling remain enabled in release builds. They are part of
the server contract, not debug instrumentation.

Performance evaluation uses optimized release hosts and records more than
request throughput. Relevant measures include allocations, retained bytes,
payload bytes shared through seamless slices, payload bytes copied, active
resource high-water marks, rejection counts, and tail latency at and beyond
saturation.

End-to-end load evaluation exercises a real compiled Roc application through
the real listener. It covers HTTP/1.1 and HTTP/2, fast handlers, handlers that
invoke hosted effects, sustained concurrency, and overload. Results distinguish
request throughput from simultaneously active work and record enough
configuration and resource data to explain coordination limits between the
transport, Roc execution domain, and host subsystems. Indicative measurements
from ordinary developer machines guide investigation but do not define a
portable performance guarantee.

Controllable invariant validation and performance evaluation have different
authority. An instrumented test host may replace the production TCP listener
with a bounded accepted-stream transport before application initialization. A
substituted host must still execute the compiled Roc application's real
`init!`, `respond!`, SSE transition, and `shutdown!` callbacks through the same
request, admission, response, and cleanup state machines as the production
host. Its controllable peer is authoritative for lifecycle, ownership, failure
mapping, and the resource-bound invariants explicitly asserted by its
scenarios; its timings and process memory are not capacity evidence.

Real-listener evaluation remains authoritative for throughput, tail latency,
resident memory, operating-system limits, transport backpressure, and scheduler
or compression contention. Machine-dependent measurements are compared only
between explicitly recorded runs on a controlled machine. Ordinary CI may gate
socketless semantic and cleanup invariants, but does not turn local timing or
resident-memory observations into portable pass/fail thresholds.

Test substitution is an internal host boundary, not a Roc capability. Normal
release artifacts select the real operating-system implementations and do not
expose a control protocol, fake resource, or general dependency container to
applications. Operational metrics that are useful in production remain
low-cardinality and low-overhead; detailed allocation epochs and test control
exist only in explicitly instrumented hosts.

## Request path

The request path has two possible destinations and three Roc outcomes:

```text
HTTP request
    |
    v
host limits, normalization, and route selection
    |
    +-- native route ----------> host subsystem ----------> HTTP response
    |
    `-- Roc fallback route ----> respond!(request, context)
                                      |
                                      +-- ordinary response
                                      +-- typed SSE source ----> bounded stream slot
                                      |                                  |
                                      |                                  v
                                      |                         finite Roc transitions
                                      `-- typed native response plan
                                                   |
                                                   v
                                             host subsystem
                                                   |
                                                   v
                                             HTTP response
```

A native route is appropriate when the host can complete the operation without
application policy. A native response plan is appropriate when Roc must first
make a policy decision, but the resulting transfer should remain in the host.

For example:

- a public `/assets` mount can bypass Roc;
- an authorized download first enters Roc, then returns a host file-serving
  plan after authorization succeeds.

## Routing

Host-native routing is deliberately smaller than an application router.

- Native exact paths and prefixes are declared as part of startup
  configuration.
- Route conflicts are rejected before listening.
- Resolution is deterministic, with exact routes and more specific prefixes
  taking precedence.
- A native route owns its declared path space and defines the allowed methods.
  Unsupported methods do not silently fall through to unrelated Roc logic.
- Requests not owned by a native route go to the Roc handler.
- Route topology is immutable while the server is running.

Public native routes bypass Roc application policy by definition. Facilities
that may require authentication or per-request authorization must also support
a native response plan selected by the Roc handler.

Runtime changes may alter the internal state of a subsystem through typed
operations, but do not dynamically install arbitrary routes.

## Host subsystems

A host subsystem is a narrowly scoped, typed facility whose state and
concurrency are fully owned by the host. It is the preferred way to support
operations that would otherwise require large byte transfers through Roc,
unsafe resource sharing, or duplicated server machinery.

A facility belongs in the host only when:

1. its semantics are application-independent;
2. the host can own and bound all mutable state involved;
3. it does not require arbitrary callbacks into Roc;
4. streaming, pooling, caching, or operating-system integration gives a clear
   benefit;
5. one dependable cross-platform contract is achievable;
6. it does not need an atomic transaction with arbitrary application state.

Subsystem APIs are specific to their purpose. The platform does not expose a
generic dynamically typed object store, generic state update operation, or
plugin-style native response mechanism.

### Subsystem capabilities

Capabilities exposed to Roc are opaque references to host-owned resources.
They must:

- be safe to retain in immutable context;
- be safe to use from concurrent handlers;
- reject stale or invalid use;
- have deterministic lifetime and shutdown behaviour;
- enforce their own resource and concurrency limits;
- expose typed operations and failures.

Internally mutable resources must be synchronized at the level at which
concurrent access can occur. Per-object locking is insufficient when several
objects share an unsynchronized underlying connection or resource.

### Configuration and activation

Creating a subsystem resource during `init!` does not immediately mutate the
active server. Initialization produces dormant resources and declarative route
or server configuration. The host validates and activates the complete
configuration atomically before listening.

This prevents partial startup and keeps the active server configuration a
single source of truth.

After startup, typed operations may change state that is inherently dynamic,
such as readiness, metrics, certificate material, or a subsystem cache policy.
The set and ownership of routes remain fixed.

## Request-scoped hosted effects

Stateless request handling is not effect-free request handling. A Roc handler
may synchronously invoke platform effects such as an outbound HTTP request, a
SQLite transaction, finite command execution, or filesystem access.

A request-scoped hosted effect represents one finite operation initiated by a
handler. The host owns the operating-system or transport resources used to
perform it, while the handler remains responsible for application policy and
waits for a typed result. Other handlers may continue concurrently within the
server's limits.

The hosted callback begins and returns on the calling Roc invocation's thread.
It may delegate transport or operating-system work to an asynchronous host
subsystem and synchronously wait for the typed result. Arguments retained by
that work must first be converted to independently owned host data; asynchronous
work must not retain borrowed Roc pointers or invocation-local ABI state. A
hosted effect must not depend on admission to the same saturated Roc execution
domain whose invocation is waiting for it.

Request-scoped effects must:

- have a finite, documented resource policy;
- participate in subsystem-specific and server-wide concurrency limits;
- return typed failures for relevant timeouts and limits;
- keep active work accounted for during graceful shutdown;
- release host resources on every success and failure path;
- avoid hidden mutable application state or ordering between unrelated
  handlers;
- provide the same observable contract on every supported target.

Immutable context may contain the data needed to request an effect, such as a
validated URL, credential, executable path, fixed arguments, database path, or
limit configuration. It may contain a concurrency-safe opaque capability to a
host subsystem. It does not contain an unsynchronized live connection, child
process, or other mutable operating-system resource.

Client disconnection does not imply rollback or automatic cancellation of an
effect. An outbound request may already have reached its destination and a
child process may already have changed external state. Effects with cancellable
transport may stop early, but the API must not describe cancellation as undoing
completed work. Accepted work remains tracked until it finishes, reaches its
own limit, or the server applies its documented hard-shutdown policy.

Request-scoped effects do not provide detached execution. Work that must
outlive a request is durable domain state: it is recorded in SQLite or an
external service and processed by a separately supervised worker.

## Intended subsystems

### SQLite

SQLite is the default durable state mechanism for self-contained applications.
The host owns connection management and any reusable statement cache;
applications identify a database through immutable configuration such as a
path.

SQLite support is considered production infrastructure and must provide clear
semantics for:

- transactions and rollback;
- concurrent readers and writers;
- bounded lock waiting and busy failures;
- per-connection configuration;
- statement reuse;
- connection lifetime;
- typed database errors.

The platform does not pretend that a local SQLite database is distributed
state. Deployments requiring shared state across machines use an external
service through an appropriate platform effect or package.

### Static files and file responses

The host supports:

- public file mounts declared at startup; and
- authorized file responses selected by Roc.

File contents remain in the host and are streamed with bounded memory. The
contract includes safe root-relative path resolution, traversal prevention,
explicit symlink and dotfile policies, GET and HEAD, conditional requests,
range requests, content metadata, and consistent behaviour across supported
operating systems.

Directory listing is disabled unless a future design explicitly makes it safe
and necessary.

### Request-body sinks

For uploads whose destination is a host resource, a handler may authorize the
operation and ask the host to transfer a bounded request body directly to that
resource. Roc receives metadata and the final result rather than every byte.

This does not create a general upload server or bypass application policy.

### Operational facilities

Access logging, request metrics, overload metrics, and readiness are host
concerns. They can observe the server lifecycle and request completion without
requiring every application to maintain counters.

Operational endpoints may be native exact routes. Mutable controls such as
readiness use small, typed, concurrency-safe capabilities.

### Outbound HTTP

Outbound HTTP is a host-owned pooled facility. Applications construct and
validate requests in Roc, while the host owns connection reuse, transport
timeouts, TLS implementation, and transport error classification.

It is intended for finite API calls, webhooks, and communication with local or
remote services. It is not the data path for a streaming reverse proxy or an
unbounded download.

Outbound requests have finite time and response-body limits. Global,
per-destination, connection, and queued-request concurrency are bounded.
Saturation, DNS failure, connection failure, TLS failure, timeout, cancellation,
and response-limit failure are observable as typed outcomes. Connection pooling
is an internal optimization and does not introduce application-visible mutable
state.

Hidden retries are avoided where they could duplicate application effects.
Retry policy belongs in Roc unless the transport can prove that retrying did
not transmit the request. A client disconnect does not by itself cancel or
reverse an outbound request.

The basic effect waits for one response. If concurrent fan-out is supported, it
is a separate finite, bounded batch operation rather than a general future,
task, or asynchronous callback API.

### Command execution

The platform supports finite command execution during initialization or as a
request-scoped hosted effect. Intended uses include invoking a compiler,
converter, or existing system utility and waiting for its exit status or
bounded output.

Commands are executed directly from an exact native executable and argument
list. The platform does not implicitly invoke a shell, expand arguments, or
interpret command text. Choosing an executable and constructing safe arguments
remain application policy.

Command execution has explicit bounds on:

- execution time;
- captured standard output and standard error;
- concurrent child processes;
- queued command work.

The API explicitly defines whether a command inherits or replaces process
environment, working directory, and standard streams. These choices are
application policy rather than ambient, undocumented host behaviour.

When a time or output limit is exceeded, the host terminates the command
according to documented cross-platform process-tree semantics, waits for
resource cleanup, and returns a typed failure. Shutdown accounts for active
children and applies the same termination semantics rather than abandoning
them.

Commands that inherit standard streams may interleave output with the server
and are intended for deliberate operational use. Captured output is bounded
before it is converted into Roc values, so a child process cannot force
unbounded host or Roc allocation.

Command execution is not process supervision. Detached processes, persistent
workers, daemon management, automatic restart, and background job scheduling
are outside the platform's scope. Those processes are started and supervised by
the deployment environment and communicate with the application through
durable or external interfaces.

## Data and streaming boundaries

Inbound request bodies are bounded streams. Applications can process them
incrementally, narrow their limits, or delegate an authorized transfer to a
host subsystem. Body chunks use reference-counted seamless slices into
host-owned backing storage, avoiding payload copies while ARC preserves their
lifetime.

Ordinary Roc responses are complete, in-memory values. This keeps the handler
contract simple and makes ownership across the host boundary explicit. They
are appropriate for normal API and HTML responses, not arbitrarily large
payloads. A response may retain seamless slices of request or effect data; the
host keeps their backing allocations alive until transmission or an explicit
bounded materialization completes.

Large or transport-oriented responses are represented by a closed set of typed
native response plans, such as serving a file. The host streams those responses
without moving their contents through Roc.

### Roc-produced server-sent events

SSE is a narrow exception to the complete ordinary-response rule. An
application may return a typed, retained functional source whose transitions
produce canonical SSE events, wait for a host timer, end, or fail. The source
forms one host-owned transition chain: while parked, the host owns the chain's
current reference in a finite stream slot; while advancing, one synchronous
Roc invocation owns it and returns the next source. Roc values remain normally
duplicable inside trusted application code; the platform guarantees only that
its own use of the returned source is single-owner and sequential. Applications
do not receive a socket, response writer, compressor,
task, arbitrary byte sink, or cancellation callback.

The first source transition occurs before the `200 text/event-stream` response
is committed. Stream admission failure, queue timeout, Roc panic, application
error, or an oversized first event therefore becomes an ordinary bounded HTTP
error. A successful first `Emit`, `Wait`, or `End` validates the source and may
commit the response. After commitment, a transition or framing failure is
logged and terminates only that response stream because its HTTP status can no
longer change.

Exactly one transition may run for a stream at a time. A returned event and its
next source remain in a draining state until the event has transferred into
host-owned transport or compression frames. Only then may the host park the
next source and arm its declared timer. This acknowledgement means accepted by
bounded host ownership, not delivered to the peer. Slow readers exert normal
HTTP backpressure and cannot cause the source to run ahead.

Disconnect and shutdown cancel parked and queued work immediately and prevent
future transitions. A transition already executing synchronously is not
preempted: it remains request- and handler-accounted, and its eventual result is
dropped rather than published. Normal stream completion finishes the selected
content coding; cancellation abandons it without pretending to produce a clean
end.

SSE sources are appropriate for finite Datastar actions, progressive feedback,
and timer-driven views over durable state. Application code should retain small
identifiers and cursors and re-query immutable context resources on each step.
The platform bounds every host-owned resource associated with a stream, but—
consistently with its trusted-application model—does not impose a transitive
heap quota on the Roc closure captured by one source.

### Response validation and framing

The application response contract is independent of the HTTP wire version.
Ordinary responses contain one status, a complete ordered header list, and a
complete bounded representation body. The host validates the whole response
before transmission and owns HTTP/1.1 and HTTP/2 message framing.

Applications may select ordinary representation metadata, but they do not
control connection state or transfer framing. SSE status and representation
headers are canonical and host-owned. Header names and values must use valid
HTTP field syntax. `Connection`, `HTTP2-Settings`, `Keep-Alive`,
`Proxy-Connection`, `TE`, `Transfer-Encoding`, `Upgrade`, `Trailer`, and fields
nominated by `Connection` are rejected. `Content-Length` is host-owned: an
application may omit it or assert the complete returned representation length,
but repeated values must agree and the host emits one canonical length for the
bytes it will transmit after content coding. Repeated non-framing fields retain
their order; the platform does not impose application security-header policy
or maintain a registry of repeatable extension fields.

Method and status semantics are part of the common contract:

- a `HEAD` handler returns the representation it would return for `GET`; the
  host derives its metadata and transmits no content;
- `204` and `304` require an empty body and no application-supplied
  `Content-Length`;
- `205` requires an empty body and is transmitted with a zero length;
- standalone informational responses are invalid because the ordinary
  one-response API cannot provide the final response that must follow them;
- a successful ordinary `CONNECT` response is invalid because the platform
  does not expose a tunnel outcome.

An invalid application response is never partially transmitted. The host logs
a diagnostic and substitutes a fixed, bounded `500 Internal Server Error`.
`StopAfter` uses the same validation while preserving its graceful-shutdown
intent. Native and host-generated responses pass through the same final
invariants, while native streams with an unknown length leave the protocol
framing choice to the host.

### Response content coding

The host negotiates response compression from `Accept-Encoding` by default.
It provides Zstandard, Brotli, and gzip for eligible ordinary and native file
responses, preferring the client's quality weights and using identity when
compression is not accepted or useful. At equal quality weights, the host
prefers Zstandard, then Brotli, then gzip.

Compression is a transport transformation, not application policy. The host:

- does not recompress an application-selected content coding;
- preserves byte-range semantics by serving range requests as identity;
- does not compress bodyless, already compressed, or known incompressible
  representations;
- emits cache-correct `Vary` and representation metadata;
- lets an application prevent transformation with `Cache-Control:
  no-transform`.

Ordinary response compression remains inside the bounded Roc handler execution
domain, and its temporary encoded copy has a fixed input-size ceiling. Native
file compression remains inside the bounded file-transfer domain and streams
through finite chunks, so memory use does not scale with file size.

Compressed request bodies are not decoded implicitly. A future request-decoding
facility must define supported content codings, apply limits to decoded bytes,
bound decoder memory and CPU, reject unsupported or stacked codings, and expose
failures through the request-body contract. A compressed byte length alone is
not a safe request resource bound.

SSE compression uses the same negotiation rules and emits `Vary:
Accept-Encoding` for every selected representation. It supports identity and
streaming Brotli; if the request forbids both, the precommit response is `406`
rather than silently selecting a forbidden representation. Compression work is
bounded independently from transport polling and a logical event is flushed
before the next source transition may begin.

General Roc-produced incremental byte streams are not a goal. The closed SSE
event/step vocabulary and host-owned scheduling are what keep this facility
from becoming a broader asynchronous runtime or arbitrary response writer.

## HTTP protocols and upgraded connections

The application contract models conventional HTTP request/response semantics
rather than a particular HTTP wire version. The host supports conventional
request/response traffic over HTTP/1.1 and HTTP/2 through the same Roc
application contract.

The host owns HTTP/2 multiplexing, header compression, flow control, stream
cancellation, concurrent-stream limits, and connection draining. These
responsibilities preserve the same bounded body, handler admission, overload,
and shutdown semantics exposed for HTTP/1.1 traffic. A synchronous Roc handler
must not stall unrelated streams on its connection. Protocol-specific details
do not enter the Roc request API unless applications have a demonstrated policy
decision that cannot be expressed through the common HTTP contract.

HTTP/2 server push is not a goal. Public TLS policy, certificate automation,
and public protocol negotiation such as ALPN normally remain responsibilities
of an edge proxy. The platform accepts HTTP/2 on a trusted connection from that
proxy without taking ownership of those edge responsibilities.

Application-defined WebSockets and other upgraded, long-lived bidirectional
protocols are outside the platform's scope. After an upgrade, processing
messages would require incremental callbacks into Roc, outbound backpressure,
connection cancellation and supervision, and per-connection scheduling. An
`Upgrade` outcome by itself does not solve those responsibilities and must not
be added as though it were an ordinary native response plan.

A host-native subsystem may proxy an upgraded connection without asking Roc to
process its messages, provided it independently satisfies the subsystem
criteria in this document. A constrained host-owned messaging facility would
be a deliberate expansion of scope and requires new design justification; it
must not become an indirect general WebSocket runtime or mutable application
state service.

## Concurrency, overload, and isolation

Concurrent requests must not pass through a global application lock or state
coordinator.

The host bounds active handlers, queued work, body buffering, active
connections or transfers where appropriate, and subsystem-specific resources.
At saturation it applies documented backpressure or returns a deliberate
overload response. It does not rely on an executor's large default blocking
pool or unbounded queue as its resource policy.

Configuration exposes limits that applications have a meaningful reason to
change. Defaults are finite and safe for an internet-facing service behind a
conventional reverse proxy.

One request must not corrupt another request's memory or host resources.
Ordinary application failures become request failures where recovery is safe.
The platform cannot guarantee recovery from arbitrary application crashes,
infinite computation, or effects that cannot be interrupted.

## Security boundary

The host is responsible for transport and resource safety:

- parsing and normalizing the request target consistently;
- enforcing request and buffering limits;
- preventing native file routes from escaping configured roots;
- validating headers and native response plans before passing them to protocol
  libraries;
- ensuring opaque capabilities cannot be forged into arbitrary host access;
- making concurrent hosted resource use memory-safe.

Roc application code is responsible for application policy:

- authentication and authorization;
- validation of domain input;
- access decisions for protected resources;
- transaction boundaries and domain invariants.

Deployments commonly place a reverse proxy or load balancer in front of
`basic-webserver`. Edge concerns such as public TLS policy, certificate
automation, HTTP protocol negotiation, global traffic shaping, and trusted
forwarded-client identity belong there unless a future design establishes a
compelling cross-platform reason to move a specific part into this platform.

## Deliberate non-goals

`basic-webserver` does not aim to provide:

- arbitrary mutable in-process Roc application state;
- a general actor, reducer, cache, key-value store, or message bus;
- application-defined WebSocket, upgraded-protocol, arbitrary byte-stream, or
  custom SSE runtimes beyond the platform's typed SSE source;
- HTTP/2 server push;
- arbitrary background Roc callbacks, schedulers, detached processes, daemon
  management, or worker supervision;
- dynamically installed routes or a generic native plugin system;
- a reverse proxy or API gateway;
- a replacement for an edge TLS proxy or load balancer;
- a universal database abstraction or built-in client for every database;
- distributed state, clustering, deployment orchestration, or job execution;
- unbounded request bodies, queues, response buffering, or concurrency;
- large arbitrary response streams incrementally generated by Roc;
- a complete application routing, middleware, templating, authentication, or
  frontend framework.

Some of these uses can be served by a separate process, an external proxy, a
Roc package built on the platform's existing effects, or a future narrowly
scoped host subsystem. Being technically possible is not by itself a reason to
make a capability part of the platform.

## Evaluating changes

A proposed feature or architectural change should answer:

1. Which supported use case does it improve?
2. Is the responsibility application policy, durable domain state, or
   operational host state?
3. Can the same result be achieved with immutable context, SQLite, an external
   service, or a Roc package?
4. Does it introduce hidden process-local state or ordering between handlers?
5. Are memory, concurrency, queueing, and shutdown semantics enforceable by the
   host rather than convention?
6. Who owns each resource, what bounds it, how does it saturate, and when is it
   released?
7. Can debug hosts assert its ownership and lifecycle invariants without
   adding equivalent bookkeeping to release hosts?
8. Is resource use finite under malicious input and overload?
9. Does it reduce or add allocations, boundary crossings, or payload copies on
   the common request path, and can seamless slices or ownership transfer avoid
   those copies?
10. Can it provide the same contract on every supported target?
11. Does it make ordinary applications simpler, or make every application pay
   for a specialized use case?
12. Does it move the platform toward one of its explicit non-goals?

A change that expands scope should require a concrete use case and evidence
that the new responsibility can be supported without weakening the platform's
correctness, boundedness, performance, ergonomics, or cross-platform contract.
