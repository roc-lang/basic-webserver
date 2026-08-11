## A validated application route path used by a Datastar backend request.
RoutePath :: Str.{

	parse : Str -> Try(RoutePath, [InvalidRoutePath(Str)])
	parse = |value|
		if valid_route_path(value) {
			Ok(RoutePath.(value))
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
	to_str = |RoutePath.(value)| value
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

expect {
	match RoutePath.parse("/") {
		Ok(path) => path.to_str() == "/"
		Err(_) => Bool.False
	}
}
