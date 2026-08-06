## Hosted effects used only by the explicit-state SSE feasibility spike.
ExplicitState :: [].{
	Resource := [Resource(Box(U64))]

	make_resource! : U64 => Resource

	observe! : U64 => {}

	touch_resource! : Resource => U64
}
