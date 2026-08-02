app [State, program] { pf: platform "./platform/main.roc" }

import pf.Abi

State : {
	base : U64,
	items : List(Str),
	label : Str,
	resource : Abi.Resource,
	steps : U64,
}

MachineState : {
	base : U64,
	inner : Box(U64 -> U64),
	items : List(Str),
	label : Str,
	resource : Abi.Resource,
	steps : U64,
}

program = { make_machine!, make_bench_machine, make_source_machine!, make_aliased_source_machine!, make_unique_source_machine!, make_sink_machine!, make_callable, init_state!, step_state!, bench_step_state }

make_state! : U64 => State
make_state! = |seed| {
	resource = Abi.make_resource!(seed + 1000)

	{
		base: seed,
		items: [
			"first retained heap string in the machine capture",
			"second retained heap string in the machine capture",
		],
		label: "retained boxed stream machine capture whose bytes outlive the creating entrypoint",
		resource,
		steps: 0,
	}
}

make_machine_state! : U64 => MachineState
make_machine_state! = |seed| {
	state = make_state!(seed)
	{
		base: state.base,
		inner: Box.box(|value| value + seed + 17),
		items: state.items,
		label: state.label,
		resource: state.resource,
		steps: state.steps,
	}
}

machine_from_state : MachineState -> Abi.Machine
machine_from_state = |state|
	Abi.Machine.Machine(
		Box.box(
			|wake| {
				inner_fn = Box.unbox(state.inner)
				inner_value = inner_fn(wake)
				next_inner = Box.box(inner_fn)
				resource_value = Abi.touch_resource!(state.resource)
				observed = inner_value + resource_value + state.steps + List.len(state.items)
				Abi.observe!(observed)

				machine_from_state({
					base: state.base,
					inner: next_inner,
					items: state.items,
					label: state.label,
					resource: state.resource,
					steps: state.steps + 1,
				})
			},
		),
	)

make_machine! : U64 => Abi.Machine
make_machine! = |seed| machine_from_state(make_machine_state!(seed))

bench_machine_from_value : U64 -> Abi.BenchMachine
bench_machine_from_value = |value|
	Abi.BenchMachine.BenchMachine(Box.box(|wake|
		bench_machine_from_value(value + wake + 1)))

make_bench_machine : U64 -> Abi.BenchMachine
make_bench_machine = bench_machine_from_value

source_machine_from_state : { item : List(U8), remaining : U64, resource : Abi.Resource, sequence : U64 } -> Abi.SourceMachine
source_machine_from_state = |state|
	Abi.SourceMachine.SourceMachine(
		Box.box(
			|wake| {
				resource_value = Abi.touch_resource!(state.resource)
				if wake == 99 {
					Abi.observe!(resource_value)
				} else {}
				if state.remaining == 0 {
					Abi.SourceStep.End
				} else {
					next = source_machine_from_state({
						item: state.item,
						remaining: state.remaining - 1,
						resource: state.resource,
						sequence: state.sequence + wake + 1,
					})
					Abi.SourceStep.Emit({
						item: state.item,
						machine: next,
						wait_millis: state.sequence % 17,
					})
				}
			},
		),
	)

make_source_machine! : U64 => Abi.SourceMachine
make_source_machine! = |events| {
	resource = Abi.make_resource!(events + 2000)
	source_machine_from_state({
		item: [
			101,
			118,
			101,
			110,
			116,
			58,
			32,
			100,
			97,
			116,
			97,
			115,
			116,
			97,
			114,
			45,
			112,
			97,
			116,
			99,
			104,
			45,
			101,
			108,
			101,
			109,
			101,
			110,
			116,
			115,
			10,
			100,
			97,
			116,
			97,
			58,
			32,
			101,
			108,
			101,
			109,
			101,
			110,
			116,
			115,
			32,
			60,
			100,
			105,
			118,
			62,
			111,
			107,
			60,
			47,
			100,
			105,
			118,
			62,
			10,
			10,
		],
		remaining: events,
		resource,
		sequence: 0,
	})
}

