import ./InternalDatastarName

## A validated canonical Datastar signal name and its attribute spelling.
SignalName :: { attribute : Str, canonical : Str }.{

	## Validate a dynamically obtained canonical signal name.
	parse : Str -> Try(SignalName, [InvalidSignalName(Str)])
	parse = |value|
		if InternalDatastarName.valid_signal(value) {
			Ok(SignalName.({ canonical: value, attribute: InternalDatastarName.attribute_name(value) }))
		} else {
			Err(InvalidSignalName(value))
		}

	## Validate a quoted signal name during compile-time evaluation.
	from_quote : Str -> Try(SignalName, [BadQuotedBytes(Str)])
	from_quote = |value|
		match SignalName.parse(value) {
			Ok(name) => Ok(name)
			Err(_) => Err(BadQuotedBytes("Datastar signal names must start with an ASCII letter and contain only ASCII letters or digits"))
		}

	canonical : SignalName -> Str
	canonical = |name| name.canonical

	attribute : SignalName -> Str
	attribute = |name| name.attribute
}

expect {
	match SignalName.from_quote("activeSearch") {
		Ok(name) => name.canonical() == "activeSearch" and name.attribute() == "active-search"
		Err(_) => Bool.False
	}
}
