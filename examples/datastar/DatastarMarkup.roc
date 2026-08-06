import pf.Attribute
import ./Datastar
import pf.Html
import ./RoutePath
import ./Selector
import ./SignalName
import pf.Sse
import http.Method

## Typed, receiver-oriented Datastar markup constructors.
##
## This module deliberately models the common, structurally checkable subset
## of Datastar's browser syntax. It renders ordinary attributes and typed SSE
## events; uncommon JavaScript remains available through conspicuously named
## unchecked constructors.
DatastarMarkup :: [].{

	## A typed signal handle. The type parameter is compile-time evidence; the
	## value stores only validated spellings and the encoded initial value.
	Signal(a) := { attribute : Str, canonical : Str }.{

		## Name a boolean signal which is included in requests by default.
		bool : SignalName -> Signal(Bool)
		bool = |name| Signal.(
			{
				canonical: name.canonical(),
				attribute: name.attribute(),
			},
		)

		## Name a string signal which is included in requests by default.
		str : SignalName -> Signal(Str)
		str = |name| Signal.(
			{
				canonical: name.canonical(),
				attribute: name.attribute(),
			},
		)

		## Name a U64 signal which is included in requests by default.
		## Browser arithmetic is exact only through JavaScript's safe-integer range.
		u64 : SignalName -> Signal(U64)
		u64 = |name| Signal.(
			{
				canonical: name.canonical(),
				attribute: name.attribute(),
			},
		)

		## Name a list-of-booleans signal which is included in requests.
		bool_list : SignalName -> Signal(List(Bool))
		bool_list = |name| Signal.(
			{
				canonical: name.canonical(),
				attribute: name.attribute(),
			},
		)

		## Define an underscore-prefixed boolean signal. Datastar excludes these
		## signals from backend requests by default, but request filters may include
		## them; this is not a confidentiality boundary.
		excluded_bool : SignalName -> Signal(Bool)
		excluded_bool = |name| Signal.(
			{
				canonical: "_${name.canonical()}",
				attribute: "_${name.attribute()}",
			},
		)

		## Pair this signal with a checked initial value.
		definition = |signal, value| {
			_ = signal_value_types_match(signal, value)
			SignalDef.(
				{
					field: "${Json.to_str(signal.canonical)}:${Json.to_str(value)}",
				},
			)
		}

		## Finalize a checked server update for a heterogeneous list.
		update = |signal, value| {
			_ = signal_value_types_match(signal, value)
			SignalUpdate.(
				{
					field: "${Json.to_str(signal.canonical)}:${Json.to_str(value)}",
				},
			)
		}

		## Refer to this signal in a typed Datastar expression.
		expr : Signal(a) -> Expr(a)
		expr = |signal| Expr.({ source: "$${signal.canonical}" })

		## Assign a checked literal value in the browser.
		assign = |signal, value| {
			_ = signal_value_types_match(signal, value)
			Action.(
				{
					source: "$${signal.canonical} = ${Json.to_str(value)}",
				},
			)
		}

		## Assign a same-typed expression in the browser.
		assign_expr : Signal(a), Expr(a) -> Action
		assign_expr = |signal, expression| Action.(
			{
				source: "$${signal.canonical} = ${expression.source}",
			},
		)

		## Attach this boolean signal as Datastar's fetch indicator.
		indicator : Signal(Bool) -> Attribute
		indicator = |signal| Attribute.attribute("data-indicator:${signal.attribute}", "")

		## Disable an element while this boolean signal is true.
		disabled_when_true : Signal(Bool) -> Attribute
		disabled_when_true = |signal| Attribute.attribute("data-attr:disabled", "$${signal.canonical}")

		## Toggle this boolean signal in the browser.
		toggle : Signal(Bool) -> Action
		toggle = |signal| Action.({ source: "$${signal.canonical} = !$${signal.canonical}" })

		## Bind one checkbox position to a list-of-booleans signal.
		bind_each_bool : Signal(List(Bool)) -> Attribute
		bind_each_bool = |signal| Attribute.attribute("data-bind:${signal.attribute}", "")

		## Construct an input bound to this string signal. Owning the element here
		## prevents a text binding from being attached to a non-input element.
		text_input : Signal(Str), List(Attribute) -> Html.Node
		text_input = |signal, attributes|
			Html.input(attributes.append(Attribute.attribute("data-bind:${signal.attribute}", "")))

		## Test whether every member of a list-of-booleans signal is true.
		every_true : Signal(List(Bool)) -> Expr(Bool)
		every_true = |signal| Expr.({ source: "$${signal.canonical}.every(Boolean)" })

		## Fill a list-of-booleans signal from one checked-state expression.
		fill : Signal(List(Bool)), U64, Expr(Bool) -> Action
		fill = |signal, count, value| Action.(
			{
				source: "$${signal.canonical} = Array(${U64.to_str(count)}).fill(${value.source})",
			},
		)
	}

	## A typed Datastar expression. Its type records the result promised by the
	## constructors used to build it; unchecked JavaScript can invalidate that
	## promise and is therefore result-specific and conspicuously named.
	Expr(a) := { source : Str }.{

		bool : Bool -> Expr(Bool)
		bool = |value| Expr.({ source: Json.to_str(value) })

		str : Str -> Expr(Str)
		str = |value| Expr.({ source: Json.to_str(value) })

		event_target_checked : Expr(Bool)
		event_target_checked = Expr.({ source: "evt.target.checked" })

		not : Expr(Bool) -> Expr(Bool)
		not = |expression| Expr.({ source: "!(${expression.source})" })

		and_also : Expr(Bool), Expr(Bool) -> Expr(Bool)
		and_also = |left, right| Expr.({ source: "(${left.source}) && (${right.source})" })

		equals : Expr(a), Expr(a) -> Expr(Bool)
		equals = |left, right| Expr.({ source: "(${left.source}) === (${right.source})" })

		disabled_when_true : Expr(Bool) -> Attribute
		disabled_when_true = |expression| Attribute.attribute("data-attr:disabled", expression.source)

		## Check an input while this boolean expression is true.
		checked_when_true : Expr(Bool) -> Attribute
		checked_when_true = |expression| Attribute.attribute("data-attr:checked", expression.source)

		text : Expr(Str) -> Attribute
		text = |expression| Attribute.attribute("data-text", expression.source)

		unchecked_bool : Str -> Expr(Bool)
		unchecked_bool = |source| Expr.(
			{
				source: source,
			},
		)

		unchecked_str : Str -> Expr(Str)
		unchecked_str = |source| Expr.(
			{
				source: source,
			},
		)
	}

	## A checked signal definition after its value type has been erased.
	SignalDef := { field : Str }.{
		to_field : SignalDef -> Str
		to_field = |definition| definition.field
	}

	## A checked signal update after its value type has been erased.
	SignalUpdate := { field : Str }.{
		to_field : SignalUpdate -> Str
		to_field = |update| update.field
	}

	## Install checked signal definitions on an element.
	signals : List(SignalDef) -> Attribute
	signals = |definitions|
		signal_definitions_attribute("data-signals", definitions)

	## Install checked signal definitions without replacing existing signals.
	signals_if_missing : List(SignalDef) -> Attribute
	signals_if_missing = |definitions|
		signal_definitions_attribute("data-signals__ifmissing", definitions)

	## Patch checked signal updates from the server.
	patch_signals : List(SignalUpdate) -> Sse.Event
	patch_signals = |updates|
		Datastar.patch_signals("{${Str.join_with(updates.map(|update| update.to_field()), ",")}}")

	## A structured browser event name and modifier suffix.
	DomEvent := [DomEvent(Str)].{

		click : DomEvent
		click = DomEvent("click")

		change : DomEvent
		change = DomEvent("change")

		input : DomEvent
		input = DomEvent("input")

		debounce_milliseconds : DomEvent, U64 -> DomEvent
		debounce_milliseconds = |DomEvent(name), milliseconds| DomEvent("${name}__debounce.${U64.to_str(milliseconds)}ms")

		attribute_name : DomEvent -> Str
		attribute_name = |DomEvent(name)| "data-on:${name}"
	}

	## A client-side Datastar action.
	Action := { source : Str }.{

		when : Action, Expr(Bool) -> Action
		when = |action, condition| Action.({ source: "(${condition.source}) && ${action.source}" })

		unless : Action, Expr(Bool) -> Action
		unless = |action, condition| Action.({ source: "!(${condition.source}) && ${action.source}" })

		on : Action, DomEvent -> Attribute
		on = |action, event| Attribute.attribute(event.attribute_name(), action.source)

		on_click : Action -> Attribute
		on_click = |action| action.on(DomEvent.click)

		## Run this action when Datastar initializes the element. Initialization
		## is a Datastar lifecycle hook, not a DOM event.
		on_init : Action -> Attribute
		on_init = |action| Attribute.attribute("data-init", action.source)

		unchecked : Str -> Action
		unchecked = |source| Action.(
			{
				source: source,
			},
		)
	}

	## An HTTP method and route path that render one matching Datastar backend
	## request action. The method is owned here and cannot disagree with request().
	RequestTarget := [
		DeleteTarget(RoutePath),
		GetTarget(RoutePath),
		PatchRequestTarget(RoutePath),
		PostTarget(RoutePath),
		PutTarget(RoutePath),
	].{

		delete : RoutePath -> RequestTarget
		delete = |path| DeleteTarget(path)

		get : RoutePath -> RequestTarget
		get = |path| GetTarget(path)

		patch : RoutePath -> RequestTarget
		patch = |path| PatchRequestTarget(path)

		post : RoutePath -> RequestTarget
		post = |path| PostTarget(path)

		put : RoutePath -> RequestTarget
		put = |path| PutTarget(path)

		request : RequestTarget -> Action
		request = |target| {
			(method_name, path) = request_target_parts(target)
			Action.({ source: "@${method_name}(${Json.to_str(path.to_str())})" })
		}

		matches : RequestTarget, Method, Str -> Bool
		matches = |target, method, raw_path| {
			(expected_method, path) = request_target_match_parts(target)
			method == expected_method and raw_path == path.to_str()
		}
	}

	## A selector-required element patch target. Its receiver operations prevent
	## append/prepend/remove from being constructed without a target and prevent
	## removal from carrying an HTML payload.
	PatchTarget := [PatchTarget(Selector)].{

		css : Selector -> PatchTarget
		css = |selector| PatchTarget(selector)

		append : PatchTarget, Html.Fragment -> Sse.Event
		append = |PatchTarget(selector), fragment|
			targeted_patch(fragment, selector, Datastar.PatchMode.append)

		prepend : PatchTarget, Html.Fragment -> Sse.Event
		prepend = |PatchTarget(selector), fragment|
			targeted_patch(fragment, selector, Datastar.PatchMode.prepend)

		before : PatchTarget, Html.Fragment -> Sse.Event
		before = |PatchTarget(selector), fragment|
			targeted_patch(fragment, selector, Datastar.PatchMode.before)

		after : PatchTarget, Html.Fragment -> Sse.Event
		after = |PatchTarget(selector), fragment|
			targeted_patch(fragment, selector, Datastar.PatchMode.after)

		inner : PatchTarget, Html.Fragment -> Sse.Event
		inner = |PatchTarget(selector), fragment|
			targeted_patch(fragment, selector, Datastar.PatchMode.inner)

		replace : PatchTarget, Html.Fragment -> Sse.Event
		replace = |PatchTarget(selector), fragment|
			targeted_patch(fragment, selector, Datastar.PatchMode.replace)

		## Replace this target inside a browser View Transition. Keeping the
		## selector on the receiver prevents the transition target and patched
		## element from drifting apart.
		replace_with_view_transition : PatchTarget, Html.Fragment -> Sse.Event
		replace_with_view_transition = |PatchTarget(selector), fragment|
			Datastar.patch_elements_with(
				fragment.to_str(),
				{
					..Datastar.default_patch_elements_options,
					mode: Datastar.PatchMode.replace,
					selector: Select(selector.to_str()),
					view_transition: ViewTransition(TransitionTarget(selector.to_str())),
				},
			)

		remove : PatchTarget -> Sse.Event
		remove = |PatchTarget(selector)| Datastar.remove_elements(selector.to_str())
	}

	## Patch fragment elements by their own IDs using Datastar's default outer merge.
	patch_elements : Html.Fragment -> Sse.Event
	patch_elements = |fragment| Datastar.patch_elements(fragment.to_str())
}

