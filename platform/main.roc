platform "webserver"
    requires { Model } { server : {
        init : Task Model [Exit I32 Str]_,
        respond : Http.Request, Model -> Task Http.Response [ServerErr Str]_,
    } }
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
        SQLite3,
    ]
    packages {}
    imports [
        Task.{ Task },
        Stderr.{ line },
    ]
    provides [forHost]

import InternalTask
import Http
import InternalHttp

ForHost : {
    init : Task (Box Model) I32,
    respond : InternalHttp.RequestToAndFromHost, Box Model -> InternalTask.Task InternalHttp.ResponseToHost [],
}

forHost : ForHost
forHost = { init, respond }

init : Task (Box Model) I32
init =
    Task.attempt server.init \res ->
        when res is
            Ok model -> Task.ok (Box.box model)
            Err (Exit code str) ->
                if Str.isEmpty str then
                    Task.err code
                else
                    line str
                    |> Task.onErr \_ -> Task.err code
                    |> Task.await \{} -> Task.err code

            Err err ->
                line
                    """
                    Program exited with error:
                        $(Inspect.toStr err)

                    Tip: If you do not want to exit on this error, use `Task.mapErr` to handle the error.
                    Docs for `Task.mapErr`: <https://www.roc-lang.org/packages/basic-cli/Task#mapErr>
                    """
                |> Task.onErr \_ -> Task.err 1
                |> Task.await \_ -> Task.err 1

respond : InternalHttp.RequestToAndFromHost, Box Model -> InternalTask.Task InternalHttp.ResponseToHost []
respond = \request, boxedModel ->
    when server.respond (InternalHttp.fromHostRequest request) (Box.unbox boxedModel) |> Task.result! is
        Ok response -> Task.ok response
        Err (ServerErr msg) ->
            # prints the error message to stderr
            line! msg

            # returns a http server error response
            InternalTask.ok {
                status: 500,
                headers: [],
                body: [],
            }

        Err err ->
            line!
                """
                Server error:
                    $(Inspect.toStr err)

                Tip: If you do not want to see this error, use `Task.mapErr` to handle the error.
                Docs for `Task.mapErr`: <https://www.roc-lang.org/packages/basic-webserver/Task#mapErr>
                """

            InternalTask.ok {
                status: 500,
                headers: [],
                body: [],
            }
