## Reproduces the public non-Rocket Datastar examples as executable Roc API probes.
app [Context, program] {
	pf: platform "../../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Datastar
import pf.DatastarMarkup
import pf.ElementId
import pf.Attribute
import pf.Html
import pf.Server
import pf.Sse
import http.Response
import "datastar-v1.0.2.js" as datastar_js : List(U8)

Context : {}

ActiveSearchSignals : { activeSearch : Str }

ViewTransitionSignals : { shouldRestore : Bool }

BulkUpdateSignals : { selections : List(Bool), statuses : List(Bool) }

BulkStatuses : { angie : Bool, fuqua : Bool, joe : Bool, kim : Bool }

ClickToEditSignals : {
	email : Str,
	firstName : Str,
	lastName : Str,
	savedEmail : Str,
	savedFirstName : Str,
	savedLastName : Str,
}

ClickToEditContact : { email : Str, firstName : Str, lastName : Str }

ClickToLoadSignals : { page : U64 }

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

	if click_to_load_more_target.matches(request.method(), path) {
		click_to_load_more!(request)
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
		(GET, "/examples/bulk_update") => Ok(Server.respond(html_response(bulk_update_page)))
		(PUT, "/examples/bulk_update/activate") => bulk_update!(request, Bool.True)
		(PUT, "/examples/bulk_update/deactivate") => bulk_update!(request, Bool.False)
		(GET, "/examples/click_to_edit") => Ok(Server.respond(html_response(click_to_edit_page)))
		(GET, "/examples/click_to_edit/edit") => Ok(Datastar.respond([Datastar.patch_elements(click_to_edit_form)]))
		(PUT, "/examples/click_to_edit") => click_to_edit_save!(request)
		(GET, "/examples/click_to_edit/cancel") => click_to_edit_cancel!(request)
		(PATCH, "/examples/click_to_edit/reset") => Ok(click_to_edit_reset())
		(GET, "/examples/click_to_load") => Ok(Server.respond(html_document_response(click_to_load_page)))
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

bulk_update! : Server.Request, Bool => Try(Server.Outcome, [ServerErr(Str), ..])
bulk_update! = |request, next_status| {
	signals_result : Try(BulkUpdateSignals, Datastar.SignalsError)
	signals_result = Datastar.read_signals!(request)
	signals =
		match signals_result {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(text_response(400, "Invalid Datastar signals: ${Str.inspect(err)}")))
		}

	updated =
		match (signals.selections, signals.statuses) {
			([joe_selected, angie_selected, fuqua_selected, kim_selected], [joe_status, angie_status, fuqua_status, kim_status]) => {
				joe: if joe_selected {
					next_status
				} else {
					joe_status
				},
				angie: if angie_selected {
					next_status
				} else {
					angie_status
				},
				fuqua: if fuqua_selected {
					next_status
				} else {
					fuqua_status
				},
				kim: if kim_selected {
					next_status
				} else {
					kim_status
				},
			}
			_ => return Ok(Server.respond(text_response(400, "Expected exactly four selections and four statuses")))
		}

	status_signals = Json.to_str({ statuses: [updated.joe, updated.angie, updated.fuqua, updated.kim] })
	Ok(
		Datastar.respond([
			Datastar.patch_signals(status_signals),
			Datastar.patch_elements(bulk_update_demo(updated)),
		]),
	)
}

bulk_update_demo : BulkStatuses -> Str
bulk_update_demo = |statuses| {
	status_signals = Json.to_str([statuses.joe, statuses.angie, statuses.fuqua, statuses.kim])

	# With the pinned 1.0.2 client, binding the header checkbox to `_all`
	# updates its effect before the change handler can read the checked state.
	# Deriving `checked` from the selections avoids that listener-order race.
	\\<div id="demo" data-signals__ifmissing="{_fetching: false, selections: Array(4).fill(false), statuses: ${status_signals}}">
	\\    <table>
	\\        <thead><tr><th><input aria-label="Select all users" type="checkbox" data-on:change="$selections = Array(4).fill(evt.target.checked)" data-attr:checked="$selections.every(Boolean)" data-attr:disabled="$_fetching"></th><th>Name</th><th>Email</th><th>Status</th></tr></thead>
	\\        <tbody>
	\\            ${bulk_update_row("joe", "Joe Smith", "joe@example.com", statuses.joe)}
	\\            ${bulk_update_row("angie", "Angie MacDowell", "angie@example.com", statuses.angie)}
	\\            ${bulk_update_row("fuqua", "Fuqua Tarkenton", "fuqua@example.com", statuses.fuqua)}
	\\            ${bulk_update_row("kim", "Kim Yee", "kim@example.com", statuses.kim)}
	\\        </tbody>
	\\    </table>
	\\    <div role="group"><button data-action="activate" data-on:click="@put('/examples/bulk_update/activate')" data-indicator:_fetching data-attr:disabled="$_fetching">Activate</button><button data-action="deactivate" data-on:click="@put('/examples/bulk_update/deactivate')" data-indicator:_fetching data-attr:disabled="$_fetching">Deactivate</button></div>
	\\</div>
}

bulk_update_row : Str, Str, Str, Bool -> Str
bulk_update_row = |key, name, email, active|
	\\<tr data-user="${key}"><td><input aria-label="Select ${name}" type="checkbox" data-bind:selections data-attr:disabled="$_fetching"></td><td>${name}</td><td><a href="mailto:${email}">${email}</a></td><td class="status">${
		if active {
			"Active"
		} else {
			"Inactive"
		}
	}</td></tr>

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

click_to_load_page_signal : DatastarMarkup.Signal(U64)
click_to_load_page_signal = DatastarMarkup.Signal.u64("page")

click_to_load_fetching_signal : DatastarMarkup.Signal(Bool)
click_to_load_fetching_signal = DatastarMarkup.Signal.excluded_bool("fetching")

click_to_load_more_target : DatastarMarkup.RequestTarget
click_to_load_more_target = DatastarMarkup.RequestTarget.get("/examples/click_to_load/more")

click_to_load_root_id : ElementId
click_to_load_root_id = "click-to-load"

click_to_load_agents_id : ElementId
click_to_load_agents_id = "agents"

click_to_load_more_id : ElementId
click_to_load_more_id = "load-more"

click_to_load_rows_target : DatastarMarkup.PatchTarget
click_to_load_rows_target = click_to_load_agents_id.descendant("tbody")

click_to_load_more! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
click_to_load_more! = |request| {
	signals_result : Try(ClickToLoadSignals, Datastar.SignalsError)
	signals_result = Datastar.read_signals!(request)
	signals =
		match signals_result {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(text_response(400, "Invalid Click To Load signals: ${Str.inspect(err)}")))
		}
	if signals.page >= 2 {
		return Ok(Server.respond(text_response(400, "All Click To Load pages have already been requested")))
	}

	next_page = signals.page + 1
	start = next_page * 10
	rows = click_to_load_rows_target.append(click_to_load_rows(start, 10))
	page_signal = DatastarMarkup.patch_signals([click_to_load_page_signal.update(next_page)])
	events =
		if next_page == 2 {
			[rows, page_signal, click_to_load_more_id.patch_target().replace(click_to_load_complete_button)]
		} else {
			[rows, page_signal]
		}
	Ok(Datastar.respond(events))
}

