platform "webserver"
    requires {} { main : GlueTypes }
    exposes []
    packages {}
    imports [
        InternalCommand,
        InternalError,
    ]
    provides [mainForHost]

GlueTypes : [
    A InternalCommand.InternalCommand,
    B InternalCommand.InternalOutput,
    C InternalCommand.InternalCommandErr,
    D InternalError.InternalError,
]

mainForHost : GlueTypes
mainForHost = main
