## Construct HTML attributes for use with [`Html`](../Html/).
##
## Attribute values are escaped when rendered. Attribute names passed to
## [`attribute`](#Attribute.attribute) are emitted as HTML syntax and must be
## trusted constants, not user input.
Attribute := [Attribute(Str, Str)].{

	## Construct an attribute with a trusted HTML name and an arbitrary value.
	attribute : Str, Str -> Attribute
	attribute = |key, val| Attribute(key, val)

	## Return the attribute name exactly as supplied.
	raw_name : Attribute -> Str
	raw_name = |Attribute(name, _)| name

	## Return the unescaped attribute value exactly as supplied.
	raw_value : Attribute -> Str
	raw_value = |Attribute(_, value)| value

	## Set the HTML `class` attribute.
	class : Str -> Attribute
	class = |val| attribute("class", val)

	## Set the HTML `id` attribute.
	id : Str -> Attribute
	id = |val| attribute("id", val)

	## Set the HTML `href` attribute.
	href : Str -> Attribute
	href = |val| attribute("href", val)

	## Set the HTML `src` attribute.
	src : Str -> Attribute
	src = |val| attribute("src", val)

	## Set the HTML `rel` attribute.
	rel : Str -> Attribute
	rel = |val| attribute("rel", val)

	## Set the HTML `name` attribute.
	name : Str -> Attribute
	name = |val| attribute("name", val)

	## Set the HTML `width` attribute.
	width : Str -> Attribute
	width = |val| attribute("width", val)

	## Set the HTML `height` attribute.
	height : Str -> Attribute
	height = |val| attribute("height", val)

	## Set the HTML `style` attribute.
	style : Str -> Attribute
	style = |val| attribute("style", val)

	## Set the HTML `type` attribute.
	type : Str -> Attribute
	type = |val| attribute("type", val)

	## Set the HTML `value` attribute.
	value : Str -> Attribute
	value = |val| attribute("value", val)

	## Set the HTML `role` attribute.
	role : Str -> Attribute
	role = |val| attribute("role", val)

	## Set the HTML `for` attribute. The trailing underscore avoids the Roc
	## keyword.
	for_ : Str -> Attribute
	for_ = |val| attribute("for", val)

	## Set the HTML form `action` attribute.
	action : Str -> Attribute
	action = |val| attribute("action", val)

	## Set the HTML form `method` attribute.
	method : Str -> Attribute
	method = |val| attribute("method", val)

	## Set the HTML `min` attribute.
	min : Str -> Attribute
	min = |val| attribute("min", val)

	## Set the HTML `max` attribute.
	max : Str -> Attribute
	max = |val| attribute("max", val)

	## Set the HTML `hidden` attribute.
	hidden : Str -> Attribute
	hidden = |val| attribute("hidden", val)

	## Disable a form control. HTML boolean attributes are enabled by their
	## presence, so the canonical value is the empty string.
	disabled : Attribute
	disabled = attribute("disabled", "")
}
