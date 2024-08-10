app [Model, server] { pf: platform "../platform/main.roc" }

import pf.File
import pf.Path
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]

Model : Str

server = { init, respond }

# We only read the file once in init. If that fails, we don't launch the server.
init : Task Model [Exit I32 Str]_
init =
    # Read the contents of examples/file.roc
    File.readUtf8 (Path.fromStr "examples/file.roc")
    |> Task.attempt \result ->
        when result is
            Ok contents ->
                Task.ok "Source code of current program:\n\n$(contents)"

            Err (FileReadErr path err) ->
                Exit -1 "Failed to launch server!\nError reading file $(Path.display path):\n\t$(File.readErrToStr err)"
                |> Task.err

            Err (FileReadUtf8Err path _) ->
                Exit -2 "Failed to launch server!\nError: failed to read file $(Path.display path) as utf8."
                |> Task.err

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, model ->
    # Assuming the server launched, the model is the file. Just serve it.
    Task.ok { status: 200, headers: [], body: Str.toUtf8 model }
