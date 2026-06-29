import Attribute exposing [Attribute]

HtmlNode := [
    Text(Str),
    Raw(Str),
    Element(Str, List(Attribute), List(HtmlNode)),
    VoidElement(Str, List(Attribute)),
]

Html := [].{
    Node : HtmlNode

    text : Str -> HtmlNode
    text = |value| Text(value)

    dangerously_include_unescaped_html : Str -> HtmlNode
    dangerously_include_unescaped_html = |value| Raw(value)

    element : Str, List(Attribute), List(HtmlNode) -> HtmlNode
    element = |tag, attrs, children| Element(tag, attrs, children)

    void_element : Str, List(Attribute) -> HtmlNode
    void_element = |tag, attrs| VoidElement(tag, attrs)

    render : HtmlNode -> Str
    render = |node| Str.concat("<!DOCTYPE html>", render_without_doc_type(node))

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

    html = |attrs, children| element("html", attrs, children)
    head = |attrs, children| element("head", attrs, children)
    body = |attrs, children| element("body", attrs, children)
    title = |attrs, children| element("title", attrs, children)
    header = |attrs, children| element("header", attrs, children)
    nav = |attrs, children| element("nav", attrs, children)
    main = |attrs, children| element("main", attrs, children)
    div = |attrs, children| element("div", attrs, children)
    span = |attrs, children| element("span", attrs, children)
    p = |attrs, children| element("p", attrs, children)
    a = |attrs, children| element("a", attrs, children)
    ul = |attrs, children| element("ul", attrs, children)
    li = |attrs, children| element("li", attrs, children)
    h1 = |attrs, children| element("h1", attrs, children)
    h2 = |attrs, children| element("h2", attrs, children)
    h3 = |attrs, children| element("h3", attrs, children)
    h4 = |attrs, children| element("h4", attrs, children)
    h5 = |attrs, children| element("h5", attrs, children)
    h6 = |attrs, children| element("h6", attrs, children)
    form = |attrs, children| element("form", attrs, children)
    button = |attrs, children| element("button", attrs, children)
    label = |attrs, children| element("label", attrs, children)
    table = |attrs, children| element("table", attrs, children)
    thead = |attrs, children| element("thead", attrs, children)
    tbody = |attrs, children| element("tbody", attrs, children)
    tr = |attrs, children| element("tr", attrs, children)
    th = |attrs, children| element("th", attrs, children)
    td = |attrs, children| element("td", attrs, children)
    svg = |attrs, children| element("svg", attrs, children)
    select = |attrs, children| element("select", attrs, children)
    option = |attrs, children| element("option", attrs, children)

    input = |attrs| void_element("input", attrs)
    meta = |attrs| void_element("meta", attrs)
    link = |attrs| void_element("link", attrs)
    br = |attrs| void_element("br", attrs)
}

render_children : List(HtmlNode) -> Str
render_children = |children| Str.join_with(List.map(children, Html.render_without_doc_type), "")

render_attributes : List(Attribute) -> Str
render_attributes = |attrs|
    if List.is_empty(attrs) {
        ""
    } else {
        " ${Str.join_with(List.map(attrs, render_attribute), " ")}"
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
        List.fold(
            Str.to_utf8(value),
            [],
            |bytes, byte|
                if byte == 38 {
                    List.concat(bytes, [38, 97, 109, 112, 59])
                } else if byte == 60 {
                    List.concat(bytes, [38, 108, 116, 59])
                } else if byte == 62 {
                    List.concat(bytes, [38, 103, 116, 59])
                } else if escape_quotes and byte == 34 {
                    List.concat(bytes, [38, 113, 117, 111, 116, 59])
                } else if escape_quotes and byte == 39 {
                    List.concat(bytes, [38, 35, 51, 57, 59])
                } else if escape_quotes and byte == 10 {
                    List.concat(bytes, [38, 35, 49, 48, 59])
                } else if escape_quotes and byte == 13 {
                    List.concat(bytes, [38, 35, 49, 51, 59])
                } else {
                    List.append(bytes, byte)
                },
        )

    match Str.from_utf8(escaped_bytes) {
        Ok(str) => str
        Err(_) => ""
    }
}
