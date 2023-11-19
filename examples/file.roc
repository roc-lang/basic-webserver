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
    maybeExe <- Env.exePath |> Task.attempt
    printExe = when maybeExe is 
        Ok exePath -> Stdout.line "Executable path: \(Path.display exePath)\n"
        Err ExePathUnavailable -> Stderr.line "Unable to get executable path\n"

    {} <- printExe |> Task.await

    # Read the contents of the log file
    result <- File.readUtf8 (Path.fromStr "examples/log.txt") |> Task.attempt

    task = 
        when result is 
            Ok contents -> Stdout.line contents
            Err (FileReadErr path err) -> Stdout.line "Error reading file \(Path.display path) with \(File.readErrToStr err)"
            Err (FileReadUtf8Err path _) -> Stdout.line "Error reading file \(Path.display path) as utf8" 

    {} <- task |> Task.await

    # Delete the file
    # _ <- File.delete path |> Task.attempt

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "Logged request\n" }



