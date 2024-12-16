# Webapp for todos using a SQLite 3 database
app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Command
import pf.Env
import pf.Url
import pf.Utc
import "todos.html" as todoHtml : List U8

Model : {}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init =
    when isSqliteInstalled |> Task.result! is
        Ok _ -> Task.ok {}
        Err err -> Task.err err

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, _ ->
    responseTask =
        logRequest! req

        dbPath = readEnvVar! "DB_PATH"

        # TODO check if dbPath exists

        splitUrl =
            req.url
            |> Url.fromStr
            |> Url.path
            |> Str.splitOn "/"

        # Route to handler based on url path
        when splitUrl is
            ["", ""] -> byteResponse 200 todoHtml
            ["", "todos", ..] -> routeTodos dbPath req
            _ -> textResponse 404 "URL Not Found (404)"

    # Handle any application errors
    responseTask |> Task.mapErr mapAppErr

AppError : [
    EnvVarNotSet Str,
    StdoutErr Str,
]

mapAppErr : AppError -> [ServerErr Str]
mapAppErr = \appErr ->
    when appErr is
        EnvVarNotSet varName -> ServerErr "Environment variable \"$(varName)\" was not set. Please set it to the path of todos.db"
        StdoutErr msg -> ServerErr msg

routeTodos : Str, Request -> Task Response *
routeTodos = \dbPath, req ->
    when req.method is
        Get ->
            listTodos dbPath

        Post ->
            # Create todo
            when taskFromQuery req.url is
                Ok props -> createTodo dbPath props
                Err InvalidQuery -> textResponse 400 "Invalid query string, I expected: ?task=foo&status=bar"

        otherMethod ->
            # Not supported
            textResponse 405 "HTTP method $(Inspect.toStr otherMethod) is not supported for the URL $(req.url)"

listTodos : Str -> Task Response *
listTodos = \dbPath ->
    output =
        Command.new "sqlite3"
        |> Command.arg dbPath
        |> Command.arg ".mode json"
        |> Command.arg "SELECT id, task, status FROM todos;"
        |> Command.output!

    when output.status is
        Ok {} -> jsonResponse output.stdout
        Err _ -> byteResponse 500 output.stderr

createTodo : Str, { task : Str, status : Str } -> Task Response *
createTodo = \dbPath, { task, status } ->
    output =
        # TODO upgrade this to use the Sqlite API
        Command.new "sqlite3"
        |> Command.arg dbPath
        |> Command.arg ".mode json"
        |> Command.arg "INSERT INTO todos (task, status) VALUES ('$(task)', '$(status)');"
        |> Command.arg "SELECT id, task, status FROM todos WHERE id = last_insert_rowid();"
        |> Command.output!

    when output.status is
        Ok {} -> jsonResponse output.stdout
        Err _ -> byteResponse 500 output.stderr

taskFromQuery : Str -> Result { task : Str, status : Str } [InvalidQuery]
taskFromQuery = \url ->
    params = url |> Url.fromStr |> Url.queryParams

    when (params |> Dict.get "task", params |> Dict.get "status") is
        (Ok task, Ok status) -> Ok { task: Str.replaceEach task "%20" " ", status: Str.replaceEach status "%20" " " }
        _ -> Err InvalidQuery

jsonResponse : List U8 -> Task Response *
jsonResponse = \bytes ->
    Task.ok {
        status: 200,
        headers: [
            { name: "Content-Type", value: "application/json; charset=utf-8" },
        ],
        body: bytes,
    }

textResponse : U16, Str -> Task Response *
textResponse = \status, str ->
    Task.ok {
        status,
        headers: [
            { name: "Content-Type", value: "text/html; charset=utf-8" },
        ],
        body: Str.toUtf8 str,
    }

byteResponse : U16, List U8 -> Task Response *
byteResponse = \status, bytes ->
    Task.ok {
        status,
        headers: [
            { name: "Content-Type", value: "text/html; charset=utf-8" },
        ],
        body: bytes,
    }

isSqliteInstalled : Task {} [Sqlite3NotInstalled]_
isSqliteInstalled =
    Stdout.line! "INFO: Checking if sqlite3 is installed..."

    sqlite3T =
        Command.new "sqlite3"
        |> Command.arg "--version"
        |> Command.status

    when sqlite3T |> Task.result! is
        Ok {} -> Task.ok {}
        Err _ -> Task.err Sqlite3NotInstalled

logRequest : Request -> Task {} [StdoutErr Str]
logRequest = \req ->
    datetime = Utc.now! |> Utc.toIso8601Str

    Stdout.line "$(datetime) $(Http.methodToStr req.method) $(req.url)"
    |> Task.mapErr \err -> StdoutErr (Inspect.toStr err)

readEnvVar : Str -> Task Str [EnvVarNotSet Str]_
readEnvVar = \envVarName ->
    Env.var envVarName
    |> Task.mapErr \_ -> EnvVarNotSet envVarName
