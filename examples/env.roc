app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Env

Model : {}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init = Task.ok {}

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->
    # Check if DEBUG environment variable is set
    debug <-
        Env.var "DEBUG"
        |> Task.attempt \maybeVar ->
            when maybeVar is
                Ok var if !(Str.isEmpty var) -> Task.ok DebugPrintMode
                _ -> Task.ok NonDebugMode
        |> Task.await

    when debug is
        DebugPrintMode ->
            # Respond with all the current environment variables
            vars = Env.list!

            body =
                vars
                |> List.map (\(k, v) -> "$(k): $(v)")
                |> Str.joinWith "\n"
                |> Str.concat "\n"
                |> Str.toUtf8

            Task.ok { status: 200, headers: [], body }

        NonDebugMode ->
            # Respond with a message that DEBUG is not set
            Task.ok { status: 200, headers: [], body: Str.toUtf8 "DEBUG var not set" }
