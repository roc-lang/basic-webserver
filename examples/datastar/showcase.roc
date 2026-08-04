## Reproduces the public non-Rocket Datastar examples as executable Roc API probes.
app [Context, program] {
	pf: platform "../../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import ./components/ClickToLoad
import ./components/BulkUpdate
import pf.Datastar
import pf.Attribute
import pf.Html
import pf.Server
import pf.Sse
import http.Response
import "datastar-v1.0.2.js" as datastar_js : List(U8)

Context : {}

ActiveSearchSignals : { activeSearch : Str }

ViewTransitionSignals : { shouldRestore : Bool }

ClickToEditSignals : {
	email : Str,
	firstName : Str,
	lastName : Str,
	savedEmail : Str,
	savedFirstName : Str,
	savedLastName : Str,
}

ClickToEditContact : { email : Str, firstName : Str, lastName : Str }

Contact : { first : Str, last : Str, search : Str }

click_to_load : ClickToLoad
click_to_load = ClickToLoad.default

bulk_update : BulkUpdate
bulk_update = BulkUpdate.default

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
	_ =
		match bulk_update.respond!(request, path) {
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
		(GET, "/examples/animations") => Ok(Server.respond(html_response(animations_page)))
		(GET, "/examples/animations/throb") => Ok(Server.stream(Sse.unfold!(0, throb_transition!)))
		(GET, "/examples/animations/view_transition") => view_transition!(request)
		(DELETE, "/examples/animations") => Ok(Server.stream(Sse.unfold!(0, fade_out_transition!)))
		(GET, "/examples/animations/fade_me_in") => Ok(Server.stream(Sse.unfold!(0, fade_in_transition!)))
		(GET, "/examples/bad_apple") => Ok(Server.respond(html_response(bad_apple_page)))
		(GET, "/examples/bad_apple/updates") => Ok(Server.stream(Sse.unfold!(0, bad_apple_transition!)))
		(GET, "/examples/click_to_edit") => Ok(Server.respond(html_response(click_to_edit_page)))
		(GET, "/examples/click_to_edit/edit") => Ok(Datastar.respond([Datastar.patch_elements(click_to_edit_form)]))
		(PUT, "/examples/click_to_edit") => click_to_edit_save!(request)
		(GET, "/examples/click_to_edit/cancel") => click_to_edit_cancel!(request)
		(PATCH, "/examples/click_to_edit/reset") => Ok(click_to_edit_reset())
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

click_to_edit_save! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
click_to_edit_save! = |request| {
	signals_result = click_to_edit_signals!(request)
	signals =
		match signals_result {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(text_response(400, "Invalid Click To Edit signals: ${Str.inspect(err)}")))
		}
	contact = { firstName: signals.firstName, lastName: signals.lastName, email: signals.email }
	if contact.firstName.is_empty() or contact.lastName.is_empty() or Bool.not(Str.contains(contact.email, "@")) {
		return Ok(Server.respond(text_response(422, "First name, last name, and a valid email are required")))
	}

	saved = Json.to_str({ savedEmail: contact.email, savedFirstName: contact.firstName, savedLastName: contact.lastName })
	Ok(
		Datastar.respond([
			Datastar.patch_signals(saved),
			Datastar.patch_elements(click_to_edit_view(contact)),
		]),
	)
}

click_to_edit_cancel! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
click_to_edit_cancel! = |request| {
	signals_result = click_to_edit_signals!(request)
	signals =
		match signals_result {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(text_response(400, "Invalid Click To Edit signals: ${Str.inspect(err)}")))
		}
	contact = { firstName: signals.savedFirstName, lastName: signals.savedLastName, email: signals.savedEmail }
	draft = Json.to_str({ email: contact.email, firstName: contact.firstName, lastName: contact.lastName })
	Ok(
		Datastar.respond([
			Datastar.patch_signals(draft),
			Datastar.patch_elements(click_to_edit_view(contact)),
		]),
	)
}

