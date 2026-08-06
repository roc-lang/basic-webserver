FeedRoute := [FeedRoute({ checksum : U64, items : List(Str), label : Str, steps : U64 })].{
	init : U64 -> FeedRoute
	init = |seed|
		FeedRoute({
			checksum: seed + 73,
			items: [
				"package-private stream state item one",
				"package-private stream state item two",
			],
			label: "the application can name this nominal state without seeing its payload",
			steps: 0,
		})

	step : U64, U64, FeedRoute -> FeedRoute
	step = |wake, event_count, FeedRoute(state)| {
		advanced = advance(wake, event_count, state.steps, state.checksum)
		FeedRoute({
			checksum: advanced.checksum,
			items: state.items,
			label: state.label,
			steps: advanced.steps,
		})
	}

	checksum : FeedRoute -> U64
	checksum = |FeedRoute(state)| state.checksum

	advance : U64, U64, U64, U64 -> { checksum : U64, steps : U64 }
	advance = |wake, remaining, steps, current_checksum|
		if remaining == 0 {
			{ checksum: current_checksum, steps }
		} else {
			next_steps = steps + 1
			next_checksum = U64.plus_wrap(U64.plus_wrap(U64.times_wrap(current_checksum, 6364136223846793005), wake), next_steps)
			advance(wake + 1, remaining - 1, next_steps, next_checksum)
		}
}
