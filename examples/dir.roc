app "dir"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Dir,
        pf.Path,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->

    cwd = Path.fromStr "./"

    # List contents of current directory
    result <- Dir.list cwd |> Task.attempt

    task = when result is 
        Ok paths ->  
            paths 
            |> List.map Path.display
            |> Str.joinWith ","
            |> Stdout.line 
                
        Err _ -> Stdout.line "Failed to list directory"

    {} <- task |> Task.await

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "Logged request\n" }

