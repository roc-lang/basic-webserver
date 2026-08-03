app [Context, program] {
	pf: platform "../../platform/main.roc",
}

import pf.Datastar
import pf.Server
import pf.Sse

# This application is intentionally fixed-shape. The Go reference server uses
# the same route matrix, payload generator, event counts, and timer schedule so
# the external driver does not benchmark request parsing or configuration.

Context : {}

StreamState : {
	delay_millis : U64,
	dynamic_payload : Bool,
	payload_bytes : U64,
	prepared_html : Str,
	remaining : U64,
	sequence : U64,
}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
	Ok({
		config: Server.with_limits(
			Server.default_config,
			{
				max_connections: 512,
				max_handlers: 64,
				max_queued_handlers: 64,
			},
		),
		context: {},
	})

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context| {
	raw_path =
		match request.target() {
			Resource({ raw_path: path, .. }) => path
			_ => ""
		}

	state =
		match raw_path {
			"/finite" => dynamic_state(1, 256, 0)
			"/progressive" => dynamic_state(3, 256, 100)
			"/hot-100" => dynamic_state(100, 256, 0)
			"/hot-1000" => dynamic_state(1000, 256, 0)
			"/hot-10000" => dynamic_state(10000, 256, 0)
			"/hot-4096" => dynamic_state(2000, 4096, 0)
			"/hot-65536" => dynamic_state(200, 65536, 0)
			"/transport-256" => prepared_state(10000, 256)
			"/transport-100" => prepared_state(100, 256)
			"/transport-1000" => prepared_state(1000, 256)
			"/transport-4096" => prepared_state(2000, 4096)
			"/transport-65536" => prepared_state(200, 65536)
			"/idle" => dynamic_state(1000000, 256, 60000)
			_ => dynamic_state(1, 256, 0)
		}

	Ok(Server.stream(Sse.unfold!(state, transition!)))
}

transition! : StreamState, U64 => Try(Sse.Step(StreamState), [StreamFailed(Str)])
transition! = |state, _wake_generation|
	if state.remaining == 0 {
		Ok(End)
	} else {
		html =
			if state.dynamic_payload {
				html_payload(state.payload_bytes, state.sequence)
			} else {
				state.prepared_html
			}
		next_state = {
			..state,
			remaining: state.remaining - 1,
			sequence: state.sequence + 1,
		}
		wake =
			if state.delay_millis == 0 or state.remaining == 1 {
				Immediately
			} else {
				After(state.delay_millis)
			}
		Ok(Emit({ event: Datastar.patch_elements(html), state: next_state, wake }))
	}

dynamic_state : U64, U64, U64 -> StreamState
dynamic_state = |remaining, payload_bytes, delay_millis| {
	delay_millis,
	dynamic_payload: Bool.True,
	payload_bytes,
	prepared_html: "",
	remaining,
	sequence: 1,
}

prepared_state : U64, U64 -> StreamState
prepared_state = |remaining, payload_bytes| {
	delay_millis: 0,
	dynamic_payload: Bool.False,
	payload_bytes,
	prepared_html: html_payload(payload_bytes, 1),
	remaining,
	sequence: 1,
}

html_payload : U64, U64 -> Str
html_payload = |target_bytes, sequence| {
	prefix = "<article id=\"feed\" data-seq=\"${U64.to_str(sequence)}\"><p>"
	suffix = "</p></article>"
	fixed_bytes = Str.count_utf8_bytes(prefix) + Str.count_utf8_bytes(suffix)
	padding =
		if target_bytes > fixed_bytes {
			Str.repeat("x", target_bytes - fixed_bytes)
		} else {
			""
		}
	Str.with_capacity(target_bytes)
		.concat(prefix)
		.concat(padding)
		.concat(suffix)
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
