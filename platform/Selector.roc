## A validated CSS selector for a targeted Datastar element operation.
##
## This type excludes empty and line-breaking values; it does not claim to
## implement a complete CSS parser.
Selector :: Str.{

	parse : Str -> Try(Selector, [InvalidSelector(Str)])
	parse = |value|
		if valid_selector(value) {
			Ok(Selector.(value))
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
	to_str = |Selector.(value)| value
}

valid_selector : Str -> Bool
valid_selector = |value|
	Bool.not(value.is_empty()) and
		Bool.not(Str.to_utf8(value).any(|byte| byte == 0 or byte == 10 or byte == 13))

expect {
	match Selector.parse("#agents tbody") {
		Ok(selector) => selector.to_str() == "#agents tbody"
		Err(_) => Bool.False
	}
}
