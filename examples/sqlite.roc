app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Sqlite
import pf.Env

Model : { stmt : Sqlite.Stmt }

init! : {} => Result Model _
init! = \{} ->
    # Read DB_PATH environment variable
    db_path =
        Env.var! "DB_PATH"
        |> Result.mapErr \_ -> ServerErr "DB_PATH not set on environment"
        |> try

    stmt =
        Sqlite.prepare! {
            path: db_path,
            query: "SELECT id, task FROM todos WHERE status = :status;",
        }
        |> Result.mapErr \err -> ServerErr "Failed to prepare Sqlite statement: $(Inspect.toStr err)"
        |> try

    Ok { stmt }

respond! : Request, Model => Result Response _
respond! = \_, { stmt } ->
    # Query todos table
    strings : Str
    strings =
        Sqlite.query_many_prepared! {
            stmt,
            bindings: [{ name: ":status", value: String "completed" }],
            rows: { Sqlite.decode_record <-
                id: Sqlite.i64 "id",
                task: Sqlite.str "task",
            },
        }
        |> try
        |> List.map \{ id, task } -> "row $(Num.toStr id), task: $(task)"
        |> Str.joinWith "\n"

    # Print out the results
    try Stdout.line! strings

    Ok {
        status: 200,
        headers: [{ name: "Content-Type", value: "text/html; charset=utf-8" }],
        body: Str.toUtf8 strings,
    }
