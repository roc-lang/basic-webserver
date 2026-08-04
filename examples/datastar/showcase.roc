## Reproduces the public non-Rocket Datastar examples as executable Roc API probes.
app [Context, program] {
	pf: platform "../../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Datastar
import pf.Server
import pf.Sse
import http.Response
import "datastar-v1.0.2.js" as datastar_js : List(U8)

Context : {}

ActiveSearchSignals : { activeSearch : Str }

ViewTransitionSignals : { shouldRestore : Bool }

Contact : { first : Str, last : Str, search : Str }

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

	match (request.method(), path) {
		(GET, "/") => Ok(Server.respond(html_response(index_page)))
		(GET, "/datastar.js") => Ok(Server.respond(javascript_response(datastar_js)))
		(GET, "/examples/active_search") => Ok(Server.respond(html_response(active_search_page)))
		(GET, "/examples/active_search/search") => active_search!(request)
		(GET, "/examples/animations") => Ok(Server.respond(html_response(animations_page)))
		(GET, "/examples/animations/throb") => Ok(Server.stream(Sse.unfold!(0, throb_transition!)))
		(GET, "/examples/animations/view_transition") => view_transition!(request)
		(DELETE, "/examples/animations") => Ok(Server.stream(Sse.unfold!(0, fade_out_transition!)))
		(GET, "/examples/animations/fade_me_in") => Ok(Server.stream(Sse.unfold!(0, fade_in_transition!)))
		(GET, "/examples/bad_apple") => Ok(Server.respond(html_response(bad_apple_page)))
		(GET, "/examples/bad_apple/updates") => Ok(Server.stream(Sse.unfold!(0, bad_apple_transition!)))
		_ => Ok(Server.respond(text_response(404, "Example not found")))
	}
}

active_search! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
active_search! = |request| {
	signals_result : Try(ActiveSearchSignals, Datastar.SignalsError)
	signals_result = Datastar.read_signals!(request)
	signals =
		match signals_result {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(text_response(400, "Invalid Datastar signals: ${Str.inspect(err)}")))
		}

	Ok(Datastar.respond([Datastar.patch_elements(active_search_demo(signals.activeSearch))]))
}

view_transition! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
view_transition! = |request| {
	signals_result : Try(ViewTransitionSignals, Datastar.SignalsError)
	signals_result = Datastar.read_signals!(request)
	signals =
		match signals_result {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(text_response(400, "Invalid Datastar signals: ${Str.inspect(err)}")))
		}

	next = Bool.not(signals.shouldRestore)
	label = if next {
		"Restore It!"
	} else {
		"Swap It!"
	}
	next_json = if next {
		"true"
	} else {
		"false"
	}
	element =
		\\<button id="view-transition" data-signals="{shouldRestore: ${next_json}}" data-on:click="@get('/examples/animations/view_transition')">${label}</button>

	Ok(
		Datastar.respond([
			Datastar.patch_elements_with(
				element,
				{ ..Datastar.default_patch_elements_options, view_transition: ViewTransition(CurrentTarget) },
			),
		]),
	)
}

throb_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
throb_transition! = |state| {
	style =
		match state % 4 {
			0 => { foreground: "blue", background: "orange" }
			1 => { foreground: "orange", background: "gray" }
			2 => { foreground: "gray", background: "red" }
			_ => { foreground: "red", background: "blue" }
		}
	element =
		\\<div id="throb" style="color: var(--${style.foreground}-8); background-color: var(--${style.background}-5)" data-init="@get('/examples/animations/throb')">${style.foreground} on ${style.background}</div>

	Ok(
		Emit({
			event: Datastar.patch_elements(element),
			state: state + 1,
			wake: After(1000),
		}),
	)
}

fade_out_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
fade_out_transition! = |state|
	match state {
		0 => Ok(
			Emit({
				event: Datastar.patch_elements(fade_out_button(" style=\"transition: opacity 1s ease-out; opacity: 0\" disabled")),
				state: 1,
				wake: After(1000),
			}),
		)
		1 => Ok(
			Emit({
				event: Datastar.patch_elements("<div id=\"fade-out-swap\"></div>"),
				state: 2,
				wake: After(1000),
			}),
		)
		2 => Ok(Emit({ event: Datastar.patch_elements(fade_out_button("")), state: 3, wake: Immediately }))
		_ => Ok(End)
	}

