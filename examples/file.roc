app [Model, server] { pf: platform "../platform/main.roc" }

import pf.File
import pf.Path
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]

Model : {}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init = Task.ok {}

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->
    # Read the contents of examples/file.roc
    File.readUtf8 (Path.fromStr "examples/file.roc")
    |> Task.attempt \result ->
        when result is
            Ok contents ->
                okHttp "Source code of current program:\n\n$(contents)"

            Err (FileReadErr path err) ->
                internalErrHttp "Error reading file $(Path.display path):\n\t$(File.readErrToStr err)"

            Err (FileReadUtf8Err path _) ->
                internalErrHttp "Error: failed to read file $(Path.display path) as utf8."

okHttp : Str -> Task Response []
okHttp = \bodyStr ->
    Task.ok { status: 200, headers: [], body: Str.toUtf8 bodyStr }

internalErrHttp : Str -> Task Response []
internalErrHttp = \bodyStr ->
    Task.ok { status: 500, headers: [], body: Str.toUtf8 bodyStr }
