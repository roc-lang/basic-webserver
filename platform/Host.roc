hosted Host
    exposes [
        InternalIOErr,
        TcpStream,
        FileReader,
        stdoutLine!,
        stdoutWrite!,
        stderrLine!,
        stderrWrite!,
        dirList!,
        dirCreate!,
        dirCreateAll!,
        dirDeleteEmpty!,
        dirDeleteAll!,
        hardLink!,
        envDict!,
        envVar!,
        cwd!,
        setCwd!,
        exePath!,
        pathType!,
        sendRequest!,
        fileReadBytes!,
        fileDelete!,
        fileWriteUtf8!,
        fileWriteBytes!,
        fileReadLine!,
        fileReader!,
        posixTime!,
        tcpConnect!,
        tcpReadUpTo!,
        tcpReadExactly!,
        tcpReadUntil!,
        tcpWrite!,
        commandStatus!,
        commandOutput!,
        sqliteExecute!,
        tempDir!,
        getLocale!,
        getLocales!,
        currentArchOS!,
    ]
    imports []

import InternalHttp exposing [Request, ResponseFromHost]
import InternalCommand
import InternalSQL
import InternalPath

InternalIOErr : {
    tag : [
        EndOfFile,
        NotFound,
        PermissionDenied,
        BrokenPipe,
        AlreadyExists,
        Interrupted,
        Unsupported,
        OutOfMemory,
        Other,
    ],
    msg : Str,
}

# COMMAND
commandStatus! : Box InternalCommand.Command => Result {} (List U8)
commandOutput! : Box InternalCommand.Command => InternalCommand.Output

# FILE
fileWriteBytes! : List U8, List U8 => Result {} InternalIOErr
fileWriteUtf8! : List U8, Str => Result {} InternalIOErr
fileDelete! : List U8 => Result {} InternalIOErr
fileReadBytes! : List U8 => Result (List U8) InternalIOErr

FileReader := Box {}
fileReader! : List U8, U64 => Result FileReader InternalIOErr
fileReadLine! : FileReader => Result (List U8) InternalIOErr

dirList! : List U8 => Result (List (List U8)) InternalIOErr
dirCreate! : List U8 => Result {} InternalIOErr
dirCreateAll! : List U8 => Result {} InternalIOErr
dirDeleteEmpty! : List U8 => Result {} InternalIOErr
dirDeleteAll! : List U8 => Result {} InternalIOErr

hardLink! : List U8 => Result {} InternalIOErr
pathType! : List U8 => Result InternalPath.InternalPathType InternalIOErr

# STDIO
stdoutLine! : Str => Result {} InternalIOErr
stdoutWrite! : Str => Result {} InternalIOErr
stderrLine! : Str => Result {} InternalIOErr
stderrWrite! : Str => Result {} InternalIOErr

# TCP
sendRequest! : Box Request => ResponseFromHost

TcpStream := Box {}
tcpConnect! : Str, U16 => Result TcpStream Str
tcpReadUpTo! : TcpStream, U64 => Result (List U8) Str
tcpReadExactly! : TcpStream, U64 => Result (List U8) Str
tcpReadUntil! : TcpStream, U8 => Result (List U8) Str
tcpWrite! : TcpStream, List U8 => Result {} Str

# SQLite3
sqliteExecute! : Str, Str, List InternalSQL.SQLiteBindings => Result (List (List InternalSQL.SQLiteValue)) InternalSQL.SQLiteError

# roc_env from basic-cli
envDict! : {} => List (Str, Str)
tempDir! : {} => List U8
envVar! : Str => Result Str {}
setCwd! : List U8 => Result {} {}
exePath! : {} => Result (List U8) {}
getLocale! : {} => Result Str {}
getLocales! : {} => List Str
currentArchOS! : {} => { arch : Str, os : Str }
posixTime! : {} => U128

# TODO get from roc_env when it's added
cwd! : {} => Result (List U8) {}
