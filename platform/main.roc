platform "webserver"
    requires { Model } {
        init! : {} => Result Model [Exit I32 Str]_,
        respond! : Http.Request, Model => Result Http.Response [ServerErr Str]_,
    }
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
        Cmd,
        SQLite3,
    ]
    packages {}
    imports []
    provides [initForHost!, respondForHost!]

import Http
import Stderr
import InternalHttp

initForHost! : I32 => Result (Box Model) I32
initForHost! = \_ ->
    when init! {} is
        Ok model -> Ok (Box.box model)
        Err (Exit code msg) ->
            if Str.isEmpty msg then
                Err code
            else
                _ = Stderr.line! msg
                Err code

        Err err ->
            _ = Stderr.line!
                """
                Program exited with error:
                    $(Inspect.toStr err)

                Tip: If you do not want to exit on this error, use `Task.mapErr` to handle the error.
                Docs for `Task.mapErr`: <https://roc-lang.github.io/basic-webserver/Task/#mapErr>
                """
            Err 1

respondForHost! : InternalHttp.RequestToAndFromHost, Box Model => Result InternalHttp.ResponseToHost []
respondForHost! = \request, boxedModel ->
    when respond! (InternalHttp.fromHostRequest request) (Box.unbox boxedModel) is
        Ok response -> Ok response
        Err (ServerErr msg) ->
            # dicard the err here if stderr fails
            _ = Stderr.line! msg

            # returns a http server error response
            Ok {
                status: 500,
                headers: [],
                body: [],
            }

        Err err ->
            # dicard the err here if stderr fails
            _ = Stderr.line!
                """
                Server error:
                    $(Inspect.toStr err)

                Tip: If you do not want to see this error, use `Task.mapErr` to handle the error.
                Docs for `Task.mapErr`: <https://roc-lang.github.io/basic-webserver/Task/#mapErr>
                """

            # returns a http server error response
            Ok {
                status: 500,
                headers: [],
                body: [],
            }