signal_value_types_match : DatastarMarkup.Signal(a), a -> {}
signal_value_types_match = |_, _| {}

signal_definitions_attribute : Str, List(DatastarMarkup.SignalDef) -> Attribute
signal_definitions_attribute = |name, definitions|
	Attribute.attribute(
		name,
		"{${Str.join_with(definitions.map(|definition| definition.to_field()), ",")}}",
	)

targeted_patch : Html.Fragment, Selector, Datastar.PatchMode -> Sse.Event
targeted_patch = |fragment, selector, mode|
	Datastar.patch_elements_with(
		fragment.to_str(),
		{
			..Datastar.default_patch_elements_options,
			mode,
			selector: Select(selector.to_str()),
		},
	)

request_target_parts : DatastarMarkup.RequestTarget -> (Str, RoutePath)
request_target_parts = |target|
	match target {
		DeleteTarget(path) => ("delete", path)
		GetTarget(path) => ("get", path)
		PatchRequestTarget(path) => ("patch", path)
		PostTarget(path) => ("post", path)
		PutTarget(path) => ("put", path)
	}

request_target_match_parts : DatastarMarkup.RequestTarget -> (Method, RoutePath)
request_target_match_parts = |target|
	match target {
		DeleteTarget(path) => (DELETE, path)
		GetTarget(path) => (GET, path)
		PatchRequestTarget(path) => (PATCH, path)
		PostTarget(path) => (POST, path)
		PutTarget(path) => (PUT, path)
	}

