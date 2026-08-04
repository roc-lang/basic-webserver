import ./Page
import pf.Datastar
import pf.Html
import pf.Server
import pf.Sse

DbmonSignals : { fps : U64, mutationRate : U64 }

InfiniteScrollSignals : { limit : U64, offset : U64 }

SvgSignals : { circleBlue : Bool }

CounterSignals : { globalCount : U64, userCount : U64 }

## Server-driven loading, pagination, progress, morphing, and counter probes.
LoadingExamples :: [].{

	respond! : Server.Request, Str => Try([Handled(Server.Outcome), NotHandled], [ServerErr(Str), ..])
	respond! = |request, path|
		match (request.method(), path) {
			(GET, "/examples/dbmon") => Ok(Handled(page("DBmon", "Render a rapidly changing database activity table.", dbmon_demo, "A finite retained stream updates stable table and timing elements without retaining application state.")))
			(GET, "/examples/dbmon/updates") => Ok(Handled(Server.stream(Sse.unfold!(0, dbmon_transition!))))
			(PUT, "/examples/dbmon/inputs") => dbmon_inputs!(request).map_ok(|outcome| Handled(outcome))

			(GET, "/examples/infinite_scroll") => Ok(Handled(page("Infinite Scroll", "Load another page when the sentinel enters the viewport.", infinite_scroll_demo, "An intersection-triggered finite response appends rows and advances the browser-owned offset signal.")))
			(GET, "/examples/infinite_scroll/more") => infinite_scroll_more!(request).map_ok(|outcome| Handled(outcome))

			(GET, "/examples/lazy_load") => Ok(Handled(page("Lazy Load", "Replace a loading placeholder after the page initializes.", lazy_load_demo, "A data-init GET action returns one finite element patch for a stable placeholder ID.")))
			(GET, "/examples/lazy_load/graph") => Ok(Handled(lazy_graph))

			(GET, "/examples/lazy_tabs") => Ok(Handled(page("Lazy Tabs", "Load tab content only when a tab is selected.", lazy_tabs_demo, "Each tab owns an explicit finite GET action that replaces the shared tab panel.")))
			(GET, "/examples/lazy_tabs/0") => Ok(Handled(lazy_tab(0)))
			(GET, "/examples/lazy_tabs/1") => Ok(Handled(lazy_tab(1)))
			(GET, "/examples/lazy_tabs/2") => Ok(Handled(lazy_tab(2)))
			(GET, "/examples/lazy_tabs/3") => Ok(Handled(lazy_tab(3)))
			(GET, "/examples/lazy_tabs/4") => Ok(Handled(lazy_tab(4)))
			(GET, "/examples/lazy_tabs/5") => Ok(Handled(lazy_tab(5)))
			(GET, "/examples/lazy_tabs/6") => Ok(Handled(lazy_tab(6)))
			(GET, "/examples/lazy_tabs/7") => Ok(Handled(lazy_tab(7)))

			(GET, "/examples/progress_bar") => Ok(Handled(page("Progress Bar", "Stream progress until the task reaches 100 percent.", progress_bar_demo, "A retained timer source emits ordered progress patches and then completes.")))
			(GET, "/examples/progress_bar/updates") => Ok(Handled(Server.stream(Sse.unfold!(0, progress_transition!))))

			(GET, "/examples/progressive_load") => Ok(Handled(page("Progressive Load", "Fill independent page regions over one progressive response.", progressive_load_demo, "One retained source patches header, article, comments, and footer in order before restoring the load button.")))
			(GET, "/examples/progressive_load/updates") => Ok(Handled(Server.stream(Sse.unfold!(0, progressive_transition!))))

			(GET, "/examples/svg_morphing") => Ok(Handled(page("SVG Morphing", "Change an SVG circle using a server-driven SVG patch.", svg_morphing_demo, "A finite response patches an SVG-namespaced circle and advances the browser-owned color signal.")))
			(GET, "/examples/svg_morphing/circle_color") => svg_color!(request).map_ok(|outcome| Handled(outcome))

			(GET, "/examples/templ_counter") => Ok(Handled(page("Templ Counter", "Increment independent global and user counters.", templ_counter_demo, "PATCH actions decode counter signals, update one stable button, and return the new counter signal.")))
			(PATCH, "/examples/templ_counter/global") => increment_counter!(request, Global).map_ok(|outcome| Handled(outcome))
			(PATCH, "/examples/templ_counter/user") => increment_counter!(request, User).map_ok(|outcome| Handled(outcome))

			(GET, "/examples/title_update") => Ok(Handled(page("Title Update", "Watch the browser tab title change as events arrive.", title_update_demo, "A finite retained stream targets the document title with ordered inner patches and then completes.")))
			(GET, "/examples/title_update/updates") => Ok(Handled(Server.stream(Sse.unfold!(0, title_transition!))))
			_ => Ok(NotHandled)
		}
}

