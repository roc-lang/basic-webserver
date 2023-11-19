app "command"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.Command,
        pf.Utc,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \req ->

    # Log request date, method and url using echo program
    date <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await
    result <- 
        Command.new "echo"
        |> Command.arg "\(date) \(Http.methodToStr req.method) \(req.url)"
        |> Command.status
        |> Task.attempt

    when result is 
        Ok {} -> respond "Command succeeded\n"
        Err (ExitCode code) -> respond "Command exited with code \(Num.toStr code)\n"
        Err (KilledBySignal) -> respond "Command was killed by signal\n"
        Err (IOError str) -> respond "IO Error: \(str)\n"

respond = \str -> Task.ok { status: 200, headers: [], body: Str.toUtf8 str }