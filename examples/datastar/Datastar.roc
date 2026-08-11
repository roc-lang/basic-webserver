import pf.Sse
import pf.MultipartFormData
import pf.Server
import http.Response

## Typed constructors for the Datastar SSE protocol. Applications provide
## domain HTML or signal JSON; this module owns canonical event names and
## per-line field framing.
Datastar :: [].{

	## Default maximum Datastar signals document: 64 KiB.
	default_signals_limit_bytes : U64
	default_signals_limit_bytes = 64 * 1024

	SignalsError := [
		InvalidSignals(Str),
		MalformedSignalsQuery,
		MissingSignals,
		SignalsBodyFailed(Str),
		UnsupportedSignalsMethod,
	]

	## Whether the request carries Datastar's advisory request header. This is
	## a client hint only; it is not authentication or CSRF protection.
	is_request : Server.Request -> Bool
	is_request = |request| has_datastar_header(request.headers())

	## Decode the complete bounded Datastar signals object into the type inferred
	## by the caller. GET and DELETE read the `datastar` query parameter;
	## POST, PUT, and PATCH read a JSON request body.
	read_signals! = |request| read_signals_with_limit!(request, default_signals_limit_bytes)

	## Decode Datastar signals with an application-selected inclusive body limit.
	read_signals_with_limit! = |request, max_bytes| {
		json =
			match request.method() {
				GET => signals_from_query(request)?
				DELETE => signals_from_query(request)?
				POST => signals_from_body!(request, max_bytes)?
				PUT => signals_from_body!(request, max_bytes)?
				PATCH => signals_from_body!(request, max_bytes)?
				_ => return Err(UnsupportedSignalsMethod)
			}

		match Json.parse(json) {
			Ok(signals) => Ok(signals)
			Err(err) => Err(InvalidSignals(Str.inspect(err)))
		}
	}

	## Return a complete finite Datastar action as an ordinary bounded response.
	## This avoids consuming a retained-stream slot when every event is already
	## available.
	respond : List(Sse.Event) -> Server.Outcome
	respond = |events|
		Server.respond(
			Response.from_status(200)
				.with_headers([
					{ name: "Content-Type", value: "text/event-stream" },
					{ name: "Cache-Control", value: "no-cache" },
				])
				.with_body(event_bytes(events)),
		)

	PatchMode := [After, Append, Before, Inner, Outer, Prepend, Remove, Replace].{
		after : PatchMode
		after = After

		append : PatchMode
		append = Append

		before : PatchMode
		before = Before

		inner : PatchMode
		inner = Inner

		outer : PatchMode
		outer = Outer

		prepend : PatchMode
		prepend = Prepend

		replace : PatchMode
		replace = Replace
	}

	Selector := [FromElementIds, Select(Str)]

	Namespace := [Html, MathMl, Svg]

	ViewTransition := [NoViewTransition, ViewTransition([CurrentTarget, TransitionTarget(Str)])]

	PatchElementsOptions := {
		event : Sse.EventOptions,
		mode : PatchMode,
		namespace : Namespace,
		selector : Selector,
		view_transition : ViewTransition,
	}

	default_patch_elements_options : PatchElementsOptions
	default_patch_elements_options = {
		event: Sse.default_event_options,
		mode: Outer,
		namespace: Html,
		selector: FromElementIds,
		view_transition: NoViewTransition,
	}

	PatchSignalsOptions := {
		event : Sse.EventOptions,
		only_if_missing : Bool,
	}

	default_patch_signals_options : PatchSignalsOptions
	default_patch_signals_options = {
		event: Sse.default_event_options,
		only_if_missing: Bool.False,
	}

	RemoveElementsOptions := {
		event : Sse.EventOptions,
		view_transition : ViewTransition,
	}

	default_remove_elements_options : RemoveElementsOptions
	default_remove_elements_options = {
		event: Sse.default_event_options,
		view_transition: NoViewTransition,
	}

	## Patch elements using Datastar's default ID-based outer merge.
	patch_elements : Str -> Sse.Event
	patch_elements = |html| Sse.Event.keyed("datastar-patch-elements", "elements", html)

	## Patch elements with an explicit selector, patch mode, or view transition.
	patch_elements_with : Str, PatchElementsOptions -> Sse.Event
	patch_elements_with = |html, options| {
		selector_fields =
			match options.selector {
				FromElementIds => []
				Select(selector) => ["selector ${single_line(selector)}"]
			}

		mode_fields =
			match options.mode {
				Outer => []
				Inner => ["mode inner"]
				Remove => ["mode remove"]
				Replace => ["mode replace"]
				Prepend => ["mode prepend"]
				Append => ["mode append"]
				Before => ["mode before"]
				After => ["mode after"]
			}

		namespace_fields =
			match options.namespace {
				Html => []
				Svg => ["namespace svg"]
				MathMl => ["namespace mathml"]
			}

		transition_fields =
			match options.view_transition {
				NoViewTransition => []
				ViewTransition(CurrentTarget) => ["useViewTransition true"]
				ViewTransition(TransitionTarget(selector)) => [
					"useViewTransition true",
					"viewTransitionSelector ${single_line(selector)}",
				]
			}

		element_fields = keyed_lines("elements", html)
		Sse.Event.named_with(
			"datastar-patch-elements",
			List.concat(
				List.concat(List.concat(List.concat(selector_fields, mode_fields), namespace_fields), transition_fields),
				element_fields,
			),
			options.event,
		)
	}

	## Remove the elements selected by a CSS selector.
	remove_elements : Str -> Sse.Event
	remove_elements = |selector| remove_elements_with(selector, default_remove_elements_options)

	## Remove selected elements with reconnect or view-transition options.
	remove_elements_with : Str, RemoveElementsOptions -> Sse.Event
	remove_elements_with = |selector, options| {
		transition_fields =
			match options.view_transition {
				NoViewTransition => []
				ViewTransition(CurrentTarget) => ["useViewTransition true"]
				ViewTransition(TransitionTarget(transition_selector)) => [
					"useViewTransition true",
					"viewTransitionSelector ${single_line(transition_selector)}",
				]
			}
		Sse.Event.named_with(
			"datastar-patch-elements",
			List.concat(["mode remove", "selector ${single_line(selector)}"], transition_fields),
			options.event,
		)
	}

	## Patch signals from a JSON object. Multiline input preserves each line as
	## a separate Datastar `signals` field.
	patch_signals : Str -> Sse.Event
	patch_signals = |signals|
		Sse.Event.keyed("datastar-patch-signals", "signals", signals)

	## Patch signals with optional only-if-missing and reconnect metadata.
	patch_signals_with : Str, PatchSignalsOptions -> Sse.Event
	patch_signals_with = |signals, options| {
		missing_fields =
			if options.only_if_missing {
				["onlyIfMissing true"]
			} else {
				[]
			}
		Sse.Event.named_with(
			"datastar-patch-signals",
			List.concat(missing_fields, keyed_lines("signals", signals)),
			options.event,
		)
	}

}

