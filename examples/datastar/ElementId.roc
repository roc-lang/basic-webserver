import pf.Attribute
import ./DatastarMarkup
import pf.Html
import ./InternalDatastarName
import ./Selector

## An HTML element ID restricted to a directly selectable ASCII subset.
##
## Reusing one value for the HTML attribute and Datastar patch target removes a
## common source of selector drift.
ElementId :: Str.{

	parse : Str -> Try(ElementId, [InvalidElementId(Str)])
	parse = |value|
		if InternalDatastarName.valid_element_id(value) {
			Ok(ElementId.(value))
		} else {
			Err(InvalidElementId(value))
		}

	from_quote : Str -> Try(ElementId, [BadQuotedBytes(Str)])
	from_quote = |value|
		match ElementId.parse(value) {
			Ok(element_id) => Ok(element_id)
			Err(_) => Err(BadQuotedBytes("Datastar element IDs must start with an ASCII letter and contain only ASCII letters, digits, hyphens, or underscores"))
		}

	to_str : ElementId -> Str
	to_str = |ElementId.(value)| value

	attribute : ElementId -> Attribute
	attribute = |ElementId.(value)| Attribute.id(value)

	patch_target : ElementId -> DatastarMarkup.PatchTarget
	patch_target = |ElementId.(value)| DatastarMarkup.PatchTarget.css(selector_from_parts("#${value}"))

	descendant : ElementId, Selector -> DatastarMarkup.PatchTarget
	descendant = |ElementId.(value), selector|
		DatastarMarkup.PatchTarget.css(selector_from_parts("#${value} ${selector.to_str()}"))
}

selector_from_parts : Str -> Selector
selector_from_parts = |value|
	match Selector.parse(value) {
		Ok(selector) => selector
		Err(_) => {
			crash "ElementId produced an invalid selector"
		}
	}

expect {
	agents : ElementId
	agents = "agents"
	selector = agents.descendant("tbody")
	fragment = Html.render_fragment([Html.tr([], [Html.td([], [Html.text("Agent")])])])
	bytes = selector.append(fragment).to_bytes()

	agents.to_str() == "agents" and
		Str.from_utf8_lossy(bytes) == "event: datastar-patch-elements\ndata: selector #agents tbody\ndata: mode append\ndata: elements <tr><td>Agent</td></tr>\n\n"
}
