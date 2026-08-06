# Typed SSE and Datastar

`basic-webserver` supports first-class server-sent event responses through a
typed functional source. Roc owns application state and event construction;
the host owns admission, timers, transport backpressure, HTTP framing, Brotli,
cancellation, and shutdown.

## Application API

Return `Server.stream` with a source created by `Sse.unfold!`:

```roc
respond! = |request, context| {
	user_id = authorize!(request, context)?
	initial = { user_id, revision: 0 }

	source = Sse.unfold!(initial, |state| {
		# The transition is an ordinary Roc closure, so it can use immutable
		# Context fields without putting them in the changing state record.
		view = load_view!(context.db, state.user_id)?

		Ok(Emit({
			event: Datastar.patch_elements(render(view)),
			state: { ..state, revision: view.revision },
			wake: After(500),
		}))
	})

	Ok(Server.stream(source))
}
```

One transition returns:

- `Emit({ event, state, wake })`: send one completely framed event, then retain
  the next state;
- `Wait({ state, wake })`: retain the next state without emitting;
- `End`: finish the response cleanly; or
- `Err(err)`: fail the source.

`Immediately` makes the next transition ready after the current event has
drained into host-owned frames. `After(milliseconds)` parks it on a host timer;
the maximum wait is 24 hours, and a larger value fails the source.
The application does not receive the host's wake-generation counter, a socket,
a writer, a task, or a cancellation callback.

The transition closure may retain ordinary immutable Roc values and
server-lifetime capabilities from `Context`. Request-scoped capabilities are
not valid retained state: in particular, a request `Server.Body` expires when
`respond!` returns, before the precommit transition runs. Prefer small IDs,
versions, and durable cursors as changing state, then query SQLite or another
context capability on each transition. The host bounds each admitted source
slot but does not trace or byte-quota the transitive Roc heap captured by
trusted application code.

## Commitment and failures

The host reserves the stream and selected Brotli capacity and executes exactly
one transition before committing `200 text/event-stream`.

- Initial admission failure or queue timeout returns `503`.
- If neither identity nor Brotli is acceptable, the host returns `406`.
- An initial Roc panic, application error, or oversized event is logged and
  returns the ordinary bounded `500` response.
- A successful initial `Emit`, `Wait`, or `End` commits the SSE response.

After commitment, HTTP cannot change the response status. A later transition,
framing, or compression failure is logged and terminates that stream. It does
not affect other requests.

Exactly one transition runs for a stream at a time. The next transition cannot
begin until the current event has copied into identity frames or completely
flushed into Brotli frames owned by the host. This is bounded host acceptance,
not proof that the peer displayed or even received the event. HTTP/1.1 socket
backpressure and HTTP/2 flow control naturally stop the source from running
ahead of a slow reader.

Disconnect cancels parked and queued transitions immediately. A synchronous
transition that is already running cannot be safely preempted: it remains
request- and handler-accounted until it returns, and its result is then dropped.
Graceful shutdown uses the same rule before invoking `shutdown!`.

## Limits and operations

The defaults admit 256 SSE responses and allow one framed event up to 1 MiB.
They are independent from the 32 active Roc handlers because parked streams do
not occupy handler workers:

```roc
config = Server.default_config
	.with_sse_limits({
		max_streams: 1024,
		max_event_bytes: 256 * 1024,
	})
```

`max_streams` and `max_event_bytes` must be non-zero; the event limit cannot
exceed 16 MiB. Stream saturation returns `503` before commitment. Ordinary
handlers and ready SSE transitions share the configured fixed Roc worker pool
and FIFO queue, including its queue timeout.

An SSE request remains active for metrics, access logging, response-idle
timeout, and graceful drain until its body ends, fails, or is cancelled. Parked
time is therefore part of request duration. Active-handler metrics include only
the initial handler or a currently executing transition, never a parked source.
Every transition contributes to the bounded Roc-handler duration histogram;
the access-log handler fields describe the initial `respond!` call, while its
overall request duration includes the complete stream lifetime.

The OpenMetrics endpoint also exports current and high-water gauges for
admitted SSE streams, leased Brotli lanes, queued Brotli operations, and
running Brotli operations under the `basic_webserver_sse_*` namespace. These
distinguish stream-slot pressure from compression pressure when a request is
rejected before commitment.

## Content coding

The response always uses host-owned canonical headers:

```text
Content-Type: text/event-stream
Cache-Control: no-cache
Vary: Accept-Encoding
```

The host negotiates identity or streaming Brotli from `Accept-Encoding`; Brotli
uses the bounded scale profile and is transparent to Roc. Every logical event
is flushed. Normal end writes a valid Brotli finish; disconnect abandons the
encoder without pretending the response ended cleanly. The same contract is
used over HTTP/1.1 and HTTP/2.

## Event and Datastar constructors

`Sse.Event.data` constructs a generic data event. `Sse.Event.named` constructs
a named event from data values. Use `Sse.Event.named_with` with
`Sse.default_event_options` for reconnect metadata. `Sse.event_id` validates
that an ID contains no NUL or line ending, `Sse.clear_event_id` emits an empty
`id:`, and `Sse.retry_after` supplies the retry delay.

`Datastar` owns the two stable Datastar wire event names and their data keys:

- `patch_elements` and `patch_elements_with`;
- `remove_elements` and `remove_elements_with`; and
- `patch_signals` and `patch_signals_with`.

The option records cover selectors, all patch modes, HTML/SVG/MathML
namespaces, view-transition targets, `onlyIfMissing`, event ID, and retry. Start
from the matching `default_*_options` record so later compatible fields do not
force manual record construction. Signal values remain JSON strings because
the platform does not choose an application JSON model.

The experimental `DatastarMarkup` companion adds typed signals, expressions,
actions, request targets, and patch targets over this wire API. Its current
guarantees and deliberate limits are recorded in the
[typed markup feasibility report](research/datastar-typed-markup-spike.md).

## Deliberately deferred optimizations

The current hot transition transfers one complete Roc-framed event allocation
into host-owned frames without additional host allocations per event. Two
possible optimizations are deliberately outside the accepted implementation:

- sharing response-frame capacity only among currently active streams; and
- replacing the complete Roc event with a structured host-framing ABI.

Neither changes the application API or is required for bounded, correct SSE.
They should be reconsidered only with evidence that parked-stream memory or the
remaining Roc event allocation matters for a target workload.

The maintained SSE capacity, fairness, timing, memory, and allocation scenarios
are described in [the benchmarking guide](benchmarking.md). The earlier Roc/Go
comparison remains available in repository history.
