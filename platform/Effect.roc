hosted Effect
    exposes [
        Effect,
        after,
        args,
        map,
        always,
        forever,
        loop,
        dirList,
        envDict,
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
        InternalDir,
        InternalTcp,
        InternalCommand,
        InternalError,
    ]
    generates Effect with [after, map, always, forever, loop]

stdoutLine : Str -> Effect (Result {} InternalError.InternalError) 
stdoutWrite : Str -> Effect {}
stderrLine : Str -> Effect {}
stderrWrite : Str -> Effect {}
stdoutFlush : Effect (Result {} InternalError.InternalError) 
stderrFlush : Effect (Result {} InternalError.InternalError)

fileWriteBytes : List U8, List U8 -> Effect (Result {} InternalFile.WriteErr)
fileWriteUtf8 : List U8, Str -> Effect (Result {} InternalFile.WriteErr)
fileDelete : List U8 -> Effect (Result {} InternalFile.WriteErr)
fileReadBytes : List U8 -> Effect (Result (List U8) InternalFile.ReadErr)
dirList : List U8 -> Effect (Result (List (List U8)) InternalDir.ReadErr)
envDict : Effect (Dict Str Str)
envVar : Str -> Effect (Result Str {})
exePath : Effect (Result (List U8) {})
setCwd : List U8 -> Effect (Result {} {})

# If we encounter a Unicode error in any of the args, it will be replaced with
# the Unicode replacement char where necessary.
args : Effect (List Str)

cwd : Effect (List U8)

sendRequest : Box InternalHttp.InternalRequest -> Effect InternalHttp.InternalResponse

tcpConnect : Str, U16 -> Effect InternalTcp.ConnectResult
tcpClose : InternalTcp.Stream -> Effect {}
tcpReadUpTo : Nat, InternalTcp.Stream -> Effect InternalTcp.ReadResult
tcpReadExactly : Nat, InternalTcp.Stream -> Effect InternalTcp.ReadExactlyResult
tcpReadUntil : U8, InternalTcp.Stream -> Effect InternalTcp.ReadResult
tcpWrite : List U8, InternalTcp.Stream -> Effect InternalTcp.WriteResult

posixTime : Effect U128
sleepMillis : U64 -> Effect {}

commandStatus : Box InternalCommand.InternalCommand -> Effect (Result {} InternalCommand.InternalCommandErr)
commandOutput : Box InternalCommand.InternalCommand -> Effect InternalCommand.InternalOutput
