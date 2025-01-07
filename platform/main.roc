platform "webserver"
    requires {} { server : Server _ _ _ }
    exposes [
        Cmd,
        Dir,
        Env,
        File,
        FileMetadata,
        Http,
        MultipartFormData,
        Path,
        Sqlite,
        Stderr,
        Stdout,
        Tcp,
        Url,
        Utc,
    ]
    packages {}
    imports []
    provides [init_for_host!, respond_for_host!]

import Http
import Stderr
import InternalHttp

Server model init_err respond_err : {
    init! : {} => Result model init_err,
    respond! : Http.Request, model => Result Http.Response respond_err,
}

# This just removes the unused error for `Server`
s : Server _ _ _
s = server

init_for_host! : I32 => Result (Box _) I32
init_for_host! = \_ ->
    when s.init! {} is
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

                Tip: If you do not want to exit on this error, use `Result.mapErr` to handle the error.
                Docs for `Result.mapErr`: <https://www.roc-lang.org/builtins/Result#mapErr>
                """
            Err 1

respond_for_host! : InternalHttp.RequestToAndFromHost, Box _ => InternalHttp.ResponseToAndFromHost
respond_for_host! = \request, boxed_model ->
    when s.respond! (InternalHttp.from_host_request request) (Box.unbox boxed_model) is
        Ok response -> InternalHttp.to_host_response response
        Err (ServerErr msg) ->
            # dicard the err here if stderr fails
            _ = Stderr.line! msg

            # returns a http server error response
            {
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

                Tip: If you do not want to see this error, use `Result.mapErr` to handle the error.
                Docs for `Result.mapErr`: <https://www.roc-lang.org/builtins/Result#mapErr>
                """

            # returns a http server error response
            {
                status: 500,
                headers: [],
                body: [],
            }
