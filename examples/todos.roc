# Webapp for todos using a SQLite 3 database
app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Cmd
import pf.Env
import pf.Url
import pf.Utc
import "todos.html" as todoHtml : List U8

Model : {}

init! : {} => Result Model [Exit I32 Str]_
init! = \{} ->
    when is_sqlite_installed! {} is
        Ok _ -> Ok {}
        Err err -> Err err

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = \req, _ ->
    response_task =
        try log_request! req

        db_path = try read_env_var! "DB_PATH"

        # Route to handler based on url path
        when Str.splitOn req.uri "/" is
            ["", ""] -> byte_response 200 todoHtml
            ["", "todos", ..] -> route_todos! db_path req
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

route_todos! : Str, Request => Result Response _
route_todos! = \db_path, req ->
    when req.method is
        GET ->
            list_todos! db_path

        POST ->
            # Create todo
            when task_from_query req.uri is
                Ok props -> create_todo! db_path props
                Err InvalidQuery -> text_response 400 "Invalid query string, I expected: ?task=foo&status=bar"

        other_method ->
            # Not supported
            text_response 405 "HTTP method $(Inspect.toStr other_method) is not supported for the URL $(req.uri)"

list_todos! : Str => Result Response _
list_todos! = \db_path ->
    output =
        Cmd.new "sqlite3"
        |> Cmd.arg db_path
        |> Cmd.arg ".mode json"
        |> Cmd.arg "SELECT id, task, status FROM todos;"
        |> Cmd.output!

    when output.status is
        Ok _ -> json_response output.stdout
        Err _ -> byte_response 500 output.stderr

create_todo! : Str, { task : Str, status : Str } => Result Response _
create_todo! = \db_path, { task, status } ->
    output =
        # TODO upgrade this to use the Sqlite API
        Cmd.new "sqlite3"
        |> Cmd.arg db_path
        |> Cmd.arg ".mode json"
        |> Cmd.arg "INSERT INTO todos (task, status) VALUES ('$(task)', '$(status)');"
        |> Cmd.arg "SELECT id, task, status FROM todos WHERE id = last_insert_rowid();"
        |> Cmd.output!

    when output.status is
        Ok _ -> json_response output.stdout
        Err _ -> byte_response 500 output.stderr

task_from_query : Str -> Result { task : Str, status : Str } [InvalidQuery]
task_from_query = \url ->
    params = url |> Url.from_str |> Url.query_params

    when (params |> Dict.get "task", params |> Dict.get "status") is
        (Ok task, Ok status) -> Ok { task: Str.replaceEach task "%20" " ", status: Str.replaceEach status "%20" " " }
        _ -> Err InvalidQuery

json_response : List U8 -> Result Response []
json_response = \bytes ->
    Ok {
        status: 200,
        headers: [
            { name: "Content-Type", value: "application/json; charset=utf-8" },
        ],
        body: bytes,
    }

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

is_sqlite_installed! : {} => Result {} [Sqlite3NotInstalled]_
is_sqlite_installed! = \{} ->

    try Stdout.line! "INFO: Checking if sqlite3 is installed..."

    sqlite3_t! : {} => Result I32 _
    sqlite3_t! = \{} ->
        Cmd.new "sqlite3"
        |> Cmd.arg "--version"
        |> Cmd.status!

    when sqlite3_t! {} is
        Ok _ -> Ok {}
        Err _ -> Err Sqlite3NotInstalled

log_request! : Request => Result {} [StdoutErr Str]
log_request! = \req ->
    datetime = Utc.to_iso_8601 (Utc.now! {})

    Stdout.line! "$(datetime) $(Inspect.toStr req.method) $(req.uri)"
    |> Result.mapErr \err -> StdoutErr (Inspect.toStr err)

read_env_var! : Str => Result Str [EnvVarNotSet Str]_
read_env_var! = \env_var_name ->
    Env.var! env_var_name
    |> Result.mapErr \_ -> EnvVarNotSet env_var_name
