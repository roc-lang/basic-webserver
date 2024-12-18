app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Dir
import pf.Env
import pf.Path
import pf.Http exposing [Request, Response]

Model : {}

init! : {} => Result Model _
init! = \{} ->
    # Get current working directory
    cwd =
        Env.cwd! {}
        |> Result.mapErr? \CwdUnavailable -> Exit 1 "Unable to read current working directory"

    Stdout.line!? "The current working directory is $(Path.display cwd)"

    # Try to set cwd to examples
    Env.set_cwd! (Path.from_str "examples/")
    |> Result.mapErr? \InvalidCwd -> Exit 1 "Unable to set cwd to examples/"

    try Stdout.line! "Set cwd to examples/"

    # List contents of examples directory
    paths =
        Dir.list! "./"
        |> Result.mapErr? \DirErr err -> Exit 1 "Error reading directory ./:\n\t$(Inspect.toStr err)"

    paths
    |> List.map Path.display
    |> Str.joinWith ","
    |> \paths_str -> "The paths are;\n$(paths_str)"
    |> Stdout.line!?

    Ok {}

respond! : Request, Model => Result Response []
respond! = \_, _ ->
    Ok {
        status: 200,
        headers: [],
        body: Str.toUtf8 "Logged request",
    }