click_to_load_rows : U64, U64 -> Html.Fragment
click_to_load_rows = |index, remaining|
	Html.render_fragment(click_to_load_row_nodes(index, remaining, []))

click_to_load_row_nodes : U64, U64, List(Html.Node) -> List(Html.Node)
click_to_load_row_nodes = |index, remaining, rows|
	if remaining == 0 {
		rows
	} else {
		click_to_load_row_nodes(index + 1, remaining - 1, rows.append(click_to_load_row(index)))
	}

click_to_load_row : U64 -> Html.Node
click_to_load_row = |index| {
	number = U64.to_str(index)
	email = "agent${number}@example.com"
	Html.tr(
		[Attribute.attribute("data-agent", number)],
		[
			Html.td([], [Html.text("Agent Smith ${number}")]),
			Html.td([], [Html.a([Attribute.href("mailto:${email}")], [Html.text(email)])]),
			Html.td([], [Html.text("agent-${number}")]),
		],
	)
}

click_to_load_complete_button : Html.Fragment
click_to_load_complete_button =
	Html.render_fragment([Html.p([click_to_load_more_id.attribute()], [Html.text("All agents loaded")])])

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

typed_page_styles : Str
typed_page_styles =
	\\:root { color-scheme: light dark; font-family: system-ui, sans-serif; }
	\\body { max-width: 54rem; margin: 3rem auto; padding: 0 1rem; }
	\\nav { display: flex; gap: 1rem; margin-bottom: 2rem; }
	\\fieldset { padding: 1.5rem; }
	\\input { width: min(24rem, 100%); padding: .65rem; }
	\\input[type="checkbox"] { width: auto; }
	\\button { margin: 1rem .5rem 0 0; padding: .65rem 1rem; }
	\\table { width: 100%; margin-top: 1rem; border-collapse: collapse; }
	\\th, td { text-align: left; padding: .5rem; border-bottom: 1px solid #8886; }
	\\code { background: #8882; padding: .1rem .3rem; }
	\\#throb { padding: 2rem; transition: color 1s, background-color 1s; }

typed_page : Str, List(Html.Node) -> Html.Document
typed_page = |title, content|
	Html.render_document(
		Html.html(
			[Attribute.attribute("lang", "en")],
			[
				Html.head(
					[],
					[
						Html.meta([Attribute.attribute("charset", "utf-8")]),
						Html.meta([
							Attribute.name("viewport"),
							Attribute.attribute("content", "width=device-width, initial-scale=1"),
						]),
						Html.title([], [Html.text("${title} · Roc + Datastar")]),
						Html.element(
							"script",
							[Attribute.type("module"), Attribute.src("/datastar.js")],
							[],
						),
						Html.element(
							"style",
							[],
							[Html.dangerously_include_unescaped_html(typed_page_styles)],
						),
					],
				),
				Html.body(
					[],
					List.concat(
						[
							Html.nav(
								[],
								[
									Html.a([Attribute.href("/")], [Html.text("All examples")]),
									Html.a(
										[
											Attribute.href("https://data-star.dev/examples/"),
											Attribute.rel("noreferrer"),
										],
										[Html.text("Datastar originals")],
									),
								],
							),
						],
						content,
					),
				),
			],
		),
	)

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

bulk_update_page : Str
bulk_update_page = page(
	"Bulk Update",
	\\<h1>Bulk Update</h1>
	\\<p>Select users and activate or deactivate them together.</p>
	\\<fieldset><legend>Demo</legend>${bulk_update_demo({ joe: Bool.False, angie: Bool.False, fuqua: Bool.True, kim: Bool.True })}</fieldset>
	\\<h2>What this validates</h2>
	\\<p><code>Datastar.read_signals!</code> decodes a PUT body containing array signals, and one finite response composes a signal patch with a server-rendered element patch. This self-contained probe keeps its four statuses in signals; an application can apply the same selections to database-backed state.</p>
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

click_to_load_page : Html.Document
click_to_load_page = typed_page(
	"Click To Load",
	[
		Html.h1([], [Html.text("Click To Load")]),
		Html.p([], [Html.text("Load the next page of agents into an existing table.")]),
		Html.element(
			"fieldset",
			[],
			[
				Html.element("legend", [], [Html.text("Demo")]),
				Html.div(
					[
						click_to_load_root_id.attribute(),
						DatastarMarkup.signals([click_to_load_page_signal.definition(0)]),
					],
					[
						Html.table(
							[click_to_load_agents_id.attribute()],
							[
								Html.thead(
									[],
									[
										Html.tr(
											[],
											[
												Html.th([], [Html.text("Name")]),
												Html.th([], [Html.text("Email")]),
												Html.th([], [Html.text("ID")]),
											],
										),
									],
								),
								Html.tbody([], click_to_load_row_nodes(0, 10, [])),
							],
						),
						Html.button(
							[
								click_to_load_more_id.attribute(),
								click_to_load_fetching_signal.indicator(),
								click_to_load_fetching_signal.disabled_when_true(),
								click_to_load_more_target.request().unless(click_to_load_fetching_signal.expr()).on_click(),
							],
							[Html.text("Load More")],
						),
					],
				),
			],
		),
		Html.h2([], [Html.text("What this validates")]),
		Html.p(
			[],
			[Html.text("Each finite GET response appends ten rows with an explicit selector and patch mode, advances a pagination signal, and eventually replaces the stable load button.")],
		),
	],
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

html_document_response : Html.Document -> Response
html_document_response = |document|
	Response.from_status(200)
		.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
		.with_body(document.to_bytes())

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
