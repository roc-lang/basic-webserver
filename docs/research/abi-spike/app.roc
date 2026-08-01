app [State, program] { pf: platform "./platform/main.roc" }

import pf.Abi

State : {
    base : U64,
    inner : Box(U64 -> U64),
    items : List(Str),
    label : Str,
    resource : Abi.Resource,
    steps : U64,
}

program = { make_machine!, make_bench_machine, init_state!, step_state!, bench_step_state }

make_state! : U64 => State
make_state! = |seed| {
    resource = Abi.make_resource!(seed + 1000)
    inner = Box.box(|value| value + seed + 17)

    {
        base: seed,
        inner,
        items: [
            "first retained heap string in the machine capture",
            "second retained heap string in the machine capture",
        ],
        label: "retained boxed stream machine capture whose bytes outlive the creating entrypoint",
        resource,
        steps: 0,
    }
}

machine_from_state : State -> Abi.Machine
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
make_machine! = |seed| machine_from_state(make_state!(seed))

bench_machine_from_value : U64 -> Abi.BenchMachine
bench_machine_from_value = |value|
    Abi.BenchMachine.BenchMachine(Box.box(|wake|
        bench_machine_from_value(value + wake + 1)
    ))

make_bench_machine : U64 -> Abi.BenchMachine
make_bench_machine = bench_machine_from_value

init_state! : U64 => State
init_state! = make_state!

step_state! : U64, State => State
step_state! = |wake, state| {
    inner_fn = Box.unbox(state.inner)
    inner_value = inner_fn(wake)
    next_inner = Box.box(inner_fn)
    resource_value = Abi.touch_resource!(state.resource)
    Abi.observe!(inner_value + resource_value + state.steps + List.len(state.items))

    {
        base: state.base,
        inner: next_inner,
        items: state.items,
        label: state.label,
        resource: state.resource,
        steps: state.steps + 1,
    }
}

bench_step_state : U64, State -> State
bench_step_state = |wake, state| {
    base: state.base + wake + 1,
    inner: state.inner,
    items: state.items,
    label: state.label,
    resource: state.resource,
    steps: state.steps + 1,
}
