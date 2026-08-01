## Types and hosted effects used only by the retained-callable feasibility spike.
Abi :: [].{
    Resource := [Resource(Box(U64))]

    Machine := [Machine(Box(U64 => Machine))]

    BenchMachine := [BenchMachine(Box(U64 -> BenchMachine))]

    make_resource! : U64 => Resource

    observe! : U64 => {}

    touch_resource! : Resource => U64
}
