app "file"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.File,
        pf.Path,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.Env,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->

    # Print the executable path
    {} <-
        Env.exePath
        |> Task.await \exePath -> Stdout.line "Executable path: \(Path.display exePath)\n"
        |> Task.onErr \ExePathUnavailable -> Stderr.line "Unable to get executable path\n"
        |> Task.await

    # Read the contents of the log file (which shouldn't exist)
    {} <-
        File.readUtf8 (Path.fromStr "examples/log.txt")
        |> Task.attempt \result ->
            when result is
                Ok contents -> Stdout.line contents
                Err (FileReadErr path err) -> Stdout.line "Error reading file \(Path.display path) with \(File.readErrToStr err)"
                Err (FileReadUtf8Err path _) -> Stdout.line "Error reading file \(Path.display path) as utf8"
        |> Task.await

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "Logged request\n" }

