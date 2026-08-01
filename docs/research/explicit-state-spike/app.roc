app [State, program] { pf: platform "./platform/main.roc" }

import pf.ExplicitState

FeedState : {
	checksum : U64,
	items : List(Str),
	label : Str,
	resource : ExplicitState.Resource,
	steps : U64,
}

DashboardState : {
	checksum : U64,
	label : Str,
	resource : ExplicitState.Resource,
	series : List(Str),
	steps : U64,
}

BenchState : { checksum : U64, steps : U64 }

State : [Bench(BenchState), Dashboard(DashboardState), Feed(FeedState)]

program = { init_stream!, init_bench, step_stream!, bench_stream }

init_stream! : U64 => State
init_stream! = |seed|
	if seed % 2 == 0 {
		Feed({
			checksum: seed + 17,
			items: [
				"first retained heap string in explicit stream state",
				"second retained heap string in explicit stream state",
			],
			label: "feed route state parked between generated provided calls",
			resource: ExplicitState.make_resource!(seed + 1000),
			steps: 0,
		})
	} else {
		Dashboard({
			checksum: seed + 29,
			label: "dashboard route state with a different private payload shape",
			resource: ExplicitState.make_resource!(seed + 2000),
			series: [
				"requests-per-second",
				"stream-wake-latency",
				"buffered-output-bytes",
			],
			steps: 0,
		})
	}

init_bench : U64 -> State
init_bench = |seed| Bench({ checksum: seed + 41, steps: 0 })

advance_values : U64, U64, U64, U64 -> { checksum : U64, steps : U64 }
advance_values = |wake, remaining, steps, checksum|
	if remaining == 0 {
		{ checksum, steps }
	} else {
		next_steps = steps + 1
		next_checksum = U64.plus_wrap(U64.plus_wrap(U64.times_wrap(checksum, 6364136223846793005), wake), next_steps)
		advance_values(wake + 1, remaining - 1, next_steps, next_checksum)
	}

step_stream! : U64, U64, State => State
step_stream! = |wake, event_count, state|
	match state {
		Bench(bench) => {
			advanced = advance_values(wake, event_count, bench.steps, bench.checksum)
			ExplicitState.observe!(advanced.checksum)
			Bench(advanced)
		}
		Feed(feed) => {
			advanced = advance_values(wake, event_count, feed.steps, feed.checksum)
			resource_value = ExplicitState.touch_resource!(feed.resource)
			ExplicitState.observe!(advanced.checksum + resource_value + List.len(feed.items))

			Feed({
				checksum: advanced.checksum,
				items: feed.items,
				label: feed.label,
				resource: feed.resource,
				steps: advanced.steps,
			})
		}
		Dashboard(dashboard) => {
			advanced = advance_values(wake, event_count, dashboard.steps, dashboard.checksum)
			resource_value = ExplicitState.touch_resource!(dashboard.resource)
			ExplicitState.observe!(advanced.checksum + resource_value + List.len(dashboard.series))

			Dashboard({
				checksum: advanced.checksum,
				label: dashboard.label,
				resource: dashboard.resource,
				series: dashboard.series,
				steps: advanced.steps,
			})
		}
	}

bench_stream : U64, U64, State -> State
bench_stream = |wake, event_count, state|
	match state {
		Bench(bench) => Bench(advance_values(wake, event_count, bench.steps, bench.checksum))
		Feed(feed) => {
			advanced = advance_values(wake, event_count, feed.steps, feed.checksum)
			Feed({
				checksum: advanced.checksum,
				items: feed.items,
				label: feed.label,
				resource: feed.resource,
				steps: advanced.steps,
			})
		}
		Dashboard(dashboard) => {
			advanced = advance_values(wake, event_count, dashboard.steps, dashboard.checksum)
			Dashboard({
				checksum: advanced.checksum,
				label: dashboard.label,
				resource: dashboard.resource,
				series: dashboard.series,
				steps: advanced.steps,
			})
		}
	}
