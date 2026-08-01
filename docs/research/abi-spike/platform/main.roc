platform "abi-spike"
    requires {
        [State : state] for program : {
            make_machine! : U64 => Abi.Machine,
            make_bench_machine : U64 -> Abi.BenchMachine,
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
        "roc_abi_init_state": init_state_for_host!,
        "roc_abi_step_state": step_state_for_host!,
        "roc_abi_bench_step_state": bench_step_state_for_host,
        "roc_abi_drop_state": drop_state_for_host!,
    }
    hosted {
        "hosted_abi_make_resource": Abi.make_resource!,
        "hosted_abi_observe": Abi.observe!,
        "hosted_abi_touch_resource": Abi.touch_resource!,
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
