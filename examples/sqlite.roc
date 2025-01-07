app [server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Sqlite
import pf.Env

server = { init!, respond! }

Model err : {
    query_todos_by_status! : Sqlite.QueryManyFn Str { id : I64, task : Str } err,
}

init! : {} => Result (Model _) _
init! = \{} ->
    # Read DB_PATH environment variable
    db_path =
        Env.var! "DB_PATH"
        |> Result.mapErr \_ -> ServerErr "DB_PATH not set on environment"
        |> try

    query_todos_by_status! =
        Sqlite.prepare_query_many! {
            path: db_path,
            query: "SELECT id, task FROM todos WHERE status = :status;",
            bindings: \name -> [{ name: ":status", value: String name }],
            rows: { Sqlite.decode_record <-
                id: Sqlite.i64 "id",
                task: Sqlite.str "task",
            },
        }
        |> Result.mapErr \err -> ServerErr "Failed to prepare Sqlite statement: $(Inspect.toStr err)"
        |> try

    Ok { query_todos_by_status! }

respond! : Request, Model _ => Result Response _
respond! = \_, { query_todos_by_status! } ->
    # Query todos table
    strings : Str
    strings =
        query_todos_by_status! "completed"
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
