import Attribute

## The stable internal representation behind [`Html.Node`](#Html.Node).
HtmlNode := [
	Text(Str),
	Raw(Str),
	Element(Str, List(Attribute), List(HtmlNode)),
	VoidElement(Str, List(Attribute)),
]

## Build and render small server-generated HTML documents.
##
## Text and attribute values are escaped by default. Tag and attribute names
## supplied to the generic constructors are trusted syntax and must be
## constants, not user input.
##
## ```roc
## page = Html.html([], [
##     Html.body([], [
##         Html.h1([], [Html.text("Hello <Roc>")]),
##         Html.a([Attribute.href("/account")], [Html.text("Account")]),
##     ]),
## ])
##
## response = Response.from_status(200)
##     .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
##     .with_body(Str.to_utf8(Html.render(page)))
## ```
Html := [].{

	## An HTML node. Prefer this module's constructors so text and attribute
	## values are escaped consistently.
	Node : HtmlNode

	## Construct escaped text. Use this for all untrusted or dynamic text.
	text : Str -> HtmlNode
	text = |value| Text(value)

	## Insert trusted HTML without escaping it.
	##
	## Never pass user input or other untrusted content to this function.
	dangerously_include_unescaped_html : Str -> HtmlNode
	dangerously_include_unescaped_html = |value| Raw(value)

	## Construct a normal element with a trusted tag name.
	element : Str, List(Attribute), List(HtmlNode) -> HtmlNode
	element = |tag, attrs, children| Element(tag, attrs, children)

	## Construct a void element with a trusted tag name.
	void_element : Str, List(Attribute) -> HtmlNode
	void_element = |tag, attrs| VoidElement(tag, attrs)

	## Render a complete HTML document beginning with `<!DOCTYPE html>`.
	render : HtmlNode -> Str
	render = |node| Str.concat("<!DOCTYPE html>", render_without_doc_type(node))

	## Render a node without adding a document type declaration.
	render_without_doc_type : HtmlNode -> Str
	render_without_doc_type = |node|
		match node {
			Text(value) => escape_text(value)
			Raw(value) => value
			Element(tag, attrs, children) =>
				"<${tag}${render_attributes(attrs)}>${render_children(children)}</${tag}>"
			VoidElement(tag, attrs) =>
				"<${tag}${render_attributes(attrs)}>"
			}

	## Construct an `html` element.
	html = |attrs, children| element("html", attrs, children)

	## Construct a `head` element.
	head = |attrs, children| element("head", attrs, children)

	## Construct a `body` element.
	body = |attrs, children| element("body", attrs, children)

	## Construct a `title` element.
	title = |attrs, children| element("title", attrs, children)

	## Construct a `header` element.
	header = |attrs, children| element("header", attrs, children)

	## Construct a `nav` element.
	nav = |attrs, children| element("nav", attrs, children)

	## Construct a `main` element.
	main = |attrs, children| element("main", attrs, children)

	## Construct a `div` element.
	div = |attrs, children| element("div", attrs, children)

	## Construct a `span` element.
	span = |attrs, children| element("span", attrs, children)

	## Construct a `p` element.
	p = |attrs, children| element("p", attrs, children)

	## Construct an `a` element.
	a = |attrs, children| element("a", attrs, children)

	## Construct a `ul` element.
	ul = |attrs, children| element("ul", attrs, children)

	## Construct an `li` element.
	li = |attrs, children| element("li", attrs, children)

	## Construct an `h1` element.
	h1 = |attrs, children| element("h1", attrs, children)

	## Construct an `h2` element.
	h2 = |attrs, children| element("h2", attrs, children)

	## Construct an `h3` element.
	h3 = |attrs, children| element("h3", attrs, children)

	## Construct an `h4` element.
	h4 = |attrs, children| element("h4", attrs, children)

	## Construct an `h5` element.
	h5 = |attrs, children| element("h5", attrs, children)

	## Construct an `h6` element.
	h6 = |attrs, children| element("h6", attrs, children)

	## Construct a `form` element.
	form = |attrs, children| element("form", attrs, children)

	## Construct a `button` element.
	button = |attrs, children| element("button", attrs, children)

	## Construct a `label` element.
	label = |attrs, children| element("label", attrs, children)

	## Construct a `table` element.
	table = |attrs, children| element("table", attrs, children)

	## Construct a `thead` element.
	thead = |attrs, children| element("thead", attrs, children)

	## Construct a `tbody` element.
	tbody = |attrs, children| element("tbody", attrs, children)

	## Construct a `tr` element.
	tr = |attrs, children| element("tr", attrs, children)

	## Construct a `th` element.
	th = |attrs, children| element("th", attrs, children)

	## Construct a `td` element.
	td = |attrs, children| element("td", attrs, children)

	## Construct an `svg` element.
	svg = |attrs, children| element("svg", attrs, children)

	## Construct a `select` element.
	select = |attrs, children| element("select", attrs, children)

	## Construct an `option` element.
	option = |attrs, children| element("option", attrs, children)

	## Construct an `input` void element.
	input = |attrs| void_element("input", attrs)

	## Construct a `meta` void element.
	meta = |attrs| void_element("meta", attrs)

	## Construct a `link` void element.
	link = |attrs| void_element("link", attrs)

	## Construct a `br` void element.
	br = |attrs| void_element("br", attrs)
}

render_children : List(HtmlNode) -> Str
render_children = |children| Str.join_with(children.map(Html.render_without_doc_type), "")

render_attributes : List(Attribute) -> Str
render_attributes = |attrs|
	if attrs.is_empty() {
		""
	} else {
		" ${Str.join_with(attrs.map(render_attribute), " ")}"
	}

render_attribute : Attribute -> Str
render_attribute = |attr| "${Attribute.raw_name(attr)}=\"${escape_attribute(Attribute.raw_value(attr))}\""

escape_text : Str -> Str
escape_text = |value| escape_html_bytes(value, Bool.False)

escape_attribute : Str -> Str
escape_attribute = |value| escape_html_bytes(value, Bool.True)

escape_html_bytes : Str, Bool -> Str
escape_html_bytes = |value, escape_quotes| {
	escaped_bytes = 
		Str.to_utf8(value).fold(
			[],
			|bytes, byte|
				match byte {
					38 => bytes.concat([38, 97, 109, 112, 59])
					60 => bytes.concat([38, 108, 116, 59])
					62 => bytes.concat([38, 103, 116, 59])
					34 if escape_quotes => bytes.concat([38, 113, 117, 111, 116, 59])
					39 if escape_quotes => bytes.concat([38, 35, 51, 57, 59])
					10 if escape_quotes => bytes.concat([38, 35, 49, 48, 59])
					13 if escape_quotes => bytes.concat([38, 35, 49, 51, 59])
					_ => bytes.append(byte)
				},
		)

	match Str.from_utf8(escaped_bytes) {
		Ok(str) => str
		Err(_) => ""
	}
}

## Text and attribute values are escaped in their respective HTML contexts.
expect {
	node = Html.div(
		[Attribute.class("\"<&'\n\r")],
		[Html.text("<Roc & friends>")],
	)

	Html.render(node)
		== "<!DOCTYPE html><div class=\"&quot;&lt;&amp;&#39;&#10;&#13;\">&lt;Roc &amp; friends&gt;</div>"
}

## Trusted raw HTML is the explicit escape hatch.
expect {
	Html.render_without_doc_type(
		Html.div([], [Html.dangerously_include_unescaped_html("<strong>trusted</strong>")]),
	) == "<div><strong>trusted</strong></div>"
}
