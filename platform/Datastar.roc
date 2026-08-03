import Sse

## Typed constructors for the Datastar SSE protocol. Applications provide
## domain HTML or signal JSON; this module owns canonical event names and
## per-line field framing.
Datastar :: [].{
	PatchMode := [After, Append, Before, Inner, Outer, Prepend, Remove, Replace]

	Selector := [FromElementIds, Select(Str)]

	PatchElementsOptions := {
		mode : PatchMode,
		selector : Selector,
		use_view_transition : Bool,
	}

	default_patch_elements_options : PatchElementsOptions
	default_patch_elements_options = {
		mode: Outer,
		selector: FromElementIds,
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
				Select(selector) => ["selector ${selector}"]
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

		transition_fields =
			if options.use_view_transition {
				["useViewTransition true"]
			} else {
				[]
			}

		element_fields = keyed_lines("elements", html)
		Sse.Event.named(
			"datastar-patch-elements",
			List.concat(
				List.concat(List.concat(selector_fields, mode_fields), transition_fields),
				element_fields,
			),
		)
	}

	## Patch signals from a JSON object. Multiline input preserves each line as
	## a separate Datastar `signals` field.
	patch_signals : Str -> Sse.Event
	patch_signals = |signals|
		Sse.Event.keyed("datastar-patch-signals", "signals", signals)

}

keyed_lines : Str, Str -> List(Str)
keyed_lines = |key, value| {
	lf = Str.join_with(Str.split_on(value, "\r\n"), "\n")
	normalized = Str.join_with(Str.split_on(lf, "\r"), "\n")
	Str.split_on(normalized, "\n").map(|line| "${key} ${line}")
}
