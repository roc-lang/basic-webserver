hosted PlatformTasks
    exposes [
        dirList,
        envList,
        envVar,
        cwd,
        setCwd,
        exePath,
        stdoutLine,
        stdoutWrite,
        stderrLine,
        stderrWrite,
        sendRequest,
        fileReadBytes,
        fileDelete,
        fileWriteUtf8,
        fileWriteBytes,
        posixTime,
        tcpConnect,
        tcpClose,
        tcpReadUpTo,
        tcpReadExactly,
        tcpReadUntil,
        tcpWrite,
        sleepMillis,
        commandStatus,
        commandOutput,
        tempDir,

        sqlitePrepare,
        sqliteBind,
        sqliteColumns,
        sqliteColumnValue,
        sqliteStep,
        sqliteReset,

        # Json Web Token
        jwtDecodingKeyFromSimpleSecret,
        jwtDecodingKeyFromRsaPem,
        jwtDecode,
    ]
    imports []

import InternalHttp
import InternalFile
import InternalTcp
import InternalCommand
import InternalError
import InternalSql
import InternalJwt

# Stdout
stdoutLine : Str -> Task {} Str
stdoutWrite : Str -> Task {} Str

# Stderr
stderrLine : Str -> Task {} Str
stderrWrite : Str -> Task {} Str

# File
fileWriteBytes : List U8, List U8 -> Task {} InternalFile.WriteErr
fileWriteUtf8 : List U8, Str -> Task {} InternalFile.WriteErr
fileDelete : List U8 -> Task {} InternalFile.WriteErr
fileReadBytes : List U8 -> Task (List U8) InternalFile.ReadErr

# Dir
dirList : List U8 -> Task (List (List U8)) InternalError.InternalDirReadErr

# Env
envList : Task (List (Str, Str)) {}
envVar : Str -> Task Str {}
exePath : Task (List U8) {}
setCwd : List U8 -> Task {} {}
cwd : Task (List U8) {}

# Http
sendRequest : Box InternalHttp.RequestToAndFromHost -> Task InternalHttp.ResponseFromHost {}

# Tcp
tcpConnect : Str, U16 -> Task InternalTcp.ConnectResult {}
tcpClose : InternalTcp.Stream -> Task {} {}
tcpReadUpTo : U64, InternalTcp.Stream -> Task InternalTcp.ReadResult {}
tcpReadExactly : U64, InternalTcp.Stream -> Task InternalTcp.ReadExactlyResult {}
tcpReadUntil : U8, InternalTcp.Stream -> Task InternalTcp.ReadResult {}
tcpWrite : List U8, InternalTcp.Stream -> Task InternalTcp.WriteResult {}

# Utc
posixTime : Task U128 {}
sleepMillis : U64 -> Task {} {}

commandStatus : Box InternalCommand.InternalCommand -> Task {} InternalCommand.InternalCommandErr
commandOutput : Box InternalCommand.InternalCommand -> Task InternalCommand.InternalOutput {}

# Sqlite
sqlitePrepare : Str, Str -> Task (Box {}) InternalSql.SqliteError
sqliteBind : Box {}, List InternalSql.SqliteBindings -> Task {} InternalSql.SqliteError
sqliteColumns : Box {} -> Task (List Str) {}
sqliteColumnValue : Box {}, U64 -> Task InternalSql.SqliteValue InternalSql.SqliteError
sqliteStep : Box {} -> Task InternalSql.SqliteState InternalSql.SqliteError
sqliteReset : Box {} -> Task {} InternalSql.SqliteError

tempDir : Task (List U8) {}

# Json Web Token

# TODO use an error union https://docs.rs/jsonwebtoken/latest/jsonwebtoken/errors/enum.ErrorKind.html
jwtDecodingKeyFromSimpleSecret : Str -> Task InternalJwt.DecodingKey InternalJwt.Err
jwtDecodingKeyFromRsaPem : Str -> Task InternalJwt.DecodingKey InternalJwt.Err
jwtDecode : Str, InternalJwt.DecodingKey, InternalJwt.Validation -> Task InternalJwt.Token InternalJwt.Err
