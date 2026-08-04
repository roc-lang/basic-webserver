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

BulkUpdateSignals : { selections : List(Bool), statuses : List(Bool) }

BulkStatuses : { angie : Bool, fuqua : Bool, joe : Bool, kim : Bool }

BulkHandles : {
	fetching : Signal(Bool),
	selections : Signal(List(Bool)),
	statuses : Signal(List(Bool)),
}

BulkUser : { active : Bool, email : Str, key : Str, name : Str }

## A self-contained Bulk Update component. It owns browser actions, route
## matching, and their corresponding server transitions as one unit.
BulkUpdate :: {
	activate_target : RequestTarget,
	deactivate_target : RequestTarget,
	definitions : Signals(BulkHandles),
	demo_id : ElementId,
	page_target : RequestTarget,
}.{
	Action := [ActivateAction(RequestTarget), DeactivateAction(RequestTarget)].{

		request : Action -> DatastarMarkup.Action
		request = |action|
			match action {
				ActivateAction(target) => target.request()
				DeactivateAction(target) => target.request()
			}
	}

	Config : {
		activate_path : RoutePath,
		deactivate_path : RoutePath,
		demo_id : ElementId,
		page_path : RoutePath,
	}

	default : BulkUpdate
	default = BulkUpdate.new({
		activate_path: "/examples/bulk_update/activate",
		deactivate_path: "/examples/bulk_update/deactivate",
		demo_id: "demo",
		page_path: "/examples/bulk_update",
	})

	new : Config -> BulkUpdate
	new = |config| {
		definitions = {
			selections: Signals.bool_list("selections", [Bool.False, Bool.False, Bool.False, Bool.False]),
			statuses: Signals.bool_list("statuses", statuses_to_list(initial_statuses)),
			fetching: Signals.excluded_bool("fetching", Bool.False),
		}.Signals

		BulkUpdate.(
			{
				activate_target: RequestTarget.put(config.activate_path),
				deactivate_target: RequestTarget.put(config.deactivate_path),
				definitions,
				demo_id: config.demo_id,
				page_target: RequestTarget.get(config.page_path),
			},
		)
	}

	activate : BulkUpdate -> Action
	activate = |component| ActivateAction(component.activate_target)

	deactivate : BulkUpdate -> Action
	deactivate = |component| DeactivateAction(component.deactivate_target)

	## Handle this component's page and action routes. The transition is selected
	## only after its corresponding target matches, so callers cannot pair an
	## activate request with deactivation behavior or vice versa.
	respond! : BulkUpdate, Server.Request, Str => Try([Handled(Server.Outcome), NotHandled], [ServerErr(Str), ..])
	respond! = |component, request, raw_path| {
		method = request.method()
		if component.page_target.matches(method, raw_path) {
			Ok(Handled(Server.respond(Page.response(component.document()))))
		} else if component.activate_target.matches(method, raw_path) {
			apply_status!(component, request, Bool.True).map_ok(|outcome| Handled(outcome))
		} else if component.deactivate_target.matches(method, raw_path) {
			apply_status!(component, request, Bool.False).map_ok(|outcome| Handled(outcome))
		} else {
			Ok(NotHandled)
		}
	}

	document : BulkUpdate -> Html.Document
	document = |component|
		Page.document(
			"Bulk Update",
			[
				Html.h1([], [Html.text("Bulk Update")]),
				Html.p([], [Html.text("Select users and activate or deactivate them together.")]),
				Html.element(
					"fieldset",
					[],
					[
						Html.element("legend", [], [Html.text("Demo")]),
						component.demo(initial_statuses),
					],
				),
				Html.h2([], [Html.text("What this validates")]),
				Html.p(
					[],
					[Html.text("A typed PUT action decodes list signals, applies one of two explicit transitions, and returns coordinated signal and element patches. The self-contained probe keeps its four statuses in browser signals; an application can apply the same selections to database-backed state.")],
				),
			],
		)

	demo : BulkUpdate, BulkStatuses -> Html.Node
	demo = |component, statuses| {
		handles = component.definitions.handles()
		Html.div(
			[
				component.demo_id.attribute(),
				component.definitions.if_missing_attribute(),
			],
			[
				Html.table(
					[],
					[
						Html.thead([], [header(handles)]),
						Html.tbody([], users(statuses).map(|user| row(handles, user))),
					],
				),
				Html.div(
					[Attribute.role("group")],
					[
						action_button(component.activate(), handles.fetching, "activate", "Activate"),
						action_button(component.deactivate(), handles.fetching, "deactivate", "Deactivate"),
					],
				),
			],
		)
	}
}

