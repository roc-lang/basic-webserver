app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.File
import pf.Path
import pf.Http exposing [Request, Response]

# Model represents the content of the file we read in `init`.
Model : Str

# We only read the file once in `init`. If that fails, we don't launch the server.
init! : {} => Result Model [Exit I32 Str]_
init! = \{} ->
    # Read the contents of examples/file.roc
    File.read_utf8!("examples/file.roc")
    |> Result.map_ok(\contents -> "Source code of current program:\n\n${contents}")
    |> Result.map_err(
        \err ->
            when err is
                FileReadErr(path, file_err) ->
                    Exit(
                        -1,
                        "Failed to launch server!\nError reading file ${Path.display(path)}:\n\t${Inspect.to_str(file_err)}",
                    )

                FileReadUtf8Err(path, _) ->
                    Exit(
                        -2,
                        "Failed to launch server!\nError: failed to read file ${Path.display(path)} as utf8.",
                    ),
    )

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = \_, model ->
    # If the server launched, the model contains the file content.
    Ok({ status: 200, headers: [], body: Str.to_utf8(model) })
