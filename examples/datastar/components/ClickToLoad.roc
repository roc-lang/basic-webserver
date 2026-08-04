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

ClickToLoadSignals : { page : U64 }

## A self-contained Click To Load component with shared typed browser/server
## identities and no mutable process-local state.
ClickToLoad :: {
	agents_id : ElementId,
	definitions : Signals({ fetching : Signal(Bool), page : Signal(U64) }),
	more_id : ElementId,
	more_target : RequestTarget,
	page_target : RequestTarget,
	root_id : ElementId,
}.{
	Config : {
		agents_id : ElementId,
		more_id : ElementId,
		more_path : RoutePath,
		page_path : RoutePath,
		root_id : ElementId,
	}

	default : ClickToLoad
	default = ClickToLoad.new({
		agents_id: "agents",
		more_id: "load-more",
		more_path: "/examples/click_to_load/more",
		page_path: "/examples/click_to_load",
		root_id: "click-to-load",
	})

	new : Config -> ClickToLoad
	new = |config| {
		definitions = {
			page: Signals.u64("page", 0),
			fetching: Signals.excluded_bool("fetching", Bool.False),
		}.Signals

		ClickToLoad.(
			{
				agents_id: config.agents_id,
				definitions,
				more_id: config.more_id,
				more_target: RequestTarget.get(config.more_path),
				page_target: RequestTarget.get(config.page_path),
				root_id: config.root_id,
			},
		)
	}

	page_target : ClickToLoad -> RequestTarget
	page_target = |component| component.page_target

	more_target : ClickToLoad -> RequestTarget
	more_target = |component| component.more_target

	page : ClickToLoad -> Server.Outcome
	page = |component| Server.respond(Page.response(component.document()))

	document : ClickToLoad -> Html.Document
	document = |component| {
		signals = component.definitions.handles()
		Page.document(
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
								component.root_id.attribute(),
								component.definitions.attribute(),
							],
							[
								Html.table(
									[component.agents_id.attribute()],
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
										Html.tbody([], row_nodes(0, 10, [])),
									],
								),
								Html.button(
									[
										component.more_id.attribute(),
										signals.fetching.indicator(),
										signals.fetching.disabled_when_true(),
										component.more_target.request().unless(signals.fetching.expr()).on_click(),
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
	}

	more! : ClickToLoad, Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
	more! = |component, request| {
		parsed : Try(ClickToLoadSignals, Datastar.SignalsError)
		parsed = Datastar.read_signals!(request)
		signals =
			match parsed {
				Ok(value) => value
				Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid Click To Load signals: ${Str.inspect(err)}")))
			}
		if signals.page >= 2 {
			return Ok(Server.respond(Page.text_response(400, "All Click To Load pages have already been requested")))
		}

		handles = component.definitions.handles()
		next_page = signals.page + 1
		start = next_page * 10
		rows_event = component.agents_id.descendant("tbody").append(rows(start, 10))
		page_event = DatastarMarkup.patch_signals([handles.page.update(next_page)])
		events =
			if next_page == 2 {
				[rows_event, page_event, component.more_id.patch_target().replace(complete_button(component))]
			} else {
				[rows_event, page_event]
			}
		Ok(Datastar.respond(events))
	}
}

rows : U64, U64 -> Html.Fragment
rows = |index, remaining| Html.render_fragment(row_nodes(index, remaining, []))

row_nodes : U64, U64, List(Html.Node) -> List(Html.Node)
row_nodes = |index, remaining, built|
	if remaining == 0 {
		built
	} else {
		row_nodes(index + 1, remaining - 1, built.append(row(index)))
	}

row : U64 -> Html.Node
row = |index| {
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

complete_button : ClickToLoad -> Html.Fragment
complete_button = |component|
	Html.render_fragment([Html.p([component.more_id.attribute()], [Html.text("All agents loaded")])])
