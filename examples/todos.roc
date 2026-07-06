# Web app for todos using a SQLite 3 database.
app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Http
import pf.MultipartFormData
import pf.Sqlite
import pf.Stdout
import pf.Url
import pf.Utc
import http.Response
import "todos.html" as todo_html : List(U8)

# To run this example: check the root README.md.
# Set `DB_PATH` to override the default database path (`./examples/todos.db`).

Model : {
    list_todos_stmt : Sqlite.Stmt,
    create_todo_stmt : Sqlite.Stmt,
    last_created_todo_stmt : Sqlite.Stmt,
}

Todo : { id : I64, task : Str, status : Str }

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || {
    db_path =
        match Env.var!("DB_PATH") {
            Ok(path) => path
            Err(_) => "./examples/todos.db"
        }

    ensure_schema!(db_path) ? |_| Exit(1)

    list_todos_stmt =
        Sqlite.prepare!({
            path: db_path,
            query: "SELECT id, task, status FROM todos ORDER BY id;",
        })
        ? |_| Exit(1)

    create_todo_stmt =
        Sqlite.prepare!({
            path: db_path,
            query: "INSERT INTO todos (task, status) VALUES (:task, :status);",
        })
        ? |_| Exit(1)

    last_created_todo_stmt =
        Sqlite.prepare!({
            path: db_path,
            query: "SELECT id, task, status FROM todos WHERE id = last_insert_rowid();",
        })
        ? |_| Exit(1)

    Ok({ list_todos_stmt, create_todo_stmt, last_created_todo_stmt })
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, model|
    match handle_req!(req, model) {
        Ok(response) => Ok(response)
        Err(err) => Err(ServerErr(Str.inspect(err)))
    }

handle_req! : Http.Request, Model => Try(Http.Response, _)
handle_req! = |req, model| {
    log_request!(req)?

    path_parts = Str.split_on(Url.path(Url.from_str(req.uri())), "/")

    match path_parts {
        ["", ""] => Ok(html_response(200, todo_html))
        ["", "todos"] => route_todos!(model, req)
        ["", "todos", ..] => route_todos!(model, req)
        _ => Ok(text_response(404, "URL Not Found (404)"))
    }
}

route_todos! : Model, Http.Request => Try(Http.Response, _)
route_todos! = |model, req|
    match req.method() {
        GET => list_todos!(model)

        POST =>
            match task_from_query(req.uri()) {
                Ok(params) => create_todo!(model, params)
                Err(_) => Ok(text_response(400, "Invalid query string; expected ?task=foo&status=bar"))
            }

        other_method =>
            Ok(text_response(405, "HTTP method ${Str.inspect(other_method)} is not supported for ${req.uri()}"))
    }

list_todos! : Model => Try(Http.Response, _)
list_todos! = |{ list_todos_stmt, create_todo_stmt: _, last_created_todo_stmt: _ }| {
    todos =
        Sqlite.query_many_prepared!({
            stmt: list_todos_stmt,
            bindings: [],
            rows: decode_todo,
        })
        ? |err| DbErr(Str.inspect(err))

    Ok(Http.json_response(Http.JsonValue.list(todos.map(todo_to_json))))
}

create_todo! : Model, { task : Str, status : Str } => Try(Http.Response, _)
create_todo! = |model, params| {
    Sqlite.execute_prepared!({
        stmt: model.create_todo_stmt,
        bindings: [
            { name: ":task", value: String(params.task) },
            { name: ":status", value: String(params.status) },
        ],
    })
    ? |err| DbErr(Str.inspect(err))

    todo =
        Sqlite.query_prepared!({
            stmt: model.last_created_todo_stmt,
            bindings: [],
            row: decode_todo,
        })
        ? |err| DbErr(Str.inspect(err))

    Ok(Http.json_response(Http.JsonValue.list([todo_to_json(todo)])))
}

decode_todo = |cols|
    |stmt| {
        id = Sqlite.i64("id")(cols)(stmt)?
        task = Sqlite.str("task")(cols)(stmt)?
        status = Sqlite.str("status")(cols)(stmt)?

        Ok({ id, task, status })
    }

todo_to_json : Todo -> Http.JsonValue
todo_to_json = |todo|
    Http.JsonValue.object([
        Http.JsonValue.field("id", Http.JsonValue.i64(todo.id)),
        Http.JsonValue.field("task", Http.JsonValue.str(todo.task)),
        Http.JsonValue.field("status", Http.JsonValue.str(todo.status)),
    ])

task_from_query : Str -> Try({ task : Str, status : Str }, [InvalidQuery])
task_from_query = |uri| {
    query = Url.query(Url.from_str(uri))
    params =
        MultipartFormData.parse_form_url_encoded(Str.to_utf8(query))
        ? |_| InvalidQuery

    task = Dict.get(params, "task") ? |_| InvalidQuery
    status = Dict.get(params, "status") ? |_| InvalidQuery

    Ok({ task, status })
}

ensure_schema! : Str => Try({}, _)
ensure_schema! = |db_path|
    Sqlite.execute!({
        path: db_path,
        query: "CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY AUTOINCREMENT, task TEXT NOT NULL, status TEXT NOT NULL);",
        bindings: [],
    })

log_request! : Http.Request => Try({}, _)
log_request! = |req| {
    datetime = Utc.to_iso_8601(Utc.now!())
    Ok(Stdout.line!("${datetime} ${Str.inspect(req.method())} ${req.uri()}") ? |err| StdoutErr(Str.inspect(err)))
}

html_response : U16, List(U8) -> Http.Response
html_response = |status, bytes|
    Response.from_status(status)
    .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
    .with_body(bytes)

text_response : U16, Str -> Http.Response
text_response = |status, body|
    html_response(status, Str.to_utf8(body))
