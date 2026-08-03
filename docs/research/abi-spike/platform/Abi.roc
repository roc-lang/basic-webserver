## Types and hosted effects used only by the retained-callable feasibility spike.
Abi :: [].{
	Resource := [Resource(Box(U64))]

	Machine := [Machine(Box(U64 => Machine))]

	BenchMachine := [BenchMachine(Box(U64 -> BenchMachine))]

	SourceMachine := [SourceMachine(Box(U64 => SourceStep))]

	SourceStep := [Emit({ item : List(U8), machine : SourceMachine, wait_millis : U64 }), End]

	## Production `Server.Outcome` will contain more ordinary response-plan
	## variants. This reduced sum proves that one owned retained source can move
	## through that outcome boundary without turning the application contract
	## into a fixed callback registry.
	SourceOutcome := [Response(U16), Stream(SourceMachine)]

	SinkMachine := [SinkMachine(Box({ sink : U64, wake : U64 } => SinkMachine))]

	make_resource! : U64 => Resource

	observe! : U64 => {}

	touch_resource! : Resource => U64

	publish_step! : U64, U8, List(U8), U64 => {}
}