apply_status! : BulkUpdate, Server.Request, Bool => Try(Server.Outcome, [ServerErr(Str), ..])
apply_status! = |component, request, next_status| {
	parsed : Try(BulkUpdateSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid Bulk Update signals: ${Str.inspect(err)}")))
		}

	current =
		match statuses_from_lists(signals.selections, signals.statuses) {
			Ok(value) => value
			Err(_) => return Ok(Server.respond(Page.text_response(400, "Expected exactly four selections and four statuses")))
		}
	updated = apply_selections(current, next_status)
	handles = component.definitions.handles()

	Ok(
		Datastar.respond([
			DatastarMarkup.patch_signals([handles.statuses.update(statuses_to_list(updated))]),
			component.demo_id.patch_target().replace(Html.render_fragment([component.demo(updated)])),
		]),
	)
}

initial_statuses : BulkStatuses
initial_statuses = { joe: Bool.False, angie: Bool.False, fuqua: Bool.True, kim: Bool.True }

header : BulkHandles -> Html.Node
header = |handles|
	Html.tr(
		[],
		[
			Html.th(
				[],
				[
					Html.input([
						Attribute.attribute("aria-label", "Select all users"),
						Attribute.type("checkbox"),
						handles.selections.fill(4, DatastarMarkup.Expr.event_target_checked).on(DatastarMarkup.DomEvent.change),
						handles.selections.every_true().checked_when_true(),
						handles.fetching.disabled_when_true(),
					]),
				],
			),
			Html.th([], [Html.text("Name")]),
			Html.th([], [Html.text("Email")]),
			Html.th([], [Html.text("Status")]),
		],
	)

row : BulkHandles, BulkUser -> Html.Node
row = |handles, user|
	Html.tr(
		[Attribute.attribute("data-user", user.key)],
		[
			Html.td(
				[],
				[
					Html.input([
						Attribute.attribute("aria-label", "Select ${user.name}"),
						Attribute.type("checkbox"),
						handles.selections.bind_each_bool(),
						handles.fetching.disabled_when_true(),
					]),
				],
			),
			Html.td([], [Html.text(user.name)]),
			Html.td([], [Html.a([Attribute.href("mailto:${user.email}")], [Html.text(user.email)])]),
			Html.td(
				[Attribute.class("status")],
				[
					Html.text(
						if user.active {
							"Active"
						} else {
							"Inactive"
						},
					),
				],
			),
		],
	)

action_button : BulkUpdate.Action, Signal(Bool), Str, Str -> Html.Node
action_button = |action, fetching, name, label|
	Html.button(
		[
			Attribute.attribute("data-action", name),
			fetching.indicator(),
			fetching.disabled_when_true(),
			action.request().unless(fetching.expr()).on_click(),
		],
		[Html.text(label)],
	)

users : BulkStatuses -> List(BulkUser)
users = |statuses| [
	{ key: "joe", name: "Joe Smith", email: "joe@example.com", active: statuses.joe },
	{ key: "angie", name: "Angie MacDowell", email: "angie@example.com", active: statuses.angie },
	{ key: "fuqua", name: "Fuqua Tarkenton", email: "fuqua@example.com", active: statuses.fuqua },
	{ key: "kim", name: "Kim Yee", email: "kim@example.com", active: statuses.kim },
]

statuses_from_lists : List(Bool), List(Bool) -> Try({ selections : BulkStatuses, statuses : BulkStatuses }, [WrongLength])
statuses_from_lists = |selections, statuses|
	match (selections, statuses) {
		([joe_selected, angie_selected, fuqua_selected, kim_selected], [joe_status, angie_status, fuqua_status, kim_status]) => Ok({
			selections: { joe: joe_selected, angie: angie_selected, fuqua: fuqua_selected, kim: kim_selected },
			statuses: { joe: joe_status, angie: angie_status, fuqua: fuqua_status, kim: kim_status },
		})
		_ => Err(WrongLength)
	}

apply_selections : { selections : BulkStatuses, statuses : BulkStatuses }, Bool -> BulkStatuses
apply_selections = |current, next_status| {
	joe: if current.selections.joe {
		next_status
	} else {
		current.statuses.joe
	},
	angie: if current.selections.angie {
		next_status
	} else {
		current.statuses.angie
	},
	fuqua: if current.selections.fuqua {
		next_status
	} else {
		current.statuses.fuqua
	},
	kim: if current.selections.kim {
		next_status
	} else {
		current.statuses.kim
	},
}

statuses_to_list : BulkStatuses -> List(Bool)
statuses_to_list = |statuses| [statuses.joe, statuses.angie, statuses.fuqua, statuses.kim]
