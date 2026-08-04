import ./Page
import pf.Attribute
import pf.Datastar
import pf.DatastarMarkup
import pf.DatastarMarkup.RequestTarget
import pf.DatastarMarkup.Signal
import pf.DatastarSignals as Signals
import pf.ElementId
import pf.Html
import pf.RoutePath
import pf.Server

ClickToEditSignals : {
	email : Str,
	firstName : Str,
	lastName : Str,
	savedEmail : Str,
	savedFirstName : Str,
	savedLastName : Str,
}

ContactDraft : { email : Str, first_name : Str, last_name : Str }

Contact := { email : Str, first_name : Str, last_name : Str }

ClickToEditHandles : {
	email : Signal(Str),
	fetching : Signal(Bool),
	first_name : Signal(Str),
	last_name : Signal(Str),
	saved_email : Signal(Str),
	saved_first_name : Signal(Str),
	saved_last_name : Signal(Str),
}

## A self-contained Click To Edit component with validated contacts, typed
## signal handles, and component-owned request dispatch.
ClickToEdit :: {
	cancel_target : RequestTarget,
	definitions : Signals(ClickToEditHandles),
	demo_id : ElementId,
	edit_target : RequestTarget,
	initial : Contact,
	page_target : RequestTarget,
	reset_target : RequestTarget,
	save_target : RequestTarget,
}.{
	Config : {
		cancel_path : RoutePath,
		demo_id : ElementId,
		edit_path : RoutePath,
		initial : ContactDraft,
		page_path : RoutePath,
		reset_path : RoutePath,
		save_path : RoutePath,
	}

	default : ClickToEdit
	default = {
		config = {
			cancel_path: "/examples/click_to_edit/cancel",
			demo_id: "demo",
			edit_path: "/examples/click_to_edit/edit",
			initial: { first_name: "John", last_name: "Doe", email: "john@example.com" },
			page_path: "/examples/click_to_edit",
			reset_path: "/examples/click_to_edit/reset",
			save_path: "/examples/click_to_edit",
		}
		build_component(config, Contact.(config.initial))
	}

	new : Config -> Try(ClickToEdit, [InvalidInitialContact])
	new = |config| {
		initial =
			match validate_contact(config.initial) {
				Ok(contact) => contact
				Err(_) => return Err(InvalidInitialContact)
			}
		Ok(build_component(config, initial))
	}

	## Handle every page and action route owned by this component.
	respond! : ClickToEdit, Server.Request, Str => Try([Handled(Server.Outcome), NotHandled], [ServerErr(Str), ..])
	respond! = |component, request, raw_path| {
		method = request.method()
		if component.page_target.matches(method, raw_path) {
			Ok(Handled(Server.respond(Page.response(component.document()))))
		} else if component.edit_target.matches(method, raw_path) {
			Ok(Handled(Datastar.respond([component.demo_id.patch_target().replace(component.form())])))
		} else if component.save_target.matches(method, raw_path) {
			save!(component, request).map_ok(|outcome| Handled(outcome))
		} else if component.cancel_target.matches(method, raw_path) {
			cancel!(component, request).map_ok(|outcome| Handled(outcome))
		} else if component.reset_target.matches(method, raw_path) {
			Ok(Handled(component.reset()))
		} else {
			Ok(NotHandled)
		}
	}

	document : ClickToEdit -> Html.Document
	document = |component|
		Page.document(
			"Click To Edit",
			[
				Html.h1([], [Html.text("Click To Edit")]),
				Html.p([], [Html.text("Edit a contact inline without a page refresh or an HTML form.")]),
				Html.element(
					"fieldset",
					[],
					[
						Html.element("legend", [], [Html.text("Demo")]),
						Html.div(
							[component.definitions.if_missing_attribute()],
							[component.view(component.initial)],
						),
					],
				),
				Html.h2([], [Html.text("What this validates")]),
				Html.p(
					[],
					[Html.text("GET replaces the record with typed signal-bound inputs; PUT validates the full signal body; Cancel validates and restores the saved contact; and PATCH resets all draft and saved signals. The component owns the browser targets and their server dispatch.")],
				),
			],
		)

	view : ClickToEdit, Contact -> Html.Node
	view = |component, contact| {
		handles = component.definitions.handles()
		Html.div(
			[component.demo_id.attribute()],
			[
				contact_field("first-name", "First Name", [Html.text(contact.first_name)]),
				contact_field("last-name", "Last Name", [Html.text(contact.last_name)]),
				contact_field(
					"email",
					"Email",
					[Html.a([Attribute.href("mailto:${contact.email}")], [Html.text(contact.email)])],
				),
				Html.div(
					[Attribute.role("group")],
					[
						action_button(component.edit_target, handles.fetching, "edit", "Edit"),
						action_button(component.reset_target, handles.fetching, "reset", "Reset"),
					],
				),
			],
		)
	}

	form : ClickToEdit -> Html.Fragment
	form = |component| {
		handles = component.definitions.handles()
		Html.render_fragment([
			Html.div(
				[component.demo_id.attribute()],
				[
					text_field("First Name", handles.first_name, "text", handles.fetching),
					text_field("Last Name", handles.last_name, "text", handles.fetching),
					text_field("Email", handles.email, "email", handles.fetching),
					Html.div(
						[Attribute.role("group")],
						[
							action_button(component.save_target, handles.fetching, "save", "Save"),
							action_button(component.cancel_target, handles.fetching, "cancel", "Cancel"),
						],
					),
				],
			),
		])
	}

	reset : ClickToEdit -> Server.Outcome
	reset = |component| {
		handles = component.definitions.handles()
		contact = component.initial
		Datastar.respond([
			DatastarMarkup.patch_signals(contact_updates(handles, contact, UpdateDraftAndSaved)),
			component.demo_id.patch_target().replace(Html.render_fragment([component.view(contact)])),
		])
	}
}

