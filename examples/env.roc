app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Http exposing [Request, Response]
import pf.Env

# To run this example: check the README.md in this folder

# We'll set this based on env var at server startup
Model : [DebugPrintMode, NonDebugMode]

init! : {} => Result Model [Exit I32 Str]_
init! = |{}|

    # Check if DEBUG environment variable is set
    when Env.decode!("DEBUG") is
        Ok(1) -> Ok(DebugPrintMode)
        _ -> Ok(NonDebugMode)

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |_, debug|
    when debug is
        DebugPrintMode ->
            # Respond with all the current environment variables
            vars : Dict Str Str
            vars = Env.dict!({})

            # Convert the Dict to a list of key-value pairs
            body =
                vars
                |> Dict.to_list
                |> List.map(|(k, v)| "${k}: ${v}")
                |> Str.join_with("\n")
                |> Str.concat("\n")
                |> Str.to_utf8

            Ok({ status: 200, headers: [], body })

        NonDebugMode ->
            # Respond with a message that DEBUG is not set
            Ok({ status: 200, headers: [], body: Str.to_utf8("DEBUG var not set") })
