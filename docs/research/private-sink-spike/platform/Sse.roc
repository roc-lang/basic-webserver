import Host

Sse :: [].{
    Stream := [Stream(Box({ sink : U64, wake : U64 } => Stream))]

    unfold! : state, (state, U64 => { item : List(U8), kind : U8, state : state, wait_millis : U64 }) => Stream
    unfold! = |initial_state, transition!| {
        from_state : state -> Stream
        from_state = |state|
            Stream(Box.box(|args| {
                step = transition!(state, args.wake)
                Host.publish!(args.sink, step.kind, step.item, step.wait_millis)
                from_state(step.state)
            }))

        from_state(initial_state)
    }

    advance_for_host! : Stream, U64, Host.StepSink => Stream
    advance_for_host! = |Stream(boxed_step), wake, sink|
        (Box.unbox(boxed_step))({ sink: Host.sink_to_host(sink), wake })

    drop_for_host! : Stream => {}
    drop_for_host! = |_stream| {}
}
