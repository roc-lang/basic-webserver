platform "webserver"
    requires {} { main : Http.Request -> InternalTask.Task Http.Response [] }
    exposes [
        Path,
        Dir,
        Env,
        File,
        FileMetadata,
        Http,
        Stderr,
        Stdout,
        Task,
        Tcp,
        Url,
        Utc,
        Sleep,
        Command,
        Sqlite,
    ]
    packages {}
    imports [
        Task.{ Task },
    ]
    provides [mainForHost]

import InternalTask
import Http
import InternalHttp

mainForHost : InternalHttp.RequestToAndFromHost -> InternalTask.Task InternalHttp.ResponseToHost []
mainForHost = \request -> request |> InternalHttp.fromHostRequest |> main
