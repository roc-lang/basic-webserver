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
        Ok {} -> okHttp "Command succeeded"
        Err (ExitCode code) ->
            Task.err (ServerErr "Command exited with code $(Num.toStr code)")

        Err KilledBySignal ->
            Task.err (ServerErr "Command was killed by signal")

        Err (IOError str) ->
            Task.err (ServerErr "IO Error: $(str)")

okHttp = \str -> Task.ok { status: 200, headers: [], body: Str.toUtf8 str }
