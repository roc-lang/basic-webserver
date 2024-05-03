module [
    InternalCommand,
    InternalOutput,
    InternalCommandErr,
]

InternalCommandErr : [
    ExitCode I32,
    KilledBySignal,
    IOError Str,
]

InternalCommand : {
    program : Str,
    args : List Str, # [arg0, arg1, arg2, arg3, ...]
    envs : List Str, # [key0, value0, key1, value1, key2, value2, ...]
    clearEnvs : Bool,
}

InternalOutput : {
    status : Result {} InternalCommandErr,
    stdout : List U8,
    stderr : List U8,
}
