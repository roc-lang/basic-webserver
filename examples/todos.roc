# Web app for todos using a SQLite 3 database.
app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.MultipartFormData
import pf.Path
import pf.Server
import pf.Sqlite
import pf.Stdout
import pf.Url
import pf.Utc
import http.Response
import "todos.html" as todo_html : List(U8)

# To run this example: check the root README.md.
# Set `DB_PATH` to override the default database path (`./examples/todos.db`).

Context : Path.Path

Todo : { id : I64, task : Str, status : Str }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
    db_path =
        match Env.var!("DB_PATH") {
            Ok(path) => Path.from_os_str(path)
            Err(_) => Path.utf8("./examples/todos.db")
        }

    ensure_schema!(db_path) ? |_| Exit(1)

    Ok({ config: Server.default_config, context: db_path })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, db_path|
    match handle_req!(req, db_path) {
        Ok(response) => Ok(Server.respond(response))
        Err(err) => Err(ServerErr(Str.inspect(err)))
    }

handle_req! : Server.Request, Path.Path => Try(Response.Response, _)
handle_req! = |req, db_path| {
    log_request!(req)?

    request_url = Url.resolve(todo_origin, req.target()) ? InvalidRequestTarget
    path_parts = Str.split_on(Url.path(request_url), "/")

    match path_parts {
        ["", ""] => Ok(html_response(200, todo_html))
        ["", "todos"] => route_todos!(db_path, req, request_url)
        ["", "todos", ..] => route_todos!(db_path, req, request_url)
        _ => Ok(text_response(404, "URL Not Found (404)"))
    }
}

todo_origin : Url.Url
todo_origin = "http://localhost"

route_todos! : Path.Path, Server.Request, Url.Url => Try(Response.Response, _)
route_todos! = |db_path, req, request_url|
    match req.method() {
        GET => list_todos!(db_path)

        POST =>
            match task_from_query(request_url) {
                Ok(params) => create_todo!(db_path, params)
                Err(_) => Ok(text_response(400, "Invalid query string; expected ?task=foo&status=bar"))
            }

        other_method =>
            Ok(text_response(405, "HTTP method ${Str.inspect(other_method)} is not supported for ${req.target()}"))
    }

list_todos! : Path.Path => Try(Response.Response, _)
list_todos! = |db_path| {
    todos =
        Sqlite.query_many!({
            path: db_path,
            query: "SELECT id, task, status FROM todos ORDER BY id;",
            bindings: [],
            rows: decode_todo,
        })
        ? |err| DbErr(Str.inspect(err))

    Ok(json_response(todos))
}

create_todo! : Path.Path, { task : Str, status : Str } => Try(Response.Response, _)
create_todo! = |db_path, params| {
    Sqlite.execute!({
        path: db_path,
        query: "INSERT INTO todos (task, status) VALUES (:task, :status);",
        bindings: [
            { name: ":task", value: String(params.task) },
            { name: ":status", value: String(params.status) },
        ],
    })
    ? |err| DbErr(Str.inspect(err))

    todo =
        Sqlite.query!({
            path: db_path,
            query: "SELECT id, task, status FROM todos WHERE id = last_insert_rowid();",
            bindings: [],
            row: decode_todo,
        })
        ? |err| DbErr(Str.inspect(err))

    Ok(json_response([todo]))
}

decode_todo = |cols|
    |stmt| {
        id = Sqlite.i64("id")(cols)(stmt)?
        task = Sqlite.str("task")(cols)(stmt)?
        status = Sqlite.str("status")(cols)(stmt)?

        Ok({ id, task, status })
    }

task_from_query : Url.Url -> Try({ task : Str, status : Str }, [InvalidQuery])
task_from_query = |url| {
    query =
        match Url.query(url) {
            None => return Err(InvalidQuery)
            Some(value) => value
        }
    params =
        MultipartFormData.parse_form_url_encoded(Str.to_utf8(query))
        ? |_| InvalidQuery

    task = Dict.get(params, "task") ? |_| InvalidQuery
    status = Dict.get(params, "status") ? |_| InvalidQuery

    Ok({ task, status })
}

ensure_schema! : Path.Path => Try({}, _)
ensure_schema! = |db_path|
    Sqlite.execute!({
        path: db_path,
        query: "CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY AUTOINCREMENT, task TEXT NOT NULL, status TEXT NOT NULL);",
        bindings: [],
    })

log_request! : Server.Request => Try({}, _)
log_request! = |req| {
    datetime = Utc.to_iso_8601(Utc.now!())
    Ok(Stdout.line!("${datetime} ${Str.inspect(req.method())} ${req.target()}") ? |err| StdoutErr(Str.inspect(err)))
}

json_response : List(Todo) -> Response.Response
json_response = |todos|
    Response.from_status(200)
    .with_headers([{ name: "Content-Type", value: "application/json; charset=utf-8" }])
    .with_body(Str.to_utf8(Json.to_str(todos)))

html_response : U16, List(U8) -> Response.Response
html_response = |status, bytes|
    Response.from_status(status)
    .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
    .with_body(bytes)

text_response : U16, Str -> Response.Response
text_response = |status, body|
    html_response(status, Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
