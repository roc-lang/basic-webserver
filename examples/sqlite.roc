app [Model, program] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Sqlite
import pf.Env

# To run this example: check the README.md in this folder and set
# `export DB_PATH=./examples/todos.db`

# Sql to create the table:
# CREATE TABLE todos (
#     id INTEGER PRIMARY KEY AUTOINCREMENT,
#     task TEXT NOT NULL,
#     status TEXT NOT NULL
# );

# The database path is resolved once at startup and stored in the Model.
Model : { db_path : Str }

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| {
    db_path =
        match Env.var!("DB_PATH") {
            Ok(p) => p
            Err(_) => "./examples/todos.db"
        }
    Ok({ db_path: db_path })
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, { db_path }| {
    match query_todos_by_status!(db_path, "completed") {
        Ok(todos) => {
            lines = List.map(todos, |todo| Str.inspect(todo))
            body = Str.join_with(lines, "\n")
            Ok({
                status: 200,
                headers: [{ name: "Content-Type", value: "text/html; charset=utf-8" }],
                body: Str.to_utf8(body),
            })
        }
        Err(err) => Err(ServerErr("Failed to query Sqlite: ${Str.inspect(err)}"))
    }
}

Todo : { id : Str, status : TodoStatus, task : Str }

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
decode_todo = |cols|
    |stmt| {
        id = Sqlite.i64("id")(cols)(stmt)?
        task = Sqlite.str("task")(cols)(stmt)?
        status_str = Sqlite.str("status")(cols)(stmt)?
        status = decode_todo_status(status_str)?
        Ok({ id: I64.to_str(id), task, status })
    }

TodoStatus : [Todo, Completed, InProgress]

decode_todo_status = |status_str|
    match status_str {
        "todo" => Ok(Todo)
        "completed" => Ok(Completed)
        "in-progress" => Ok(InProgress)
        _ => Err(ParseError("Unknown status str: ${status_str}"))
    }