build_component : ClickToEdit.Config, Contact -> ClickToEdit
build_component = |config, initial| {
	definitions = definitions_for(initial)
	ClickToEdit.(
		{
			cancel_target: RequestTarget.get(config.cancel_path),
			definitions,
			demo_id: config.demo_id,
			edit_target: RequestTarget.get(config.edit_path),
			initial,
			page_target: RequestTarget.get(config.page_path),
			reset_target: RequestTarget.patch(config.reset_path),
			save_target: RequestTarget.put(config.save_path),
		},
	)
}

definitions_for : Contact -> Signals(ClickToEditHandles)
definitions_for = |contact| {
	email = contact.email
	first_name = contact.first_name
	last_name = contact.last_name
	{
		first_name: Signals.str("firstName", first_name),
		last_name: Signals.str("lastName", last_name),
		email: Signals.str("email", email),
		saved_first_name: Signals.str("savedFirstName", first_name),
		saved_last_name: Signals.str("savedLastName", last_name),
		saved_email: Signals.str("savedEmail", email),
		fetching: Signals.excluded_bool("fetching", Bool.False),
	}.Signals
}

save! : ClickToEdit, Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
save! = |component, request| {
	parsed = read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(invalid_signals_response(err))
		}
	draft = { first_name: signals.firstName, last_name: signals.lastName, email: signals.email }
	contact =
		match validate_contact(draft) {
			Ok(value) => value
			Err(_) => return Ok(Server.respond(Page.text_response(422, invalid_contact_message)))
		}
	handles = component.definitions.handles()

	Ok(
		Datastar.respond([
			DatastarMarkup.patch_signals(contact_updates(handles, contact, UpdateSaved)),
			component.demo_id.patch_target().replace(Html.render_fragment([component.view(contact)])),
		]),
	)
}

cancel! : ClickToEdit, Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
cancel! = |component, request| {
	parsed = read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(invalid_signals_response(err))
		}
	saved = { first_name: signals.savedFirstName, last_name: signals.savedLastName, email: signals.savedEmail }
	contact =
		match validate_contact(saved) {
			Ok(value) => value
			Err(_) => return Ok(Server.respond(Page.text_response(422, "The saved contact is invalid")))
		}
	handles = component.definitions.handles()

	Ok(
		Datastar.respond([
			DatastarMarkup.patch_signals(contact_updates(handles, contact, UpdateDraft)),
			component.demo_id.patch_target().replace(Html.render_fragment([component.view(contact)])),
		]),
	)
}

read_signals! : Server.Request => Try(ClickToEditSignals, Datastar.SignalsError)
read_signals! = |request| {
	parsed : Try(ClickToEditSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	parsed
}

invalid_signals_response : Datastar.SignalsError -> Server.Outcome
invalid_signals_response = |err|
	Server.respond(Page.text_response(400, "Invalid Click To Edit signals: ${Str.inspect(err)}"))

validate_contact : ContactDraft -> Try(Contact, [InvalidContact])
validate_contact = |draft|
	if draft.first_name.is_empty() or draft.last_name.is_empty() or Bool.not(Str.contains(draft.email, "@")) {
		Err(InvalidContact)
	} else {
		Ok(Contact.(draft))
	}

contact_updates : ClickToEditHandles, Contact, [UpdateDraft, UpdateDraftAndSaved, UpdateSaved] -> List(DatastarMarkup.SignalUpdate)
contact_updates = |handles, contact, which|
	match which {
		UpdateDraft => [
			handles.email.update(contact.email),
			handles.first_name.update(contact.first_name),
			handles.last_name.update(contact.last_name),
		]
		UpdateSaved => [
			handles.saved_email.update(contact.email),
			handles.saved_first_name.update(contact.first_name),
			handles.saved_last_name.update(contact.last_name),
		]
		UpdateDraftAndSaved => [
			handles.email.update(contact.email),
			handles.first_name.update(contact.first_name),
			handles.last_name.update(contact.last_name),
			handles.saved_email.update(contact.email),
			handles.saved_first_name.update(contact.first_name),
			handles.saved_last_name.update(contact.last_name),
		]
	}

contact_field : Str, Str, List(Html.Node) -> Html.Node
contact_field = |name, label, value|
	Html.p(
		[],
		[
			Html.text("${label}: "),
			Html.span([Attribute.attribute("data-field", name)], value),
		],
	)

text_field : Str, Signal(Str), Str, Signal(Bool) -> Html.Node
text_field = |label, signal, input_type, fetching|
	Html.label(
		[],
		[
			Html.text("${label} "),
			signal.text_input([
				Attribute.type(input_type),
				fetching.disabled_when_true(),
			]),
		],
	)

action_button : RequestTarget, Signal(Bool), Str, Str -> Html.Node
action_button = |target, fetching, name, label|
	Html.button(
		[
			Attribute.attribute("data-action", name),
			fetching.indicator(),
			fetching.disabled_when_true(),
			target.request().unless(fetching.expr()).on_click(),
		],
		[Html.text(label)],
	)

invalid_contact_message : Str
invalid_contact_message = "First name, last name, and a valid email are required"
