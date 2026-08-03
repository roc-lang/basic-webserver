import Sse

## Typed constructors for the Datastar SSE protocol. Applications provide
## domain HTML or signal JSON; this module owns canonical event names and
## per-line field framing.
Datastar :: [].{
	PatchMode := [After, Append, Before, Inner, Outer, Prepend, Remove, Replace]

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
		use_view_transition : Bool,
	}

	default_remove_elements_options : RemoveElementsOptions
	default_remove_elements_options = {
		event: Sse.default_event_options,
		use_view_transition: Bool.False,
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
			if options.use_view_transition {
				["useViewTransition true"]
			} else {
				[]
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

keyed_lines : Str, Str -> List(Str)
keyed_lines = |key, value| {
	lf = Str.join_with(Str.split_on(value, "\r\n"), "\n")
	normalized = Str.join_with(Str.split_on(lf, "\r"), "\n")
	Str.split_on(normalized, "\n").map(|line| "${key} ${line}")
}

single_line : Str -> Str
single_line = |value|
	Str.join_with(Str.split_on(Str.join_with(Str.split_on(value, "\r"), ""), "\n"), "")
