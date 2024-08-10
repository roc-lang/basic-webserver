app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Command
import pf.Utc

Model : {}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init = Task.ok {}

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, _ ->
    # Log request date, method and url using echo program
    datetime = Utc.now! |> Utc.toIso8601Str
    result <-
        Command.new "echo"
        |> Command.arg "$(datetime) $(Http.methodToStr req.method) $(req.url)"
        |> Command.status
        |> Task.attempt

    when result is
        Ok {} -> okHttp "Command succeeded\n"
        Err (ExitCode code) -> okHttp "Command exited with code $(Num.toStr code)\n"
        Err KilledBySignal -> okHttp "Command was killed by signal\n"
        Err (IOError str) -> okHttp "IO Error: $(str)\n"

okHttp = \str -> Task.ok { status: 200, headers: [], body: Str.toUtf8 str }
