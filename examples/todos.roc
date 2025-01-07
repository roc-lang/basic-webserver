# Webapp for todos using a SQLite 3 database
app [server] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.Http exposing [Request, Response]
import pf.Sqlite
import pf.Stdout
import pf.Url
import pf.Utc
import "todos.html" as todoHtml : List U8

server = { init!, respond! }

Model ok err1 err2 err3 err4 : {
    list_todos_query! : Sqlite.QueryManyFn {} { id : I64, task : Str, status : Str } err1,
    create_todo_query! : Sqlite.ExecuteFn { task : Str, status : Str } err2,
    last_created_todo_query! : Sqlite.QueryFn {} { id : I64, task : Str, status : Str } err3,
    exec_transaction! : Sqlite.TransactionFn ok err4,
}

init! : {} => Result (Model _ _ _ _ _) [Exit I32 Str]_
init! = \{} ->
    db_path = try read_env_var! "DB_PATH"

    list_todos_query! =
        try Sqlite.prepare_query_many! {
            path: db_path,
            query: "SELECT id, task, status FROM todos",
            bindings: \{} -> [],
            rows: { Sqlite.decode_record <-
                id: Sqlite.i64 "id",
                task: Sqlite.str "task",
                status: Sqlite.str "status",
            },
        }
    create_todo_query! =
        try Sqlite.prepare_execute! {
            path: db_path,
            query: "INSERT INTO todos (task, status) VALUES (:task, :status)",
            bindings: \{ task, status } -> [
                { name: ":task", value: String task },
                { name: ":status", value: String status },
            ],
        }
    last_created_todo_query! =
        try Sqlite.prepare_query! {
            path: db_path,
            query: "SELECT id, task, status FROM todos WHERE id = last_insert_rowid()",
            bindings: \{} -> [],
            row: { Sqlite.decode_record <-
                id: Sqlite.i64 "id",
                task: Sqlite.str "task",
                status: Sqlite.str "status",
            },
        }
    exec_transaction! = try Sqlite.prepare_transaction! { path: db_path }

    Ok { list_todos_query!, create_todo_query!, last_created_todo_query!, exec_transaction! }

respond! : Request, Model _ _ _ _ _ => Result Response [ServerErr Str]_
respond! = \req, model ->
    response_task =
        try log_request! req

        split_url =
            req.uri
            |> Url.from_str
            |> Url.path
            |> Str.splitOn "/"

        # Route to handler based on url path
        when split_url is
            ["", ""] -> byte_response 200 todoHtml
            ["", "todos", ..] -> route_todos! model req
            _ -> text_response 404 "URL Not Found (404)"

    # Handle any application errors
    response_task |> Result.mapErr map_app_err

AppError : [
    EnvVarNotSet Str,
    StdoutErr Str,
]

map_app_err : AppError -> [ServerErr Str]
map_app_err = \app_err ->
    when app_err is
        EnvVarNotSet var_name -> ServerErr "Environment variable \"$(var_name)\" was not set. Please set it to the path of todos.db"
        StdoutErr msg -> ServerErr msg

route_todos! : Model _ _ _ _ _, Request => Result Response _
route_todos! = \model, req ->
    when req.method is
        GET ->
            list_todos! model

        POST ->
            # Create todo
            when task_from_query req.uri is
                Ok props -> create_todo! model props
                Err InvalidQuery -> text_response 400 "Invalid query string, I expected: ?task=foo&status=bar"

        other_method ->
            # Not supported
            text_response 405 "HTTP method $(Inspect.toStr other_method) is not supported for the URL $(req.uri)"

list_todos! : Model _ _ _ _ _ => Result Response _
list_todos! = \{ list_todos_query! } ->
    when list_todos_query! {} is
        Ok task ->
            task
            |> List.map encode_task
            |> Str.joinWith ","
            |> \list -> "[$(list)]"
            |> Str.toUtf8
            |> json_response

        Err err ->
            err_response err

create_todo! : Model _ _ _ _ _, { task : Str, status : Str } => Result Response _
create_todo! = \model, params ->
    result =
        model.exec_transaction! \{} ->
            try model.create_todo_query! params
            out = try model.last_created_todo_query! {}
            Ok out

    when result is
        Ok task ->
            task
            |> encode_task
            |> Str.toUtf8
            |> json_response

        Err err ->
            err_response err

task_from_query : Str -> Result { task : Str, status : Str } [InvalidQuery]
task_from_query = \url ->
    params = url |> Url.from_str |> Url.query_params

    when (params |> Dict.get "task", params |> Dict.get "status") is
        (Ok task, Ok status) -> Ok { task: Str.replaceEach task "%20" " ", status: Str.replaceEach status "%20" " " }
        _ -> Err InvalidQuery

encode_task : { id : I64, task : Str, status : Str } -> Str
encode_task = \{ id, task, status } ->
    # TODO: this should use our json encoder
    """
    {"id":$(Num.toStr id),"task":"$(task)","status":"$(status)"}
    """

json_response : List U8 -> Result Response []
json_response = \bytes ->
    Ok {
        status: 200,
        headers: [
            { name: "Content-Type", value: "application/json; charset=utf-8" },
        ],
        body: bytes,
    }

err_response : err -> Result Response * where err implements Inspect
err_response = \err ->
    byte_response 500 (Str.toUtf8 (Inspect.toStr err))

text_response : U16, Str -> Result Response []
text_response = \status, str ->
    Ok {
        status,
        headers: [
            { name: "Content-Type", value: "text/html; charset=utf-8" },
        ],
        body: Str.toUtf8 str,
    }

byte_response : U16, List U8 -> Result Response *
byte_response = \status, bytes ->
    Ok {
        status,
        headers: [
            { name: "Content-Type", value: "text/html; charset=utf-8" },
        ],
        body: bytes,
    }

log_request! : Request => Result {} [StdoutErr Str]
log_request! = \req ->
    datetime = Utc.to_iso_8601 (Utc.now! {})

    Stdout.line! "$(datetime) $(Inspect.toStr req.method) $(req.uri)"
    |> Result.mapErr \err -> StdoutErr (Inspect.toStr err)

read_env_var! : Str => Result Str [EnvVarNotSet Str]_
read_env_var! = \env_var_name ->
    Env.var! env_var_name
    |> Result.mapErr \_ -> EnvVarNotSet env_var_name
