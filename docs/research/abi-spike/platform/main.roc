platform "abi-spike"
	requires {
		[State : state] for program : {
			make_machine! : U64 => Abi.Machine,
			make_bench_machine : U64 -> Abi.BenchMachine,
			make_source_machine! : U64 => Abi.SourceMachine,
			make_source_outcome! : U64 => Abi.SourceOutcome,
			make_context_source_outcome! : U64, state => Abi.SourceOutcome,
			make_aliased_source_machine! : U64 => Abi.SourceMachine,
			make_unique_source_machine! : U64 => Abi.SourceMachine,
			make_sink_machine! : U64 => Abi.SinkMachine,
			make_callable : U64 -> Box(U64 -> U64),
			init_state! : U64 => state,
			step_state! : U64, state => state,
			bench_step_state : U64, state -> state,
		}
	}
	exposes [Abi]
	packages {}
	provides {
		"roc_abi_make_machine": make_machine_for_host!,
		"roc_abi_advance_machine": advance_machine_for_host!,
		"roc_abi_drop_machine": drop_machine_for_host!,
		"roc_abi_make_bench_machine": make_bench_machine_for_host,
		"roc_abi_advance_bench_machine": advance_bench_machine_for_host,
		"roc_abi_drop_bench_machine": drop_bench_machine_for_host,
		"roc_abi_make_source_machine": make_source_machine_for_host!,
		"roc_abi_make_source_outcome": make_source_outcome_for_host!,
		"roc_abi_make_context_source_outcome": make_context_source_outcome_for_host!,
		"roc_abi_drop_source_outcome": drop_source_outcome_for_host!,
		"roc_abi_make_aliased_source_machine": make_aliased_source_machine_for_host!,
		"roc_abi_make_unique_source_machine": make_unique_source_machine_for_host!,
		"roc_abi_advance_source_machine": advance_source_machine_for_host!,
		"roc_abi_drop_source_machine": drop_source_machine_for_host!,
		"roc_abi_drop_source_step": drop_source_step_for_host!,
		"roc_abi_drop_source_item": drop_source_item_for_host!,
		"roc_abi_make_sink_machine": make_sink_machine_for_host!,
		"roc_abi_advance_sink_machine": advance_sink_machine_for_host!,
		"roc_abi_drop_sink_machine": drop_sink_machine_for_host!,
		"roc_abi_init_state": init_state_for_host!,
		"roc_abi_step_state": step_state_for_host!,
		"roc_abi_bench_step_state": bench_step_state_for_host,
		"roc_abi_drop_state": drop_state_for_host!,
		"roc_abi_make_box": make_box_for_host,
		"roc_abi_drop_box": drop_box_for_host,
		"roc_abi_make_callable": make_callable_for_host,
		"roc_abi_make_platform_callable": make_platform_callable_for_host,
		"roc_abi_drop_callable": drop_callable_for_host,
	}
	hosted {
		"hosted_abi_make_resource": Abi.make_resource!,
		"hosted_abi_observe": Abi.observe!,
		"hosted_abi_touch_resource": Abi.touch_resource!,
		"hosted_abi_publish_step": Abi.publish_step!,
	}
	targets: {
		inputs_dir: "targets/",
		x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"] },
	}

import Abi

make_machine_for_host! : U64 => Abi.Machine
make_machine_for_host! = program.make_machine!

advance_machine_for_host! : Abi.Machine, U64 => Abi.Machine
advance_machine_for_host! = |machine, wake|
	match machine {
		Abi.Machine.Machine(boxed_step) => (Box.unbox(boxed_step))(wake)
	}

drop_machine_for_host! : Abi.Machine => {}
drop_machine_for_host! = |_machine| {}

make_bench_machine_for_host : U64 -> Abi.BenchMachine
make_bench_machine_for_host = program.make_bench_machine

advance_bench_machine_for_host : Abi.BenchMachine, U64 -> Abi.BenchMachine
advance_bench_machine_for_host = |machine, wake|
	match machine {
		Abi.BenchMachine.BenchMachine(boxed_step) => (Box.unbox(boxed_step))(wake)
	}

drop_bench_machine_for_host : Abi.BenchMachine -> {}
drop_bench_machine_for_host = |_machine| {}

make_source_machine_for_host! : U64 => Abi.SourceMachine
make_source_machine_for_host! = program.make_source_machine!

make_source_outcome_for_host! : U64 => Abi.SourceOutcome
make_source_outcome_for_host! = program.make_source_outcome!

make_context_source_outcome_for_host! : U64, Box(State) => Abi.SourceOutcome
make_context_source_outcome_for_host! = |events, boxed_context|
	(program.make_context_source_outcome!)(events, Box.unbox(boxed_context))

drop_source_outcome_for_host! : Abi.SourceOutcome => {}
drop_source_outcome_for_host! = |_outcome| {}

make_aliased_source_machine_for_host! : U64 => Abi.SourceMachine
make_aliased_source_machine_for_host! = program.make_aliased_source_machine!

make_unique_source_machine_for_host! : U64 => Abi.SourceMachine
make_unique_source_machine_for_host! = program.make_unique_source_machine!

advance_source_machine_for_host! : Abi.SourceMachine, U64 => Abi.SourceStep
advance_source_machine_for_host! = |machine, wake|
	match machine {
		Abi.SourceMachine.SourceMachine(boxed_step) => (Box.unbox(boxed_step))(wake)
	}

drop_source_machine_for_host! : Abi.SourceMachine => {}
drop_source_machine_for_host! = |_machine| {}

drop_source_step_for_host! : Abi.SourceStep => {}
drop_source_step_for_host! = |_step| {}

drop_source_item_for_host! : List(U8) => {}
drop_source_item_for_host! = |_item| {}

make_sink_machine_for_host! : U64 => Abi.SinkMachine
make_sink_machine_for_host! = program.make_sink_machine!

advance_sink_machine_for_host! : Abi.SinkMachine, U64, U64 => Abi.SinkMachine
advance_sink_machine_for_host! = |machine, wake, sink|
	match machine {
		Abi.SinkMachine.SinkMachine(boxed_step) => (Box.unbox(boxed_step))({ sink, wake })
	}

drop_sink_machine_for_host! : Abi.SinkMachine => {}
drop_sink_machine_for_host! = |_machine| {}

init_state_for_host! : U64 => Box(State)
init_state_for_host! = |seed| Box.box((program.init_state!)(seed))

step_state_for_host! : Box(State), U64 => Box(State)
step_state_for_host! = |boxed_state, wake|
	Box.box((program.step_state!)(wake, Box.unbox(boxed_state)))

bench_step_state_for_host : Box(State), U64 -> Box(State)
bench_step_state_for_host = |boxed_state, wake|
	Box.box((program.bench_step_state)(wake, Box.unbox(boxed_state)))

drop_state_for_host! : Box(State) => {}
drop_state_for_host! = |_state| {}

make_box_for_host : U64 -> Box(U64)
make_box_for_host = |value| Box.box(value)

drop_box_for_host : Box(U64) -> {}
drop_box_for_host = |_boxed| {}

make_callable_for_host : U64 -> Box(U64 -> U64)
make_callable_for_host = program.make_callable

drop_callable_for_host : Box(U64 -> U64) -> {}
drop_callable_for_host = |_callable| {}

make_platform_callable_for_host : U64 -> Box(U64 -> U64)
make_platform_callable_for_host = |offset| Box.box(|value| value + offset)
