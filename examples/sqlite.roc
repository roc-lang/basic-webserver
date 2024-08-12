app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Sqlite
import pf.Env

Model : { stmt : Sqlite.Stmt }

server = { init, respond }

init : Task Model [Exit I32 Str]_
init =
    dbPath = Env.var "DB_PATH" |> Task.mapErr! \_ -> Exit -1 "<DB_PATH> not set on environment"
    stmt =
        Sqlite.prepare {
            path: dbPath,
            query: "SELECT id, task FROM todos WHERE status = :status;",
        }
            |> Task.mapErr! \err -> Exit -2 "Failed to prepare Sqlite statement: $(Inspect.toStr err)"

    Task.ok {
        stmt,
    }

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, { stmt } ->
    rows =
        queryTodosByStatus stmt "completed"
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

queryTodosByStatus = \stmt, status ->
    Sqlite.queryPrepared! {
        stmt,
        bindings: [{ name: ":status", value: String status }],
        rows: { Sqlite.decodeRecord <-
            id: Sqlite.i64 "id" |> Sqlite.mapValue Num.toStr,
            task: Sqlite.str "task",
        },
    }
