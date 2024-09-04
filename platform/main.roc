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
        Tcp,
        Url,
        Utc,
        Sleep,
        Command,
        Sqlite,
        Jwt,
    ]
    packages {}
    imports [Stderr]
    provides [forHost]

import Http
import InternalHttp

ForHost : {
    init : Task (Box Model) I32,
    respond : InternalHttp.RequestToAndFromHost, Box Model -> Task InternalHttp.ResponseToHost [],
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
                    Stderr.line str
                    |> Task.onErr \_ -> Task.err code
                    |> Task.await \{} -> Task.err code

            Err err ->
                Stderr.line
                    """
                    Program exited with error:
                        $(Inspect.toStr err)

                    Tip: If you do not want to exit on this error, use `Task.mapErr` to handle the error.
                    Docs for `Task.mapErr`: <https://roc-lang.github.io/basic-webserver/Task/#mapErr>
                    """
                |> Task.onErr \_ -> Task.err 1
                |> Task.await \_ -> Task.err 1

respond : InternalHttp.RequestToAndFromHost, Box Model -> Task InternalHttp.ResponseToHost []
respond = \request, boxedModel ->
    when server.respond (InternalHttp.fromHostRequest request) (Box.unbox boxedModel) |> Task.result! is
        Ok response -> Task.ok response
        Err (ServerErr msg) ->
            Stderr.line msg
                |> Task.onErr! \_ -> crash "unable to write to stderr"

            # returns a http server error response
            Task.ok {
                status: 500,
                headers: [],
                body: [],
            }

        Err err ->
            """
            Server error:
                $(Inspect.toStr err)

            Tip: If you do not want to see this error, use `Task.mapErr` to handle the error.
            Docs for `Task.mapErr`: <https://roc-lang.github.io/basic-webserver/Task/#mapErr>
            """
                |> Stderr.line
                |> Task.onErr! \_ -> crash "unable to write to stderr"

            Task.ok {
                status: 500,
                headers: [],
                body: [],
            }
