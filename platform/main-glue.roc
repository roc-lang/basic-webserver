platform "glue-types"
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

import InternalCommand
import InternalTcp
import InternalSql
import InternalError
import InternalFile

GlueTypes : {
    a : InternalCommand.InternalCommand,
    b : InternalCommand.InternalOutput,
    c : InternalCommand.InternalCommandErr,
    d : InternalTcp.ConnectResult,
    e : InternalTcp.ReadResult,
    f : InternalTcp.ReadExactlyResult,
    g : InternalTcp.WriteResult,
    h : InternalTcp.ConnectErr,
    i : InternalTcp.StreamErr,
    j : InternalError.InternalDirReadErr,
    k : InternalSql.SqliteBindings,
    l : InternalSql.SqliteError,
    m : InternalSql.SqliteState,
    n : InternalSql.SqliteValue,
    o : InternalFile.ReadErr,
    p : InternalFile.WriteErr,
}

mainForHost : GlueTypes
mainForHost = main
