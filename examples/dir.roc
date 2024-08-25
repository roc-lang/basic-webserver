app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Dir
import pf.Env
import pf.Path
import pf.Http exposing [Request, Response]

Model : {}

server = { init, respond }

init : Task Model _
init =
    # Get current working directory
    cwd = Env.cwd |> Task.mapErr! \CwdUnavailable -> Exit 1 "Unable to read current working directory"

    Stdout.line! "The current working directory is $(Path.display cwd)"

    # Try to set cwd to examples
    Env.setCwd (Path.fromStr "examples/")
    |> Task.mapErr! \InvalidCwd -> Exit 1 "Unable to set cwd to examples/"

    Stdout.line! "Set cwd to examples/"

    # List contents of examples directory
    paths =
        Path.fromStr "./"
        |> Dir.list
        |> Task.mapErr! \DirReadErr path err -> Exit 1 "Error reading directory $(Path.display path):\n\t$(err)"

    paths
        |> List.map Path.display
        |> Str.joinWith ","
        |> \pathsStr -> "The paths are;\n$(pathsStr)"
        |> Stdout.line!

    Task.ok {}

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->
    Task.ok { status: 200, headers: [], body: Str.toUtf8 "Logged request" }
