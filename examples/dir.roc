app "dir"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.Dir,
        pf.Env,
        pf.Path,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->

    # Get current working directory
    {} <-
        Env.cwd
        |> Task.await \cwd -> Stdout.line "The current working directory is \(Path.display cwd)"
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
            |> \pathsStr -> "The paths are;\n\(pathsStr)"
            |> Stdout.line
        |> Task.onErr \DirReadErr path err ->
            Stderr.line "Error reading directory \(Path.display path) with \(err)"
        |> Task.await

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "Logged request\n" }
