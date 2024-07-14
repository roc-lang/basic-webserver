platform "glue-types"
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

import InternalCommand
import InternalTcp
import InternalSQL
import InternalError

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
    k : InternalSQL.SQLiteValue,
}

mainForHost : GlueTypes
mainForHost = main
