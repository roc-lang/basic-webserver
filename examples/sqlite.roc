app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Sqlite
import pf.Env
import pf.Path
import http.Response

# To run this example: check the root README.md and set
# `export DB_PATH=./examples/todos.db`

# Sql to create the table:
# CREATE TABLE todos (
#     id INTEGER PRIMARY KEY AUTOINCREMENT,
#     task TEXT NOT NULL,
#     status TEXT NOT NULL
# );

# The database path is resolved once at startup and stored in the Model.
Model : { db_path : Path.Path }
Action : [GetDbPath]
Result : [DbPath(Path.Path)]

program = { init!, transition, respond!, shutdown! }

init! : () => Try({ config : Server.Config, model : Model }, [Exit(I64), ..])
init! = || {
    db_path =
        match Env.var!("DB_PATH") {
            Ok(path) => Path.from_os_str(path)
            Err(_) => Path.utf8("./examples/todos.db")
        }
    Ok({ config: Server.default_config, model: { db_path: db_path } })
}

transition : Action, Model -> { model : Model, result : Result }
transition = |GetDbPath, model| { model, result: DbPath(model.db_path) }

respond! : Server.Request, Server.State(Action, Result) => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, state| {
    DbPath(db_path) = state.apply!(GetDbPath) ? |_| ServerErr("Server is stopping")
    match query_todos_by_status!(db_path, "completed") {
        Ok(todos) => {
            lines = todos.map(|todo| Str.inspect(todo))
            body = Str.join_with(lines, "\n")
            response =
                Response.from_status(200)
                .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
                .with_body(Str.to_utf8(body))
            Ok(Server.respond(response))
        }
        Err(err) => Err(ServerErr("Failed to query Sqlite: ${Str.inspect(err)}"))
    }
}

shutdown! : Server.ShutdownReason, Model => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})

Todo : { id : Str, status : TodoStatus, task : Str }

query_todos_by_status! : Path.Path, Str => Try(List(Todo), _)
query_todos_by_status! = |db_path, status|
    Sqlite.query_many!(
        {
            path: db_path,
            query: "SELECT id, task, status FROM todos WHERE status = :status;",
            bindings: [{ name: ":status", value: String(status) }],
            rows: decode_todo,
        },
    )

# A row decoder is `List(Str) -> (Stmt => Try(a, err))`; the new compiler does not
# support the record-builder (`<-`) sugar, so we combine the leaf decoders by hand.
# This stays unannotated because the inferred decoder error union is compiler-heavy.
decode_todo = |cols|
    |stmt| {
        id = Sqlite.i64("id")(cols)(stmt)?
        task = Sqlite.str("task")(cols)(stmt)?
        status_str = Sqlite.str("status")(cols)(stmt)?
        status = decode_todo_status(status_str)?
        Ok({ id: I64.to_str(id), task, status })
    }

TodoStatus : [Todo, Completed, InProgress]

# This stays unannotated so `ParseError` can merge with decoder errors above.
decode_todo_status = |status_str|
    match status_str {
        "todo" => Ok(Todo)
        "completed" => Ok(Completed)
        "in-progress" => Ok(InProgress)
        _ => Err(ParseError("Unknown status str: ${status_str}"))
    }
