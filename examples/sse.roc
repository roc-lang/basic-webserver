## Streams typed SSE events from a retained Roc state machine. The host owns
## callback admission, timer scheduling, output framing, and cancellation.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	roc: "nightly-2026-08-23-fb208ba",
}

import pf.Server
import pf.Sse

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context| {
	path =
		match request.target() {
			Resource({ raw_path, .. }) => raw_path
			_ => ""
		}
	match path {
		"/error-first" => Ok(Server.stream(Sse.unfold!({}, |_state| Err(StreamFailed("initial transition failed")))))
		"/end-first" => Ok(Server.stream(Sse.unfold!({}, |_state| Ok(End))))
		"/wait-first" => Ok(Server.stream(Sse.unfold!(0, wait_first_transition!)))
		"/long-wait-first" => Ok(Server.stream(Sse.unfold!(0, long_wait_first_transition!)))
		"/oversize-first" => Ok(Server.stream(Sse.unfold!({}, |_state| Ok(Emit({ event: Sse.Event.data(Str.repeat("x", 1024 * 1024)), state: {}, wake: Immediately })))))
		"/options" => Ok(Server.stream(Sse.unfold!(0, options_transition!)))
		_ => Ok(Server.stream(Sse.unfold!(0, transition!)))
	}
}

options_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
options_transition! = |state| {
	id =
		match Sse.event_id("event${U64.to_str(state)}") {
			Ok(valid) => valid
			Err(_) => Sse.clear_event_id
		}
	event_options = {
		..Sse.default_event_options,
		id,
		retry: Sse.retry_after(2000),
	}
	match state {
		0 => Ok(
			Emit({
				event: Sse.Event.named_with(
					"view-update",
					["target div", "namespace svg", "payload <svg>Merge</svg>"],
					event_options,
				),
				state: 1,
				wake: Immediately,
			}),
		)
		1 => Ok(
			Emit({
				event: Sse.Event.named(
					"state-update",
					["only-if-missing true", "payload {\"one\":1}"],
				),
				state: 2,
				wake: Immediately,
			}),
		)
		2 => Ok(
			Emit({
				event: Sse.Event.named("remove-view", ["target #target"]),
				state: 3,
				wake: Immediately,
			}),
		)
		_ => Ok(End)
	}
}

wait_first_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
wait_first_transition! = |state|
	match state {
		0 => Ok(Wait({ state: 1, wake: After(20) }))
		1 => Ok(Emit({ event: Sse.Event.data("after initial wait"), state: 2, wake: Immediately }))
		_ => Ok(End)
	}

long_wait_first_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
long_wait_first_transition! = |state|
	match state {
		0 => Ok(Wait({ state: 1, wake: After(500) }))
		1 => Ok(Emit({ event: Sse.Event.data("after long initial wait"), state: 2, wake: Immediately }))
		_ => Ok(End)
	}

transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
transition! = |state|
	match state {
		0 => Ok(Emit({ event: Sse.Event.keyed("view-update", "html", "<div id=\"stage\">A</div>"), state: 1, wake: After(50) }))
		1 => Ok(Emit({ event: Sse.Event.keyed("state-update", "json", "{\"stage\":\"B\"}"), state: 2, wake: Immediately }))
		2 => Ok(Wait({ state: 3, wake: After(20) }))
		3 => Ok(Emit({ event: Sse.Event.keyed("view-update", "html", "<pre id=\"large\">${Str.repeat("x", 20000)}</pre>"), state: 4, wake: Immediately }))
		4 => Ok(Emit({ event: Sse.Event.keyed("view-update", "html", "<div id=\"stage\">done</div>"), state: 5, wake: Immediately }))
		5 => Ok(End)
		_ => Err(StreamFailed("invalid retained source state"))
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
