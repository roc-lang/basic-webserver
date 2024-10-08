app [Model, server] { pf: platform "../platform/main.roc" }

import pf.File
import pf.Path
import pf.Http exposing [Request, Response]

# Model represents the content of the file we read in `init`.
Model : Str

server = { init, respond }

# We only read the file once in `init`. If that fails, we don't launch the server.
init : Task Model [Exit I32 Str]_
init =
    # Read the contents of examples/file.roc
    when File.readUtf8 (Path.fromStr "examples/file.roc") |> Task.result! is
        Ok contents ->
            Task.ok "Source code of current program:\n\n$(contents)"

        Err (FileReadErr path err) ->
            Exit -1 "Failed to launch server!\nError reading file $(Path.display path):\n\t$(File.readErrToStr err)"
            |> Task.err

        Err (FileReadUtf8Err path) ->
            Exit -2 "Failed to launch server!\nError: failed to read file $(Path.display path) as utf8."
            |> Task.err

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, model ->
    # If the server launched, the model contains the file content.
    Task.ok { status: 200, headers: [], body: Str.toUtf8 model }
