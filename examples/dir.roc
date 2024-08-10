app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Dir
import pf.Env
import pf.Path
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]

Model : {}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init = Task.ok {}

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->
    # Get current working directory
    {} <-
        Env.cwd
        |> Task.await \cwd -> Stdout.line "The current working directory is $(Path.display cwd)"
        |> Task.onErr \CwdUnavailable -> Stderr.line "Unable to read current working directory"
        |> Task.await

    # Try to set cwd to examples
    {} <-
        Env.setCwd (Path.fromStr "examples")
        |> Task.await \{} -> Stdout.line "Set cwd to examples/"
        |> Task.onErr \InvalidCwd -> Stderr.line "Unable to set cwd to examples/"
        |> Task.await

    # List contents of examples directory
    {} <-
        Dir.list (Path.fromStr "./")
        |> Task.await \paths ->
            paths
            |> List.map Path.display
            |> Str.joinWith ","
            |> \pathsStr -> "The paths are;\n$(pathsStr)"
            |> Stdout.line
        |> Task.onErr \DirReadErr path err ->
            Stderr.line "Error reading directory $(Path.display path):\n\t$(err)"
        |> Task.await

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "Logged request\n" }
