hosted Effect
    exposes [
        Effect,
        after,
        map,
        always,
        forever,
        loop,
        dirList,
        envList,
        envVar,
        cwd,
        setCwd,
        exePath,
        stdoutLine,
        stdoutWrite,
        stdoutFlush,
        stderrLine,
        stderrWrite,
        stderrFlush,
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
    ]
    imports [
        InternalHttp,
        InternalFile,
        InternalTcp,
        InternalCommand,
        InternalError,
    ]
    generates Effect with [after, map, always, forever, loop]

# Stdout
stdoutLine : Str -> Effect {}
stdoutWrite : Str -> Effect {}
stdoutFlush : Effect {}

# Stderr
stderrLine : Str -> Effect {}
stderrWrite : Str -> Effect {}
stderrFlush : Effect {}

# File 
fileWriteBytes : List U8, List U8 -> Effect (Result {} InternalFile.WriteErr)
fileWriteUtf8 : List U8, Str -> Effect (Result {} InternalFile.WriteErr)
fileDelete : List U8 -> Effect (Result {} InternalFile.WriteErr)
fileReadBytes : List U8 -> Effect (Result (List U8) InternalFile.ReadErr)

# Dir
dirList : List U8 -> Effect (Result (List (List U8)) InternalError.InternalDirReadErr)

# Env
envList : Effect (List (Str, Str))
envVar : Str -> Effect (Result Str {})
exePath : Effect (Result (List U8) {})
setCwd : List U8 -> Effect (Result {} {})
cwd : Effect (List U8)

# Http
sendRequest : Box InternalHttp.InternalRequest -> Effect InternalHttp.InternalResponse

# Tcp
tcpConnect : Str, U16 -> Effect InternalTcp.ConnectResult
tcpClose : InternalTcp.Stream -> Effect {}
tcpReadUpTo : Nat, InternalTcp.Stream -> Effect InternalTcp.ReadResult
tcpReadExactly : Nat, InternalTcp.Stream -> Effect InternalTcp.ReadExactlyResult
tcpReadUntil : U8, InternalTcp.Stream -> Effect InternalTcp.ReadResult
tcpWrite : List U8, InternalTcp.Stream -> Effect InternalTcp.WriteResult

# Utc
posixTime : Effect U128
sleepMillis : U64 -> Effect {}

commandStatus : Box InternalCommand.InternalCommand -> Effect (Result {} InternalCommand.InternalCommandErr)
commandOutput : Box InternalCommand.InternalCommand -> Effect InternalCommand.InternalOutput
