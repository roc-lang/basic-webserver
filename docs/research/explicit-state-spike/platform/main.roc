platform "explicit-state-spike"
	requires {
		[State : state] for program : {
			init_stream! : U64 => state,
			init_bench : U64 -> state,
			init_packaged : U64 -> state,
			step_stream! : U64, U64, state => state,
			bench_stream : U64, U64, state -> state,
		}
	}
	exposes [ExplicitState]
	packages {}
	provides {
		"roc_explicit_init_state": init_state_for_host!,
		"roc_explicit_init_bench_state": init_bench_state_for_host,
		"roc_explicit_init_packaged_state": init_packaged_state_for_host,
		"roc_explicit_step_state": step_state_for_host!,
		"roc_explicit_bench_state": bench_state_for_host,
		"roc_explicit_roundtrip_state": roundtrip_state_for_host,
		"roc_explicit_drop_state": drop_state_for_host!,
	}
	hosted {
		"hosted_explicit_make_resource": ExplicitState.make_resource!,
		"hosted_explicit_observe": ExplicitState.observe!,
		"hosted_explicit_touch_resource": ExplicitState.touch_resource!,
	}
	targets: {
		inputs_dir: "targets/",
		x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"] },
	}

import ExplicitState

init_state_for_host! : U64 => Box(State)
init_state_for_host! = |seed| Box.box((program.init_stream!)(seed))

init_bench_state_for_host : U64 -> Box(State)
init_bench_state_for_host = |seed| Box.box((program.init_bench)(seed))

init_packaged_state_for_host : U64 -> Box(State)
init_packaged_state_for_host = |seed| Box.box((program.init_packaged)(seed))

step_state_for_host! : Box(State), U64, U64 => Box(State)
step_state_for_host! = |boxed_state, wake, event_count|
	Box.box((program.step_stream!)(wake, event_count, Box.unbox(boxed_state)))

bench_state_for_host : Box(State), U64, U64 -> Box(State)
bench_state_for_host = |boxed_state, wake, event_count|
	Box.box((program.bench_stream)(wake, event_count, Box.unbox(boxed_state)))

roundtrip_state_for_host : Box(State) -> Box(State)
roundtrip_state_for_host = |boxed_state| boxed_state

drop_state_for_host! : Box(State) => {}
drop_state_for_host! = |_state| {}
