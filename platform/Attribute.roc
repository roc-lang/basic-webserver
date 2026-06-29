Attribute := [Attribute(Str, Str)].{
    attribute : Str, Str -> Attribute
    attribute = |key, val| Attribute(key, val)

    raw_name : Attribute -> Str
    raw_name = |Attribute(name, _)| name

    raw_value : Attribute -> Str
    raw_value = |Attribute(_, value)| value

    class : Str -> Attribute
    class = |val| attribute("class", val)

    id : Str -> Attribute
    id = |val| attribute("id", val)

    href : Str -> Attribute
    href = |val| attribute("href", val)

    src : Str -> Attribute
    src = |val| attribute("src", val)

    rel : Str -> Attribute
    rel = |val| attribute("rel", val)

    name : Str -> Attribute
    name = |val| attribute("name", val)

    width : Str -> Attribute
    width = |val| attribute("width", val)

    height : Str -> Attribute
    height = |val| attribute("height", val)

    style : Str -> Attribute
    style = |val| attribute("style", val)

    type : Str -> Attribute
    type = |val| attribute("type", val)

    value : Str -> Attribute
    value = |val| attribute("value", val)

    role : Str -> Attribute
    role = |val| attribute("role", val)

    for_ : Str -> Attribute
    for_ = |val| attribute("for", val)

    action : Str -> Attribute
    action = |val| attribute("action", val)

    method : Str -> Attribute
    method = |val| attribute("method", val)

    min : Str -> Attribute
    min = |val| attribute("min", val)

    max : Str -> Attribute
    max = |val| attribute("max", val)

    hidden : Str -> Attribute
    hidden = |val| attribute("hidden", val)
}
