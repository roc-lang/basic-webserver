import Attribute
import Datastar
import Html
import Sse
import http.Method

## Typed, receiver-oriented Datastar markup constructors.
##
## This module deliberately models the common, structurally checkable subset
## of Datastar's browser syntax. It renders ordinary attributes and typed SSE
## events; uncommon JavaScript remains available through conspicuously named
## unchecked constructors.
DatastarMarkup :: [].{

	## A validated canonical Datastar signal name and its attribute spelling.
	SignalName := [SignalName({ attribute : Str, canonical : Str })].{

		## Validate a dynamically obtained canonical signal name.
		parse : Str -> Try(SignalName, [InvalidSignalName(Str)])
		parse = |value|
			if valid_signal_name(value) {
				Ok(SignalName({ canonical: value, attribute: signal_attribute_name(value) }))
			} else {
				Err(InvalidSignalName(value))
			}

		## Validate a quoted signal name during compile-time evaluation.
		from_quote : Str -> Try(SignalName, [BadQuotedBytes(Str)])
		from_quote = |value|
			match SignalName.parse(value) {
				Ok(name) => Ok(name)
				Err(_) => Err(BadQuotedBytes("Datastar signal names must start with an ASCII letter and contain only ASCII letters or digits"))
			}

		canonical : SignalName -> Str
		canonical = |SignalName(name)| name.canonical

		attribute : SignalName -> Str
		attribute = |SignalName(name)| name.attribute
	}

	## A typed signal handle. The type parameter is compile-time evidence; the
	## value stores only validated spellings and the encoded initial value.
	Signal(a) := { attribute : Str, canonical : Str, initial_json : Str }.{

		## Define a boolean signal whose value is included in requests by default.
		bool : SignalName, Bool -> Signal(Bool)
		bool = |name, initial| Signal.(
			{
				canonical: name.canonical(),
				attribute: name.attribute(),
				initial_json: Json.to_str(initial),
			},
		)

		## Define a string signal whose value is included in requests by default.
		str : SignalName, Str -> Signal(Str)
		str = |name, initial| Signal.(
			{
				canonical: name.canonical(),
				attribute: name.attribute(),
				initial_json: Json.to_str(initial),
			},
		)

		## Define a U64 signal whose value is included in requests by default.
		## Browser arithmetic is exact only through JavaScript's safe-integer range.
		u64 : SignalName, U64 -> Signal(U64)
		u64 = |name, initial| Signal.(
			{
				canonical: name.canonical(),
				attribute: name.attribute(),
				initial_json: Json.to_str(initial),
			},
		)

		## Define an underscore-prefixed boolean signal. Datastar excludes these
		## signals from backend requests by default, but request filters may include
		## them; this is not a confidentiality boundary.
		excluded_bool : SignalName, Bool -> Signal(Bool)
		excluded_bool = |name, initial| Signal.(
			{
				canonical: "_${name.canonical()}",
				attribute: "_${name.attribute()}",
				initial_json: Json.to_str(initial),
			},
		)

		## Finalize this signal's checked initial value for a heterogeneous list.
		definition : Signal(a) -> SignalDef
		definition = |signal| SignalDef.(
			{
				field: "${Json.to_str(signal.canonical)}:${signal.initial_json}",
			},
		)

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
	}

	## A typed Datastar expression. Its type records the result promised by the
	## constructors used to build it; unchecked JavaScript can invalidate that
	## promise and is therefore result-specific and conspicuously named.
	Expr(a) := { source : Str }.{

		bool : Bool -> Expr(Bool)
		bool = |value| Expr.({ source: Json.to_str(value) })

		str : Str -> Expr(Str)
		str = |value| Expr.({ source: Json.to_str(value) })

		not : Expr(Bool) -> Expr(Bool)
		not = |expression| Expr.({ source: "!(${expression.source})" })

		and_also : Expr(Bool), Expr(Bool) -> Expr(Bool)
		and_also = |left, right| Expr.({ source: "(${left.source}) && (${right.source})" })

		equals : Expr(a), Expr(a) -> Expr(Bool)
		equals = |left, right| Expr.({ source: "(${left.source}) === (${right.source})" })

		disabled_when_true : Expr(Bool) -> Attribute
		disabled_when_true = |expression| Attribute.attribute("data-attr:disabled", expression.source)

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
		Attribute.attribute(
			"data-signals",
			"{${Str.join_with(definitions.map(|definition| definition.to_field()), ",")}}",
		)

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

		init : DomEvent
		init = DomEvent("init")

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

		unchecked : Str -> Action
		unchecked = |source| Action.(
			{
				source: source,
			},
		)
	}

	## A validated application route path used by a backend request action.
	RoutePath := [RoutePath(Str)].{

		parse : Str -> Try(RoutePath, [InvalidRoutePath(Str)])
		parse = |value|
			if valid_route_path(value) {
				Ok(RoutePath(value))
			} else {
				Err(InvalidRoutePath(value))
			}

		from_quote : Str -> Try(RoutePath, [BadQuotedBytes(Str)])
		from_quote = |value|
			match RoutePath.parse(value) {
				Ok(path) => Ok(path)
				Err(_) => Err(BadQuotedBytes("Datastar backend request paths must be absolute application paths without a query, fragment, line ending, NUL, or backslash"))
			}

		to_str : RoutePath -> Str
		to_str = |RoutePath(value)| value
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

	## A validated CSS selector for a targeted Datastar element operation.
	Selector := [Selector(Str)].{

		parse : Str -> Try(Selector, [InvalidSelector(Str)])
		parse = |value|
			if valid_selector(value) {
				Ok(Selector(value))
			} else {
				Err(InvalidSelector(value))
			}

		from_quote : Str -> Try(Selector, [BadQuotedBytes(Str)])
		from_quote = |value|
			match Selector.parse(value) {
				Ok(selector) => Ok(selector)
				Err(_) => Err(BadQuotedBytes("Datastar selectors must be non-empty and cannot contain NUL or line endings"))
			}

		to_str : Selector -> Str
		to_str = |Selector(value)| value
	}

	## An HTML element ID restricted to a directly selectable ASCII subset.
	## Reusing one value for the HTML attribute and patch target removes a common
	## source of selector drift.
	ElementId := [ElementId(Str)].{

		parse : Str -> Try(ElementId, [InvalidElementId(Str)])
		parse = |value|
			if valid_element_id(value) {
				Ok(ElementId(value))
			} else {
				Err(InvalidElementId(value))
			}

		from_quote : Str -> Try(ElementId, [BadQuotedBytes(Str)])
		from_quote = |value|
			match ElementId.parse(value) {
				Ok(element_id) => Ok(element_id)
				Err(_) => Err(BadQuotedBytes("Datastar element IDs must start with an ASCII letter and contain only ASCII letters, digits, hyphens, or underscores"))
			}

		attribute : ElementId -> Attribute
		attribute = |ElementId(value)| Attribute.id(value)

		patch_target : ElementId -> PatchTarget
		patch_target = |ElementId(value)| PatchTarget(Selector("#${value}"))

		descendant : ElementId, Selector -> PatchTarget
		descendant = |ElementId(value), selector| PatchTarget(Selector("#${value} ${selector.to_str()}"))
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

		remove : PatchTarget -> Sse.Event
		remove = |PatchTarget(selector)| Datastar.remove_elements(selector.to_str())
	}

	## Patch fragment elements by their own IDs using Datastar's default outer merge.
	patch_elements : Html.Fragment -> Sse.Event
	patch_elements = |fragment| Datastar.patch_elements(fragment.to_str())
}

signal_value_types_match : DatastarMarkup.Signal(a), a -> {}
signal_value_types_match = |_, _| {}

targeted_patch : Html.Fragment, DatastarMarkup.Selector, Datastar.PatchMode -> Sse.Event
targeted_patch = |fragment, selector, mode|
	Datastar.patch_elements_with(
		fragment.to_str(),
		{
			..Datastar.default_patch_elements_options,
			mode,
			selector: Select(selector.to_str()),
		},
	)

request_target_parts : DatastarMarkup.RequestTarget -> (Str, DatastarMarkup.RoutePath)
request_target_parts = |target|
	match target {
		DeleteTarget(path) => ("delete", path)
		GetTarget(path) => ("get", path)
		PatchRequestTarget(path) => ("patch", path)
		PostTarget(path) => ("post", path)
		PutTarget(path) => ("put", path)
	}

request_target_match_parts : DatastarMarkup.RequestTarget -> (Method, DatastarMarkup.RoutePath)
request_target_match_parts = |target|
	match target {
		DeleteTarget(path) => (DELETE, path)
		GetTarget(path) => (GET, path)
		PatchRequestTarget(path) => (PATCH, path)
		PostTarget(path) => (POST, path)
		PutTarget(path) => (PUT, path)
	}

valid_signal_name : Str -> Bool
valid_signal_name = |value| {
	bytes = Str.to_utf8(value)
	match bytes {
		[first, .. as rest] => ascii_letter(first) and rest.all(ascii_letter_or_digit)
		[] => Bool.False
	}
}

signal_attribute_name : Str -> Str
signal_attribute_name = |value|
	Str.from_utf8_lossy(
		Str.to_utf8(value).fold(
			[],
			|bytes, byte|
				if byte >= 65 and byte <= 90 {
					bytes.concat([45, byte + 32])
				} else {
					bytes.append(byte)
				},
		),
	)

ascii_letter : U8 -> Bool
ascii_letter = |byte| (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)

ascii_letter_or_digit : U8 -> Bool
ascii_letter_or_digit = |byte| ascii_letter(byte) or (byte >= 48 and byte <= 57)

valid_element_id : Str -> Bool
valid_element_id = |value| {
	bytes = Str.to_utf8(value)
	match bytes {
		[first, .. as rest] =>
			ascii_letter(first) and
				rest.all(|byte| ascii_letter_or_digit(byte) or byte == 45 or byte == 95)
		[] => Bool.False
	}
}

valid_route_path : Str -> Bool
valid_route_path = |value| {
	bytes = Str.to_utf8(value)
	bytes.len() > 0 and
		bytes.first() == Ok(47) and
			Bool.not(Str.starts_with(value, "//")) and
				Bool.not(Str.contains(value, "?")) and
					Bool.not(Str.contains(value, "#")) and
						Bool.not(Str.contains(value, "\\")) and
							Bool.not(bytes.any(|byte| byte == 0 or byte == 10 or byte == 13))
}

valid_selector : Str -> Bool
valid_selector = |value|
	Bool.not(value.is_empty()) and
		Bool.not(Str.to_utf8(value).any(|byte| byte == 0 or byte == 10 or byte == 13))

expect {
	page = DatastarMarkup.Signal.u64("page", 0)
	fetching = DatastarMarkup.Signal.excluded_bool("fetching", Bool.False)
	attribute = DatastarMarkup.signals([page.definition(), fetching.definition()])

	Attribute.raw_name(attribute) == "data-signals" and
		Attribute.raw_value(attribute) == "{\"page\":0,\"_fetching\":false}"
}

expect {
	message = DatastarMarkup.Signal.str("message", "quote \" newline\n")
	attribute = DatastarMarkup.signals([message.definition()])

	Attribute.raw_value(attribute) == "{\"message\":\"quote \\\" newline\\n\"}"
}

expect {
	fetching = DatastarMarkup.Signal.excluded_bool("fetching", Bool.False)
	target = DatastarMarkup.RequestTarget.get("/examples/load")
	action = target.request().unless(fetching.expr()).on_click()

	Attribute.raw_value(action) == "!($_fetching) && @get(\"/examples/load\")"
}

expect {
	match DatastarMarkup.SignalName.from_quote("activeSearch") {
		Ok(name) => name.attribute() == "active-search"
		Err(_) => Bool.False
	}
}

expect {
	agents : DatastarMarkup.ElementId
	agents = "agents"
	selector = agents.descendant("tbody")
	fragment = Html.render_fragment([Html.tr([], [Html.td([], [Html.text("Agent")])])])
	bytes = selector.append(fragment).to_bytes()

	Str.from_utf8_lossy(bytes) == "event: datastar-patch-elements\ndata: selector #agents tbody\ndata: mode append\ndata: elements <tr><td>Agent</td></tr>\n\n"
}

expect {
	page = DatastarMarkup.Signal.u64("page", 0)
	fetching = DatastarMarkup.Signal.bool("fetching", Bool.False)
	event = DatastarMarkup.patch_signals([
		page.update(1),
		fetching.update(Bool.True),
	])

	Str.from_utf8_lossy(event.to_bytes()) == "event: datastar-patch-signals\ndata: signals {\"page\":1,\"fetching\":true}\n\n"
}

expect {
	target = DatastarMarkup.RequestTarget.get("/")
	input = DatastarMarkup.DomEvent.input.debounce_milliseconds(200)
	attribute = target.request().on(input)

	Attribute.raw_name(attribute) == "data-on:input__debounce.200ms" and
		Attribute.raw_value(attribute) == "@get(\"/\")"
}

expect {
	match DatastarMarkup.RoutePath.parse("/dynamic/path") {
		Ok(path) => path.to_str() == "/dynamic/path"
		Err(_) => Bool.False
	}
}