page : Str, Str, Str, Str -> Server.Outcome
page = |title, description, demo_html, validation|
	Server.respond(
		Page.response(
			Page.document(
				title,
				[
					Html.h1([], [Html.text(title)]),
					Html.p([], [Html.text(description)]),
					Html.element("fieldset", [], [Html.element("legend", [], [Html.text("Demo")]), Html.dangerously_include_unescaped_html(demo_html)]),
					Html.h2([], [Html.text("What this validates")]),
					Html.p([], [Html.text(validation)]),
				],
			),
		),
	)

dbmon_demo : Str
dbmon_demo =
	\\<div id="dbmon-demo" data-init="@get('/examples/dbmon/updates')" data-signals="{mutationRate: 20, fps: 60}">
	\\    <label>Mutation Rate % <input id="dbmon-mutation" type="number" min="0" max="100" data-bind:mutation-rate data-on:change="@put('/examples/dbmon/inputs')"></label>
	\\    <label>FPS <input id="dbmon-fps" type="number" min="1" max="144" data-bind:fps data-on:change="@put('/examples/dbmon/inputs')"></label>
	\\    <p id="dbmon-settings">Mutation 20%, 60 FPS</p>
	\\    <p id="dbmon-render">Render frame 0</p>
	\\    <table><tbody id="dbmon-body">${dbmon_rows(0)}</tbody></table>
	\\</div>

dbmon_rows : U64 -> Str
dbmon_rows = |frame|
	Str.join_with(
		List.map(
			[1, 2, 3, 4, 5, 6],
			|cluster| {
				queries = (cluster * 3 + frame) % 16
				latency = (cluster * 7 + frame * 3) % 20
				cluster_str = U64.to_str(cluster)
				"<tr data-dbmon-cluster=\"${cluster_str}\"><td>cluster${cluster_str}</td><td>${U64.to_str(queries)}</td><td>${U64.to_str(latency)}ms</td><td>SELECT records</td></tr>"
			},
		),
		"",
	)

dbmon_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
dbmon_transition! = |frame| {
	if frame >= 6 {
		return Ok(End)
	}
	next = frame + 1
	elements = "<p id=\"dbmon-render\">Render frame ${U64.to_str(next)}</p><tbody id=\"dbmon-body\">${dbmon_rows(next)}</tbody>"
	Ok(Emit({ event: Datastar.patch_elements(elements), state: next, wake: After(40) }))
}

dbmon_inputs! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
dbmon_inputs! = |request| {
	parsed : Try(DbmonSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid DBmon signals: ${Str.inspect(err)}")))
		}
	Ok(Datastar.respond([Datastar.patch_elements("<p id=\"dbmon-settings\">Mutation ${U64.to_str(signals.mutationRate)}%, ${U64.to_str(signals.fps)} FPS</p>")]))
}

infinite_scroll_demo : Str
infinite_scroll_demo =
	\\<div id="infinite-scroll-demo" data-signals="{offset: 0, limit: 10}">
	\\    <table><caption>Agents</caption><thead><tr><th>Name</th><th>Email</th><th>ID</th></tr></thead><tbody id="infinite-agents">${agent_rows(0, 10)}</tbody></table>
	\\    <div id="infinite-scroll-sentinel" data-on-intersect="@get('/examples/infinite_scroll/more')">Loading more…</div>
	\\</div>

