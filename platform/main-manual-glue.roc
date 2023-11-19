platform "webserver"
    requires {} { main : GlueTypes }
    exposes []
    packages {}
    imports [
        InternalCommand,
        InternalError,
        InternalTcp,
        InternalFile,
    ]
    provides [mainForHost]

GlueTypes : [
    A InternalCommand.InternalCommand,
    B InternalCommand.InternalOutput,
    C InternalCommand.InternalCommandErr,
    D InternalError.InternalError,
    E InternalTcp.Stream,
    F InternalTcp.ConnectErr,
    G InternalTcp.StreamErr,
    H InternalTcp.ConnectResult,
    I InternalTcp.WriteResult,
    J InternalTcp.ReadResult,
    K InternalTcp.ReadExactlyResult,
    L InternalFile.ReadErr, 
    M InternalFile.WriteErr
]

mainForHost : GlueTypes
mainForHost = main
