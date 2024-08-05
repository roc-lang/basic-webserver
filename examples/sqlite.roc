app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Sqlite
import pf.Env

main : Request -> Task Response []
main = \_ ->

    # Read DB_PATH environment variable
    maybeDbPath <- Env.var "DB_PATH" |> Task.attempt

    # Query todos table
    dbPath = maybeDbPath |> Result.withDefault "<DB_PATH> not set on environment"
    rows =
        queryTodosByStatus dbPath "completed"
            |> Task.onErr! \err ->
                # Crash on any errors for now
                crash "$(Inspect.toStr err)"

    body =
        rows
        |> List.map \{ id, task } ->
            "row $(id), task: $(task)"
        |> Str.joinWith "<br/>"
    # Print out the results
    Stdout.line! body

    Task.ok {
        status: 200,
        headers: [{ name: "Content-Type", value: "text/html; charset=utf-8" }],
        body: Str.toUtf8 body,
    }

queryTodosByStatus = \dbPath, status ->
    Sqlite.query! {
        path: dbPath,
        query: "SELECT id, task FROM todos WHERE status = :status;",
        bindings: [{ name: ":status", value: String status }],
        rows: { Sqlite.decodeRecord <-
            id: Sqlite.i64 "id" |> Sqlite.mapValue Num.toStr,
            task: Sqlite.str "task",
        },
    }