expect {
	page = DatastarMarkup.Signal.u64("page")
	fetching = DatastarMarkup.Signal.excluded_bool("fetching")
	attribute = DatastarMarkup.signals([page.definition(0), fetching.definition(Bool.False)])

	Attribute.raw_name(attribute) == "data-signals" and
		Attribute.raw_value(attribute) == "{\"page\":0,\"_fetching\":false}"
}

expect {
	message = DatastarMarkup.Signal.str("message")
	attribute = DatastarMarkup.signals([message.definition("quote \" newline\n")])

	Attribute.raw_value(attribute) == "{\"message\":\"quote \\\" newline\\n\"}"
}

expect {
	name = DatastarMarkup.Signal.str("firstName")
	input = name.text_input([Attribute.type("text")])

	Html.render_without_doc_type(input) == "<input type=\"text\" data-bind:first-name=\"\">"
}

expect {
	fetching = DatastarMarkup.Signal.excluded_bool("fetching")
	target = DatastarMarkup.RequestTarget.get("/examples/load")
	action = target.request().unless(fetching.expr()).on_click()

	Attribute.raw_value(action) == "!($_fetching) && @get(\"/examples/load\")"
}

expect {
	match SignalName.from_quote("activeSearch") {
		Ok(name) => name.attribute() == "active-search"
		Err(_) => Bool.False
	}
}

