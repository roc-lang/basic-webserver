platform "webserver"
    requires {} { main : CommandTypes }
    exposes []
    packages {}
    imports [
        InternalCommand,
    ]
    provides [mainForHost]

CommandTypes : [
    A InternalCommand.InternalCommand,
    B InternalCommand.InternalOutput,
    C InternalCommand.InternalCommandErr,
]

mainForHost : CommandTypes
mainForHost = main