click_to_edit_signals! : Server.Request => Try(ClickToEditSignals, Datastar.SignalsError)
click_to_edit_signals! = |request| {
	result : Try(ClickToEditSignals, Datastar.SignalsError)
	result = Datastar.read_signals!(request)
	result
}

click_to_edit_reset : () -> Server.Outcome
click_to_edit_reset = || {
	contact = click_to_edit_default_contact
	signals = Json.to_str({
		email: contact.email,
		firstName: contact.firstName,
		lastName: contact.lastName,
		savedEmail: contact.email,
		savedFirstName: contact.firstName,
		savedLastName: contact.lastName,
	})
	Datastar.respond([
		Datastar.patch_signals(signals),
		Datastar.patch_elements(click_to_edit_view(contact)),
	])
}

click_to_edit_view : ClickToEditContact -> Str
click_to_edit_view = |contact| {
	first_name = escaped_text(contact.firstName)
	last_name = escaped_text(contact.lastName)
	email =
		Html.render_without_doc_type(
			Html.a([Attribute.href("mailto:${contact.email}")], [Html.text(contact.email)]),
		)

	\\<div id="demo">
	\\    <p>First Name: <span data-field="first-name">${first_name}</span></p>
	\\    <p>Last Name: <span data-field="last-name">${last_name}</span></p>
	\\    <p>Email: <span data-field="email">${email}</span></p>
	\\    <div role="group"><button data-action="edit" data-indicator:_fetching data-attr:disabled="$_fetching" data-on:click="@get('/examples/click_to_edit/edit')">Edit</button><button data-action="reset" data-indicator:_fetching data-attr:disabled="$_fetching" data-on:click="@patch('/examples/click_to_edit/reset')">Reset</button></div>
	\\</div>
}

click_to_edit_form : Str
click_to_edit_form =
	\\<div id="demo">
	\\    <label>First Name <input type="text" data-bind:first-name data-attr:disabled="$_fetching"></label>
	\\    <label>Last Name <input type="text" data-bind:last-name data-attr:disabled="$_fetching"></label>
	\\    <label>Email <input type="email" data-bind:email data-attr:disabled="$_fetching"></label>
	\\    <div role="group"><button data-action="save" data-indicator:_fetching data-attr:disabled="$_fetching" data-on:click="@put('/examples/click_to_edit')">Save</button><button data-action="cancel" data-indicator:_fetching data-attr:disabled="$_fetching" data-on:click="@get('/examples/click_to_edit/cancel')">Cancel</button></div>
	\\</div>

click_to_edit_default_contact : ClickToEditContact
click_to_edit_default_contact = { firstName: "John", lastName: "Doe", email: "john@example.com" }

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
	\\<p>Executable reproductions used to evaluate basic-webserver's Datastar API.</p>
	\\<ol><li><a href="/examples/active_search">Active Search</a></li><li><a href="/examples/animations">Animations</a></li><li><a href="/examples/bad_apple">Bad Apple</a></li><li><a href="/examples/bulk_update">Bulk Update</a></li><li><a href="/examples/click_to_edit">Click To Edit</a></li><li><a href="/examples/click_to_load">Click To Load</a></li></ol>
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

click_to_edit_page : Str
click_to_edit_page = page(
	"Click To Edit",
	\\<h1>Click To Edit</h1>
	\\<p>Edit a contact inline without a page refresh or an HTML form.</p>
	\\<fieldset><legend>Demo</legend><div data-signals__ifmissing="{_fetching: false, firstName: 'John', lastName: 'Doe', email: 'john@example.com', savedFirstName: 'John', savedLastName: 'Doe', savedEmail: 'john@example.com'}">${click_to_edit_view(click_to_edit_default_contact)}</div></fieldset>
	\\<h2>What this validates</h2>
	\\<p>GET swaps the record for signal-bound inputs; PUT validates the full signals body; Cancel restores the last saved signals; and PATCH resets the record. The self-contained probe keeps its saved contact in signals, while a real application can use the same flow with database state.</p>
	,
)

escaped_text : Str -> Str
escaped_text = |value| Html.render_without_doc_type(Html.text(value))

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