agent_rows : U64, U64 -> Str
agent_rows = |start, count|
	if count == 0 {
		""
	} else {
		start_str = U64.to_str(start)
		"<tr data-infinite-agent=\"${start_str}\"><td>Agent Smith ${start_str}</td><td>void${start_str}@null.org</td><td>agent-${start_str}</td></tr>${agent_rows(start + 1, count - 1)}"
	}

infinite_scroll_more! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
infinite_scroll_more! = |request| {
	parsed : Try(InfiniteScrollSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid Infinite Scroll signals: ${Str.inspect(err)}")))
		}
	next_offset = signals.offset + signals.limit
	rows_event = Datastar.patch_elements_with(
		agent_rows(next_offset, signals.limit),
		{ ..Datastar.default_patch_elements_options, selector: Select("#infinite-agents"), mode: Append },
	)
	Ok(Datastar.respond([rows_event, Datastar.patch_signals(Json.to_str({ offset: next_offset }))]))
}

lazy_load_demo : Str
lazy_load_demo =
	\\<div id="lazy-load" data-init="@get('/examples/lazy_load/graph')">Loading graph…</div>

lazy_graph : Server.Outcome
lazy_graph = Datastar.respond([
	Datastar.patch_elements(
		\\<div id="lazy-load">
		\\    <svg id="lazy-graph" viewBox="0 0 300 120" role="img" aria-label="Loaded line graph"><polyline points="0,100 50,80 100,90 150,35 200,55 250,20 300,30" fill="none" stroke="currentColor" stroke-width="4"></polyline></svg>
		\\    <p>Graph loaded.</p>
		\\</div>
		,
	),
])

lazy_tabs_demo : Str
lazy_tabs_demo =
	\\<div id="lazy-tabs"><div role="tablist">
	\\    <button data-lazy-tab="0" data-on:click="@get('/examples/lazy_tabs/0')">Tab 0</button>
	\\    <button data-lazy-tab="1" data-on:click="@get('/examples/lazy_tabs/1')">Tab 1</button>
	\\    <button data-lazy-tab="2" data-on:click="@get('/examples/lazy_tabs/2')">Tab 2</button>
	\\    <button data-lazy-tab="3" data-on:click="@get('/examples/lazy_tabs/3')">Tab 3</button>
	\\    <button data-lazy-tab="4" data-on:click="@get('/examples/lazy_tabs/4')">Tab 4</button>
	\\    <button data-lazy-tab="5" data-on:click="@get('/examples/lazy_tabs/5')">Tab 5</button>
	\\    <button data-lazy-tab="6" data-on:click="@get('/examples/lazy_tabs/6')">Tab 6</button>
	\\    <button data-lazy-tab="7" data-on:click="@get('/examples/lazy_tabs/7')">Tab 7</button>
	\\</div><div id="lazy-tab-panel" role="tabpanel">Content for tab 0.</div></div>

lazy_tab : U64 -> Server.Outcome
lazy_tab = |index| Datastar.respond([Datastar.patch_elements("<div id=\"lazy-tab-panel\" role=\"tabpanel\">Content loaded for tab ${U64.to_str(index)}.</div>")])

progress_bar_demo : Str
progress_bar_demo =
	\\<div id="progress-bar" data-init="@get('/examples/progress_bar/updates', {openWhenHidden: true})"><progress max="100" value="0"></progress><span>0%</span></div>

progress_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
progress_transition! = |step| {
	if step >= 10 {
		return Ok(End)
	}
	next = step + 1
	percentage = next * 10
	percentage_str = U64.to_str(percentage)
	element = "<div id=\"progress-bar\"><progress max=\"100\" value=\"${percentage_str}\"></progress><span>${percentage_str}%</span></div>"
	Ok(Emit({ event: Datastar.patch_elements(element), state: next, wake: After(30) }))
}

progressive_load_demo : Str
progressive_load_demo =
	\\<div id="progressive-load-demo">
	\\    <button id="load-button" data-on:click="el.disabled = true; @get('/examples/progressive_load/updates')">Load</button>
	\\    <header id="progressive-header"></header><section id="progressive-article"></section><section id="progressive-comments"></section><footer id="progressive-footer"></footer>
	\\</div>