expect {
	page = DatastarMarkup.Signal.u64("page")
	fetching = DatastarMarkup.Signal.bool("fetching")
	event = DatastarMarkup.patch_signals([
		page.update(1),
		fetching.update(Bool.True),
	])

	Str.from_utf8_lossy(event.to_bytes()) == "event: datastar-patch-signals\ndata: signals {\"page\":1,\"fetching\":true}\n\n"
}

expect {
	selections = DatastarMarkup.Signal.bool_list("selections")
	change = selections.fill(4, DatastarMarkup.Expr.event_target_checked).on(DatastarMarkup.DomEvent.change)
	checked = selections.every_true().checked_when_true()

	Attribute.raw_value(change) == "$selections = Array(4).fill(evt.target.checked)" and
		Attribute.raw_name(checked) == "data-attr:checked" and
			Attribute.raw_value(checked) == "$selections.every(Boolean)"
}

expect {
	target = DatastarMarkup.RequestTarget.get("/")
	input = DatastarMarkup.DomEvent.input.debounce_milliseconds(200)
	attribute = target.request().on(input)

	Attribute.raw_name(attribute) == "data-on:input__debounce.200ms" and
		Attribute.raw_value(attribute) == "@get(\"/\")"
}

expect {
	target = DatastarMarkup.RequestTarget.get("/updates")
	attribute = target.request().on_init()

	Attribute.raw_name(attribute) == "data-init" and
		Attribute.raw_value(attribute) == "@get(\"/updates\")"
}

expect {
	target = DatastarMarkup.PatchTarget.css("#swap")
	fragment = Html.render_fragment([Html.button([Attribute.id("swap")], [Html.text("Restore")])])
	event = target.replace_with_view_transition(fragment)

	Str.from_utf8_lossy(event.to_bytes())
		== "event: datastar-patch-elements\ndata: selector #swap\ndata: mode replace\ndata: useViewTransition true\ndata: viewTransitionSelector #swap\ndata: elements <button id=\"swap\">Restore</button>\n\n"
}

expect {
	match RoutePath.parse("/dynamic/path") {
		Ok(path) => path.to_str() == "/dynamic/path"
		Err(_) => Bool.False
	}
}
