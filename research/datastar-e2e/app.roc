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
	payload_mode : [Assemble, Dynamic, Prepared, RepeatOnly],
	payload_bytes : U64,
	prepared_html : Str,
	prepared_padding : Str,
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
			"/repeat-100" => repeat_only_state(100, 256)
			"/repeat-1000" => repeat_only_state(1000, 256)
			"/repeat-256" => repeat_only_state(10000, 256)
			"/repeat-4096" => repeat_only_state(2000, 4096)
			"/repeat-65536" => repeat_only_state(200, 65536)
			"/assemble-100" => assemble_state(100, 256)
			"/assemble-1000" => assemble_state(1000, 256)
			"/assemble-256" => assemble_state(10000, 256)
			"/assemble-4096" => assemble_state(2000, 4096)
			"/assemble-65536" => assemble_state(200, 65536)
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
			match state.payload_mode {
				Dynamic => html_payload(state.payload_bytes, state.sequence)
				RepeatOnly => Str.repeat("x", state.payload_bytes)
				Assemble => html_payload_with_padding(state.prepared_padding, state.sequence)
				Prepared => state.prepared_html
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
	payload_mode: Dynamic,
	payload_bytes,
	prepared_html: "",
	prepared_padding: "",
	remaining,
	sequence: 1,
}

repeat_only_state : U64, U64 -> StreamState
repeat_only_state = |remaining, payload_bytes| {
	delay_millis: 0,
	payload_mode: RepeatOnly,
	payload_bytes,
	prepared_html: "",
	prepared_padding: "",
	remaining,
	sequence: 1,
}

assemble_state : U64, U64 -> StreamState
assemble_state = |remaining, payload_bytes| {
	delay_millis: 0,
	payload_mode: Assemble,
	payload_bytes,
	prepared_html: "",
	prepared_padding: payload_padding(payload_bytes, 1),
	remaining,
	sequence: 1,
}

prepared_state : U64, U64 -> StreamState
prepared_state = |remaining, payload_bytes| {
	delay_millis: 0,
	payload_mode: Prepared,
	payload_bytes,
	prepared_html: html_payload(payload_bytes, 1),
	prepared_padding: "",
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

payload_padding : U64, U64 -> Str
payload_padding = |target_bytes, sequence| {
	prefix = "<article id=\"feed\" data-seq=\"${U64.to_str(sequence)}\"><p>"
	suffix = "</p></article>"
	fixed_bytes = Str.count_utf8_bytes(prefix) + Str.count_utf8_bytes(suffix)
	if target_bytes > fixed_bytes {
		Str.repeat("x", target_bytes - fixed_bytes)
	} else {
		""
	}
}

html_payload_with_padding : Str, U64 -> Str
html_payload_with_padding = |padding, sequence| {
	prefix = "<article id=\"feed\" data-seq=\"${U64.to_str(sequence)}\"><p>"
	suffix = "</p></article>"
	target_bytes = Str.count_utf8_bytes(prefix) + Str.count_utf8_bytes(padding) + Str.count_utf8_bytes(suffix)
	Str.with_capacity(target_bytes)
		.concat(prefix)
		.concat(padding)
		.concat(suffix)
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
