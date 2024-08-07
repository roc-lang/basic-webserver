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
    k : InternalSQL.SQLiteValue,
    l : InternalFile.ReadErr,
    m : InternalFile.WriteErr,
}

mainForHost : GlueTypes
mainForHost = main
