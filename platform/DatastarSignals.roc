import Attribute
import DatastarMarkup
import DatastarMarkup.Signal
import DatastarMarkup.SignalDef
import SignalName

## A composable collection of checked Datastar signal definitions.
##
## Roc record-builder syntax uses `map2` to retain a typed record of signal
## handles while accumulating the initial definitions rendered on an element.
DatastarSignals(a) :: { definitions : List(SignalDef), handles : a }.{

	## Add an existing boolean handle and its checked initial value.
	define_bool : Signal(Bool), Bool -> DatastarSignals(Signal(Bool))
	define_bool = |signal, initial| DatastarSignals.(
		{
			definitions: [signal.definition(initial)],
			handles: signal,
		},
	)

	## Add an existing string handle and its checked initial value.
	define_str : Signal(Str), Str -> DatastarSignals(Signal(Str))
	define_str = |signal, initial| DatastarSignals.(
		{
			definitions: [signal.definition(initial)],
			handles: signal,
		},
	)

	## Add an existing U64 handle and its checked initial value.
	define_u64 : Signal(U64), U64 -> DatastarSignals(Signal(U64))
	define_u64 = |signal, initial| DatastarSignals.(
		{
			definitions: [signal.definition(initial)],
			handles: signal,
		},
	)

	## Add an existing list-of-booleans handle and its checked initial value.
	define_bool_list : Signal(List(Bool)), List(Bool) -> DatastarSignals(Signal(List(Bool)))
	define_bool_list = |signal, initial| DatastarSignals.(
		{
			definitions: [signal.definition(initial)],
			handles: signal,
		},
	)

	## Define and collect a boolean signal.
	bool : SignalName, Bool -> DatastarSignals(Signal(Bool))
	bool = |name, initial| DatastarSignals.define_bool(Signal.bool(name), initial)

	## Define and collect a string signal.
	str : SignalName, Str -> DatastarSignals(Signal(Str))
	str = |name, initial| DatastarSignals.define_str(Signal.str(name), initial)

	## Define and collect a U64 signal.
	u64 : SignalName, U64 -> DatastarSignals(Signal(U64))
	u64 = |name, initial| DatastarSignals.define_u64(Signal.u64(name), initial)

	## Define and collect a list-of-booleans signal.
	bool_list : SignalName, List(Bool) -> DatastarSignals(Signal(List(Bool)))
	bool_list = |name, initial| DatastarSignals.define_bool_list(Signal.bool_list(name), initial)

	## Define and collect an underscore-prefixed boolean signal.
	excluded_bool : SignalName, Bool -> DatastarSignals(Signal(Bool))
	excluded_bool = |name, initial| DatastarSignals.define_bool(Signal.excluded_bool(name), initial)

	## Transform the retained handle value without changing definitions.
	map : DatastarSignals(a), (a -> b) -> DatastarSignals(b)
	map = |signals, transform| DatastarSignals.(
		{
			definitions: signals.definitions,
			handles: transform(signals.handles),
		},
	)

	## Combine definitions and retain the record constructed by Roc's builder.
	map2 : DatastarSignals(a), DatastarSignals(b), (a, b -> c) -> DatastarSignals(c)
	map2 = |left, right, combine| DatastarSignals.(
		{
			definitions: List.concat(left.definitions, right.definitions),
			handles: combine(left.handles, right.handles),
		},
	)

	## Return the typed record of handles constructed by the record builder.
	handles : DatastarSignals(a) -> a
	handles = |signals| signals.handles

	## Render definitions with normal Datastar merge semantics.
	attribute : DatastarSignals(a) -> Attribute
	attribute = |signals| DatastarMarkup.signals(signals.definitions)

	## Render definitions without replacing signals already present in the DOM.
	if_missing_attribute : DatastarSignals(a) -> Attribute
	if_missing_attribute = |signals| DatastarMarkup.signals_if_missing(signals.definitions)
}

expect {
	definitions = {
		page: DatastarSignals.u64("page", 0),
		fetching: DatastarSignals.excluded_bool("fetching", Bool.False),
	}.DatastarSignals
	handles = definitions.handles()
	attribute = definitions.if_missing_attribute()

	Attribute.raw_name(attribute) == "data-signals__ifmissing" and
		Attribute.raw_value(attribute) == "{\"page\":0,\"_fetching\":false}" and
			Str.from_utf8_lossy(DatastarMarkup.patch_signals([handles.page.update(2)]).to_bytes())
				== "event: datastar-patch-signals\ndata: signals {\"page\":2}\n\n"
}
