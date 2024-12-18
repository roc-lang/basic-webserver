app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.SQLite3
import pf.Env

Model : {}

init! : {} => Result Model []
init! = \{} -> Ok {}

respond! : Request, Model => Result Response _
respond! = \_, _ ->
    # Read DB_PATH environment variable
    maybe_db_path =
        Env.var! "DB_PATH"
        |> Result.mapErr \_ -> ServerErr "DB_PATH not set on environment"

    # Query todos table
    strings : Str
    strings =
        SQLite3.execute! {
            path: maybe_db_path |> Result.withDefault "<DB_PATH> not set on environment",
            query: "SELECT id, task FROM todos WHERE status = :status;",
            bindings: [{ name: ":status", value: String "completed" }],
        }
        |> try
        |> \rows ->
            # Parse each row into a string
            List.map rows \cols ->
                when cols is
                    [Integer id, String task] -> "row $(Num.toStr id), task: $(task)"
                    _ -> crash "unexpected values returned, expected Integer and String got $(Inspect.toStr cols)"
        |> Str.joinWith "\n"

    # Print out the results
    try Stdout.line! strings

    Ok {
        status: 200,
        headers: [{ name: "Content-Type", value: "text/html; charset=utf-8" }],
        body: Str.toUtf8 strings,
    }
