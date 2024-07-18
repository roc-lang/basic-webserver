app [main] { pf: platform "../platform/main.roc" }

import pf.Http exposing [Request, Response]
import pf.Command
import pf.Utc

main : Request -> Task Response []
main = \req ->

    # Log request date, method and url using echo program
    datetime = Utc.now! |> Utc.toIso8601Str
    result <-
        Command.new "echo"
        |> Command.arg "$(datetime) $(Http.methodToStr req.method) $(req.url)"
        |> Command.status
        |> Task.attempt

    when result is
        Ok {} -> respond "Command succeeded\n"
        Err (ExitCode code) -> respond "Command exited with code $(Num.toStr code)\n"
        Err KilledBySignal -> respond "Command was killed by signal\n"
        Err (IOError str) -> respond "IO Error: $(str)\n"

respond = \str -> Task.ok { status: 200, headers: [], body: Str.toUtf8 str }