make_aliased_source_machine! : U64 => Abi.SourceMachine
make_aliased_source_machine! = |events| {
	resource = Abi.make_resource!(events + 2500)
	source_machine_from_state({
		item: List.concat(List.repeat(97, events + 64), [10, 10]),
		remaining: events,
		resource,
		sequence: 0,
	})
}

unique_source_machine_from_state : { remaining : U64, resource : Abi.Resource, sequence : U64 } -> Abi.SourceMachine
unique_source_machine_from_state = |state|
	Abi.SourceMachine.SourceMachine(
		Box.box(
			|wake| {
				resource_value = Abi.touch_resource!(state.resource)
				if wake == 99 {
					Abi.observe!(resource_value)
				} else {}
				if state.remaining == 0 {
					Abi.SourceStep.End
				} else {
					next = unique_source_machine_from_state({
						remaining: state.remaining - 1,
						resource: state.resource,
						sequence: state.sequence + wake + 1,
					})
					Abi.SourceStep.Emit({
						item: List.concat(List.repeat(98, state.remaining + 64), [10, 10]),
						machine: next,
						wait_millis: state.sequence % 17,
					})
				}
			},
		),
	)

make_unique_source_machine! : U64 => Abi.SourceMachine
make_unique_source_machine! = |events| {
	resource = Abi.make_resource!(events + 2750)
	unique_source_machine_from_state({ remaining: events, resource, sequence: 0 })
}

sink_machine_from_state : { item : List(U8), marker : U64, remaining : U64, resource : Abi.Resource, sequence : U64 } -> Abi.SinkMachine
sink_machine_from_state = |state|
	Abi.SinkMachine.SinkMachine(
		Box.box(
			|args| {
				resource_value = Abi.touch_resource!(state.resource)
				if state.remaining == 0 {
					Abi.publish_step!(args.sink, 1, [], 0)
					sink_machine_from_state(state)
				} else {
					next_state = {
						item: state.item,
						marker: state.marker,
						remaining: state.remaining - 1,
						resource: state.resource,
						sequence: state.sequence + args.wake + 1,
					}
					Abi.publish_step!(args.sink, 0, state.item, (state.sequence + state.marker) % 17)
					if args.wake == 99 {
						Abi.observe!(resource_value)
					} else {}
					sink_machine_from_state(next_state)
				}
			},
		),
	)

make_sink_machine! : U64 => Abi.SinkMachine
make_sink_machine! = |events| {
	resource = Abi.make_resource!(events + 3000)
	sink_machine_from_state({
		item: [
			101,
			118,
			101,
			110,
			116,
			58,
			32,
			100,
			97,
			116,
			97,
			115,
			116,
			97,
			114,
			45,
			112,
			97,
			116,
			99,
			104,
			45,
			101,
			108,
			101,
			109,
			101,
			110,
			116,
			115,
			10,
			100,
			97,
			116,
			97,
			58,
			32,
			101,
			108,
			101,
			109,
			101,
			110,
			116,
			115,
			32,
			60,
			100,
			105,
			118,
			62,
			111,
			107,
			60,
			47,
			100,
			105,
			118,
			62,
			10,
			10,
		],
		marker: 17,
		remaining: events,
		resource,
		sequence: 0,
	})
}

make_callable : U64 -> Box(U64 -> U64)
make_callable = |offset| Box.box(|value| value + offset)

init_state! : U64 => State
init_state! = make_state!

step_state! : U64, State => State
step_state! = |wake, state| {
	resource_value = Abi.touch_resource!(state.resource)
	Abi.observe!(state.base + wake + resource_value + state.steps + List.len(state.items))

	{
		base: state.base,
		items: state.items,
		label: state.label,
		resource: state.resource,
		steps: state.steps + 1,
	}
}

bench_step_state : U64, State -> State
bench_step_state = |wake, state| {
	base: state.base + wake + 1,
	items: state.items,
	label: state.label,
	resource: state.resource,
	steps: state.steps + 1,
}
