Host :: [].{
    StepSink := [StepSink(U64)]

    sink_from_host : U64 -> StepSink
    sink_from_host = |raw| StepSink(raw)

    sink_to_host : StepSink -> U64
    sink_to_host = |StepSink(raw)| raw

    publish! : U64, U8, List(U8), U64 => {}
}