progressive_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
progressive_transition! = |step|
	match step {
		0 => Ok(Emit({ event: Datastar.patch_elements("<header id=\"progressive-header\"><h3>Loaded header</h3></header>"), state: 1, wake: After(40) }))
		1 => Ok(Emit({ event: Datastar.patch_elements("<section id=\"progressive-article\"><p>Loaded article</p></section>"), state: 2, wake: After(40) }))
		2 => Ok(Emit({ event: Datastar.patch_elements("<section id=\"progressive-comments\"><p>Loaded comments</p></section>"), state: 3, wake: After(40) }))
		3 => Ok(Emit({ event: Datastar.patch_elements("<footer id=\"progressive-footer\">Loaded footer</footer>"), state: 4, wake: After(40) }))
		4 => Ok(Emit({ event: Datastar.patch_elements("<button id=\"load-button\" data-on:click=\"el.disabled = true; @get('/examples/progressive_load/updates')\">Load again</button>"), state: 5, wake: Immediately }))
		_ => Ok(End)
	}

svg_morphing_demo : Str
svg_morphing_demo =
	\\<div id="svg-morphing-demo" data-signals:circle-blue="false"><svg viewBox="0 0 100 100" width="160" height="160"><circle id="morph-circle" cx="50" cy="50" r="40" fill="red"></circle></svg><button data-action="morph-circle" data-on:click="@get('/examples/svg_morphing/circle_color')">Change Color</button></div>

svg_color! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
svg_color! = |request| {
	parsed : Try(SvgSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid SVG Morphing signals: ${Str.inspect(err)}")))
		}
	next = Bool.not(signals.circleBlue)
	color = if next {
		"blue"
	} else {
		"red"
	}
	event = Datastar.patch_elements_with(
		"<circle id=\"morph-circle\" cx=\"50\" cy=\"50\" r=\"40\" fill=\"${color}\"></circle>",
		{ ..Datastar.default_patch_elements_options, namespace: Svg },
	)
	Ok(Datastar.respond([event, Datastar.patch_signals(Json.to_str({ circleBlue: next }))]))
}

templ_counter_demo : Str
templ_counter_demo =
	\\<div id="templ-counter" data-signals="{globalCount: 5224, userCount: 0}"><button id="global-counter" data-on:click="@patch('/examples/templ_counter/global')">Increment Global: 5224</button><button id="user-counter" data-on:click="@patch('/examples/templ_counter/user')">Increment User: 0</button></div>

CounterKind := [Global, User]

increment_counter! : Server.Request, CounterKind => Try(Server.Outcome, [ServerErr(Str), ..])
increment_counter! = |request, kind| {
	parsed : Try(CounterSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid Templ Counter signals: ${Str.inspect(err)}")))
		}
	(element, updated) =
		match kind {
			Global => {
				next = signals.globalCount + 1
				("<button id=\"global-counter\" data-on:click=\"@patch('/examples/templ_counter/global')\">Increment Global: ${U64.to_str(next)}</button>", Json.to_str({ globalCount: next }))
			}
			User => {
				next = signals.userCount + 1
				("<button id=\"user-counter\" data-on:click=\"@patch('/examples/templ_counter/user')\">Increment User: ${U64.to_str(next)}</button>", Json.to_str({ userCount: next }))
			}
		}
	Ok(Datastar.respond([Datastar.patch_elements(element), Datastar.patch_signals(updated)]))
}

title_update_demo : Str
title_update_demo =
	\\<p id="title-update-status" data-init="@get('/examples/title_update/updates')">Look at the title change in the browser tab.</p>

title_transition! : U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
title_transition! = |frame| {
	if frame >= 3 {
		return Ok(End)
	}
	next = frame + 1
	event = Datastar.patch_elements_with(
		"Title Update frame ${U64.to_str(next)}",
		{ ..Datastar.default_patch_elements_options, selector: Select("title"), mode: Inner },
	)
	Ok(Emit({ event, state: next, wake: After(50) }))
}
