app "dir"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.Dir,
        pf.Path,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->

    # List contents of examples directory
    result <- Dir.list (Path.fromStr "examples") |> Task.attempt

    task = when result is 
        Ok paths ->  
            paths 
            |> List.map Path.display
            |> Str.joinWith ","
            |> Stdout.line 
                
        Err (DirReadErr path err) -> 
            Stderr.line "Error reading directory \(Path.display path) with \(err)"

    {} <- task |> Task.await

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "Logged request\n" }
