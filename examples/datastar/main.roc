## Reproduces the public non-Rocket Datastar examples as executable Roc API probes.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	roc: "nightly-2026-08-22-db56022",
}

import ./components/ClickToLoad
import ./components/BulkUpdate
import ./components/ClickToEdit
import ./components/Animations
import ./components/BrowserExamples
import ./components/CrudExamples
import ./components/LoadingExamples
import ./components/TodoMvc
import ./Datastar
import pf.Attribute
import pf.Html
import pf.Server
import pf.Sse
import http.Response
import "datastar-v1.0.2.js" as datastar_js : List(U8)

Context : {}

ActiveSearchSignals : { activeSearch : Str }

Contact : { first : Str, last : Str, search : Str }

click_to_load : ClickToLoad
click_to_load = ClickToLoad.default

bulk_update : BulkUpdate
bulk_update = BulkUpdate.default

click_to_edit : ClickToEdit
click_to_edit = ClickToEdit.default

animations : Animations
animations = Animations.default

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.with_request_body_limit(Server.default_config, 2 * 1024 * 1024), context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context| {
	path =
		match request.target() {
			Resource({ raw_path, .. }) => raw_path
			_ => ""
		}
	_ =
		match bulk_update.respond!(request, path) {
			Ok(Handled(outcome)) => return Ok(outcome)
			Err(err) => return Err(err)
			Ok(NotHandled) => {}
		}
	_ =
		match click_to_edit.respond!(request, path) {
			Ok(Handled(outcome)) => return Ok(outcome)
			Err(err) => return Err(err)
			Ok(NotHandled) => {}
		}
	_ =
		match animations.respond!(request, path) {
			Ok(Handled(outcome)) => return Ok(outcome)
			Err(err) => return Err(err)
			Ok(NotHandled) => {}
		}
	_ =
		match CrudExamples.respond!(request, path) {
			Ok(Handled(outcome)) => return Ok(outcome)
			Err(err) => return Err(err)
			Ok(NotHandled) => {}
		}
	_ =
		match LoadingExamples.respond!(request, path) {
			Ok(Handled(outcome)) => return Ok(outcome)
			Err(err) => return Err(err)
			Ok(NotHandled) => {}
		}
	_ =
		match TodoMvc.respond!(request, path) {
			Ok(Handled(outcome)) => return Ok(outcome)
			Err(err) => return Err(err)
			Ok(NotHandled) => {}
		}

	if click_to_load.more_target().matches(request.method(), path) {
		click_to_load.more!(request)
	} else if click_to_load.page_target().matches(request.method(), path) {
		Ok(click_to_load.page())
	} else match (request.method(), path) {
		(GET, "/") => Ok(Server.respond(html_response(index_page)))
		(GET, "/datastar.js") => Ok(Server.respond(javascript_response(datastar_js)))
		(GET, "/examples/active_search") => Ok(Server.respond(html_response(active_search_page)))
		(GET, "/examples/active_search/search") => active_search!(request)
		(GET, "/examples/bad_apple") => Ok(Server.respond(html_response(bad_apple_page)))
		(GET, "/examples/bad_apple/updates") => Ok(Server.stream(Sse.unfold!(0, bad_apple_transition!)))
		(GET, "/examples/custom_event") => Ok(BrowserExamples.custom_event())
		(GET, "/examples/custom_plugin") => Ok(BrowserExamples.custom_plugin())
		(GET, "/examples/event_bubbling") => Ok(BrowserExamples.event_bubbling())
		(GET, "/examples/on_signal_patch") => Ok(BrowserExamples.on_signal_patch())
		(GET, "/examples/sortable") => Ok(BrowserExamples.sortable())
		(GET, "/examples/web_component") => Ok(BrowserExamples.web_component())
		(GET, "/examples/match_media") => Ok(BrowserExamples.match_media())
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
	\\        input[type="checkbox"] { width: auto; }
	\\        button { margin: 1rem .5rem 0 0; padding: .65rem 1rem; }
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
	\\<p>Executable reproductions used to evaluate one Roc Datastar integration.</p>
	\\<ol>
	\\    <li><a href="/examples/active_search">Active Search</a></li>
	\\    <li><a href="/examples/animations">Animations</a></li>
	\\    <li><a href="/examples/bad_apple">Bad Apple</a></li>
	\\    <li><a href="/examples/bulk_update">Bulk Update</a></li>
	\\    <li><a href="/examples/click_to_edit">Click To Edit</a></li>
	\\    <li><a href="/examples/click_to_load">Click To Load</a></li>
	\\    <li><a href="/examples/custom_event">Custom Event</a></li>
	\\    <li><a href="/examples/custom_plugin">Custom Plugin</a></li>
	\\    <li><a href="/examples/dbmon">DBmon</a></li>
	\\    <li><a href="/examples/delete_row">Delete Row</a></li>
	\\    <li><a href="/examples/edit_row">Edit Row</a></li>
	\\    <li><a href="/examples/event_bubbling">Event Bubbling</a></li>
	\\    <li><a href="/examples/file_upload">File Upload</a></li>
	\\    <li><a href="/examples/form_data">Form Data</a></li>
	\\    <li><a href="/examples/infinite_scroll">Infinite Scroll</a></li>
	\\    <li><a href="/examples/inline_validation">Inline Validation</a></li>
	\\    <li><a href="/examples/lazy_load">Lazy Load</a></li>
	\\    <li><a href="/examples/lazy_tabs">Lazy Tabs</a></li>
	\\    <li><a href="/examples/on_signal_patch">On Signal Patch</a></li>
	\\    <li><a href="/examples/progress_bar">Progress Bar</a></li>
	\\    <li><a href="/examples/progressive_load">Progressive Load</a></li>
	\\    <li><a href="/examples/sortable">Sortable</a></li>
	\\    <li><a href="/examples/svg_morphing">SVG Morphing</a></li>
	\\    <li><a href="/examples/templ_counter">Templ Counter</a></li>
	\\    <li><a href="/examples/title_update">Title Update</a></li>
	\\    <li><a href="/examples/todomvc">TodoMVC</a></li>
	\\    <li><a href="/examples/web_component">Web Component</a></li>
	\\    <li><a href="/examples/match_media">Match Media</a></li>
	\\</ol>
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
