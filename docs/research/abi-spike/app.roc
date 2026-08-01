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

program = { make_machine!, make_bench_machine, make_callable, init_state!, step_state!, bench_step_state }

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
    Abi.Machine.Machine(Box.box(|wake| {
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
    }))

make_machine! : U64 => Abi.Machine
make_machine! = |seed| machine_from_state(make_machine_state!(seed))

bench_machine_from_value : U64 -> Abi.BenchMachine
bench_machine_from_value = |value|
    Abi.BenchMachine.BenchMachine(Box.box(|wake|
        bench_machine_from_value(value + wake + 1)
    ))

make_bench_machine : U64 -> Abi.BenchMachine
make_bench_machine = bench_machine_from_value

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
