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
	payload_bytes : U64,
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
			"/finite" => { delay_millis: 0, payload_bytes: 256, remaining: 1, sequence: 1 }
			"/progressive" => { delay_millis: 100, payload_bytes: 256, remaining: 3, sequence: 1 }
			"/hot-100" => { delay_millis: 0, payload_bytes: 256, remaining: 100, sequence: 1 }
			"/hot-1000" => { delay_millis: 0, payload_bytes: 256, remaining: 1000, sequence: 1 }
			"/hot-10000" => { delay_millis: 0, payload_bytes: 256, remaining: 10000, sequence: 1 }
			"/hot-4096" => { delay_millis: 0, payload_bytes: 4096, remaining: 2000, sequence: 1 }
			"/hot-65536" => { delay_millis: 0, payload_bytes: 65536, remaining: 200, sequence: 1 }
			"/idle" => { delay_millis: 60000, payload_bytes: 256, remaining: 1000000, sequence: 1 }
			_ => { delay_millis: 0, payload_bytes: 256, remaining: 1, sequence: 1 }
		}

	Ok(Server.stream(Sse.unfold!(state, transition!)))
}

transition! : StreamState, U64 => Try(Sse.Step(StreamState), [StreamFailed(Str)])
transition! = |state, _wake_generation|
	if state.remaining == 0 {
		Ok(End)
	} else {
		html = html_payload(state.payload_bytes, state.sequence)
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
	"${prefix}${padding}${suffix}"
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
