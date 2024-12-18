app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Http exposing [Request, Response]
import pf.Env

# We'll set this based on env var at server startup
Model : [DebugPrintMode, NonDebugMode]

init! : {} => Result Model [Exit I32 Str]_
init! = \{} ->

    # Check if DEBUG environment variable is set
    when Env.var! "DEBUG" is
        Ok var if !(Str.isEmpty var) -> Ok DebugPrintMode
        _ -> Ok NonDebugMode

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = \_, debug ->
    when debug is
        DebugPrintMode ->
            # Respond with all the current environment variables
            vars : Dict Str Str
            vars = Env.dict! {}

            # Convert the Dict to a list of key-value pairs
            body =
                vars
                |> Dict.toList
                |> List.map \(k, v) -> "$(k): $(v)"
                |> Str.joinWith "\n"
                |> Str.concat "\n"
                |> Str.toUtf8

            Ok { status: 200, headers: [], body }

        NonDebugMode ->
            # Respond with a message that DEBUG is not set
            Ok { status: 200, headers: [], body: Str.toUtf8 "DEBUG var not set" }
