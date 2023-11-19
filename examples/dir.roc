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
    maybeCwd <- Env.cwd |> Task.attempt

    printCwd = 
        when maybeCwd is 
            Ok cwd -> Stdout.line "The current working directory is \(Path.display cwd)"
            Err CwdUnavailable -> Stderr.line "Unable to read current working directory"

    {} <- printCwd |> Task.await

    # Try to set cwd to examples
    maybeSet <- Env.setCwd (Path.fromStr "examples") |> Task.attempt

    printSetResult = 
        when maybeSet is 
            Ok {} -> Stdout.line "Set cwd to examples/"
            Err InvalidCwd -> Stderr.line "Unable to set cwd to examples/"

    {} <- printSetResult |> Task.await

    # List contents of examples directory
    result <- Dir.list (Path.fromStr "./") |> Task.attempt

    task = when result is 
        Ok paths ->  
            paths 
            |> List.map Path.display
            |> Str.joinWith ","
            |> \pathsStr -> "The paths are;\n\(pathsStr)"
            |> Stdout.line 
                
        Err (DirReadErr path err) -> 
            Stderr.line "Error reading directory \(Path.display path) with \(err)"

    {} <- task |> Task.await

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "Logged request\n" }
