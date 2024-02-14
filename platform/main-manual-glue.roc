platform "webserver"
    requires {} { main : GlueTypes }
    exposes []
    packages {}
    imports [
        InternalCommand,
        InternalError,
        InternalTcp,
        InternalFile,
        InternalPath,
        InternalSQL,
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
    M InternalFile.WriteErr,
    N InternalError.InternalDirReadErr,
    O InternalError.InternalDirDeleteErr,
    P InternalPath.UnwrappedPath,
    Q InternalSQL.SQLiteValue,
]

mainForHost : GlueTypes
mainForHost = main