signals_from_query : Server.Request -> Try(Str, Datastar.SignalsError)
signals_from_query = |request| {
	raw_query =
		match request.target() {
			Resource({ raw_query: Present(query), .. }) => query
			_ => return Err(MissingSignals)
		}
	params =
		MultipartFormData.parse_form_url_encoded(Str.to_utf8(raw_query))
			? |_err| MalformedSignalsQuery

	match Dict.get(params, "datastar") {
		Ok(json) if Bool.not(json.is_empty()) => Ok(json)
		_ => Err(MissingSignals)
	}
}

signals_from_body! : Server.Request, U64 => Try(Str, Datastar.SignalsError)
signals_from_body! = |request, max_bytes| {
	body = request.body().with_limit(max_bytes).read_all!()
		? |err| SignalsBodyFailed(Str.inspect(err))
	match Str.from_utf8(body) {
		Ok(json) => Ok(json)
		Err(_) => Err(InvalidSignals("signals JSON must be valid UTF-8"))
	}
}

has_datastar_header : List({ name : Str, value : Str }) -> Bool
has_datastar_header = |headers|
	match headers {
		[] => Bool.False
		[{ name, value }, .. as rest] =>
			if ascii_lower(name) == "datastar-request" and ascii_lower(value) == "true" {
				Bool.True
			} else {
				has_datastar_header(rest)
			}
		}

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

event_bytes : List(Sse.Event) -> List(U8)
event_bytes = |events|
	match events {
		[] => []
		[first, .. as rest] => List.concat(first.to_bytes(), event_bytes(rest))
	}

keyed_lines : Str, Str -> List(Str)
keyed_lines = |key, value| {
	lf = Str.join_with(Str.split_on(value, "\r\n"), "\n")
	normalized = Str.join_with(Str.split_on(lf, "\r"), "\n")
	Str.split_on(normalized, "\n").map(|line| "${key} ${line}")
}

single_line : Str -> Str
single_line = |value|
	Str.join_with(Str.split_on(Str.join_with(Str.split_on(value, "\r"), ""), "\n"), "")