fade_in_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
fade_in_transition! = |state|
	match state {
		0 => Ok(
			Emit({
				event: Datastar.patch_elements(fade_in_button(" style=\"opacity: 0\" disabled")),
				state: 1,
				wake: After(1000),
			}),
		)
		1 => Ok(Emit({ event: Datastar.patch_elements(fade_in_button(" style=\"transition: opacity 1s ease-out\"")), state: 2, wake: Immediately }))
		_ => Ok(End)
	}

fade_out_button : Str -> Str
fade_out_button = |attributes|
	\\<button id="fade-out-swap"${attributes} data-on:click="@delete('/examples/animations')">Fade out then delete on click</button>

fade_in_button : Str -> Str
fade_in_button = |attributes|
	\\<button id="fade-me-in"${attributes} data-on:click="@get('/examples/animations/fade_me_in')">Fade me in on click</button>

bad_apple_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
bad_apple_transition! = |frame_index| {
	if frame_index >= 60 {
		return Ok(End)
	}
	percentage = ((frame_index + 1) * 100) // 60
	signals = Json.to_str({ percentage, contents: bad_apple_frame(frame_index) })
	Ok(
		Emit({
			event: Datastar.patch_signals(signals),
			state: frame_index + 1,
			wake: After(33),
		}),
	)
}

bad_apple_frame : U64 -> Str
bad_apple_frame = |frame_index|
	match frame_index % 4 {
		0 =>
			\\          ██
			\\        ██████
			\\      ██████████
			\\    ██████████████
			\\      ██████████
			\\        ██████
			\\          ██
		1 =>
			\\      ██████████
			\\    ████      ████
			\\  ████          ████
			\\  ████    ██    ████
			\\  ████          ████
			\\    ████      ████
			\\      ██████████
		2 =>
			\\  ██████████████████
			\\  ████          ████
			\\  ████  ██████  ████
			\\  ████  ██████  ████
			\\  ████          ████
			\\  ██████████████████
			\\
		_ =>
			\\██████████████████████
			\\████              ████
			\\████    ██████    ████
			\\████    ██████    ████
			\\████              ████
			\\██████████████████████
			\\██████████████████████
		}

contacts : List(Contact)
contacts = [
	{ first: "Abraham", last: "Jakubowski", search: "abraham jakubowski" },
	{ first: "Adriel", last: "Glover", search: "adriel glover" },
	{ first: "Agustin", last: "Leannon", search: "agustin leannon" },
	{ first: "Aimee", last: "Breitenberg", search: "aimee breitenberg" },
	{ first: "Alana", last: "Dach", search: "alana dach" },
	{ first: "Alayna", last: "Fay", search: "alayna fay" },
	{ first: "Albertha", last: "Rodriguez", search: "albertha rodriguez" },
	{ first: "Alek", last: "Grimes", search: "alek grimes" },
	{ first: "Alexandria", last: "Reichert", search: "alexandria reichert" },
	{ first: "Alfreda", last: "Kozey", search: "alfreda kozey" },
	{ first: "Bryana", last: "Bernier", search: "bryana bernier" },
	{ first: "Jensen", last: "Kassulke", search: "jensen kassulke" },
	{ first: "Amparo", last: "O'Keefe", search: "amparo o'keefe" },
	{ first: "Cornell", last: "Price", search: "cornell price" },
	{ first: "William", last: "Ankunding", search: "william ankunding" },
]

active_search_demo : Str -> Str
active_search_demo = |query| {
	needle = ascii_lower(query)
	matching =
		if needle.is_empty() {
			contacts
		} else {
			contacts.keep_if(|contact| Str.contains(contact.search, needle))
		}
	rows =
		Str.join_with(
			matching.map(|contact| "<tr><td>${contact.first}</td><td>${contact.last}</td></tr>"),
			"",
		)

	\\<div id="demo">
	\\    <input type="text" placeholder="Search..." data-bind:active-search data-on:input__debounce.200ms="@get('/examples/active_search/search')">
	\\    <table>
	\\        <thead><tr><th>First Name</th><th>Last Name</th></tr></thead>
	\\        <tbody>${rows}</tbody>
	\\    </table>
	\\</div>
}

page : Str, Str -> Str
page = |title, content|
	\\<!doctype html>
	\\<html lang="en">
	\\<head>
	\\    <meta charset="utf-8">
	\\    <meta name="viewport" content="width=device-width, initial-scale=1">
	\\    <title>${title} · Roc + Datastar</title>
	\\    <script type="module" src="/datastar.js"></script>
	\\    <style>
	\\        :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
	\\        body { max-width: 54rem; margin: 3rem auto; padding: 0 1rem; }
	\\        nav { display: flex; gap: 1rem; margin-bottom: 2rem; }
	\\        fieldset { padding: 1.5rem; }
	\\        input { width: min(24rem, 100%); padding: .65rem; }
	\\        table { width: 100%; margin-top: 1rem; border-collapse: collapse; }
	\\        th, td { text-align: left; padding: .5rem; border-bottom: 1px solid #8886; }
	\\        code { background: #8882; padding: .1rem .3rem; }
	\\        #throb { padding: 2rem; transition: color 1s, background-color 1s; }
	\\    </style>
	\\</head>
	\\<body>
	\\    <nav><a href="/">All examples</a><a href="https://data-star.dev/examples/" rel="noreferrer">Datastar originals</a></nav>
	\\    ${content}
	\\</body>
	\\</html>

index_page : Str
index_page = page(
	"Examples",
	\\<h1>Roc + Datastar examples</h1>
	\\<p>Executable reproductions used to evaluate basic-webserver's Datastar API.</p>
	\\<ol><li><a href="/examples/active_search">Active Search</a></li><li><a href="/examples/animations">Animations</a></li><li><a href="/examples/bad_apple">Bad Apple</a></li></ol>
	,
)

active_search_page : Str
active_search_page = page(
	"Active Search",
	\\<h1>Active Search</h1>
	\\<p>Searches a server-owned contact list as the bound signal changes.</p>
	\\<fieldset><legend>Demo</legend>${active_search_demo("")}</fieldset>
	\\<h2>What this validates</h2>
	\\<p><code>Datastar.read_signals!</code> decodes GET query signals and <code>Datastar.respond</code> returns a finite typed patch without occupying a retained-stream slot.</p>
	,
)

animations_page : Str
animations_page = page(
	"Animations",
	\\<h1>Animations</h1>
	\\<p>Stable element IDs let CSS and the View Transitions API animate server-driven patches.</p>
	\\<h2>Color Throb</h2>
	\\<fieldset><legend>Demo</legend><div id="throb" style="color: var(--brown-8); background-color: var(--orange-5)" data-init="@get('/examples/animations/throb')">brown on orange</div></fieldset>
	\\<h2>View Transitions</h2>
	\\<fieldset><legend>Demo</legend><button id="view-transition" data-signals="{shouldRestore: false}" data-on:click="@get('/examples/animations/view_transition')">Swap It!</button></fieldset>
	\\<h2>Fade Out On Swap</h2>
	\\<fieldset><legend>Demo</legend>${fade_out_button("")}</fieldset>
	\\<h2>Fade In On Addition</h2>
	\\<fieldset><legend>Demo</legend>${fade_in_button(" style=\"transition: opacity 1s ease-out\"")}</fieldset>
	\\<h2>What this validates</h2>
	\\<p>One page composes finite view-transition responses with host-scheduled timer streams and delayed multi-event transitions.</p>
	,
)

bad_apple_page : Str
bad_apple_page = page(
	"Bad Apple",
	\\<h1>Bad Apple</h1>
	\\<p>A compact 30fps ASCII animation driven entirely by signal patches.</p>
	\\<fieldset><legend>Demo</legend>
	\\    <div id="bad-apple" data-signals="{percentage: 0, contents: 'frames loading'}" data-init="@get('/examples/bad_apple/updates')">
	\\        <label><span data-text="'Percentage: ' + $percentage + '%'"></span><input type="range" min="0" max="100" disabled data-attr:value="$percentage"></label>
	\\        <pre data-text="$contents">frames loading</pre>
	\\    </div>
	\\</fieldset>
	\\<h2>What this validates</h2>
	\\<p>A bounded retained source emits 60 typed signal patches at roughly 30fps; the browser updates existing elements without server-rendering HTML for each frame.</p>
	,
)

ascii_lower : Str -> Str
ascii_lower = |value|
	Str.from_utf8_lossy(
		Str.to_utf8(value).map(
			|byte|
				if byte >= 65 and byte <= 90 {
					byte + 32
				} else {
					byte
				},
		),
	)

html_response : Str -> Response
html_response = |body|
	Response.from_status(200)
		.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
		.with_body(Str.to_utf8(body))

javascript_response : List(U8) -> Response
javascript_response = |body|
	Response.from_status(200)
		.with_headers([{ name: "Content-Type", value: "text/javascript; charset=utf-8" }])
		.with_body(body)

text_response : U16, Str -> Response
text_response = |status, body|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
		.with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
