# Webapp for todos using a SQLite 3 database
app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Command
import pf.Env
import pf.Url
import pf.Utc
import "todos.html" as todoHtml : List U8

Model : {}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init = Task.ok {}

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, _ ->
    responseTask =
        logRequest! req
        isSqliteInstalled!

        dbPath = readEnvVar! "DB_PATH"

        splitUrl =
            req.url
            |> Url.fromStr
            |> Url.path
            |> Str.split "/"

        # Route to handler based on url path
        when splitUrl is
            ["", ""] -> byteResponse 200 todoHtml
            ["", "todos", ..] -> routeTodos dbPath req
            _ -> textResponse 404 "URL Not Found (404)"

    # Handle any application errors
    responseTask |> Task.onErr handleErr

AppError : [
    Sqlite3NotInstalled,
    EnvVarNotSet Str,
]

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
    output <-
        Command.new "sqlite3"
        |> Command.arg dbPath
        |> Command.arg ".mode json"
        |> Command.arg "SELECT id, task, status FROM todos;"
        |> Command.output
        |> Task.await

    when output.status is
        Ok {} -> jsonResponse output.stdout
        Err _ -> byteResponse 500 output.stderr

createTodo : Str, { task : Str, status : Str } -> Task Response *
createTodo = \dbPath, { task, status } ->
    output <-
        Command.new "sqlite3"
        |> Command.arg dbPath
        |> Command.arg ".mode json"
        |> Command.arg "INSERT INTO todos (task, status) VALUES ('$(task)', '$(status)');"
        |> Command.arg "SELECT id, task, status FROM todos WHERE id = last_insert_rowid();"
        |> Command.output
        |> Task.await

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
    sqlite3Res <-
        Command.new "sqlite3"
        |> Command.arg "--version"
        |> Command.status
        |> Task.attempt

    when sqlite3Res is
        Ok {} -> Task.ok {}
        Err _ -> Task.err Sqlite3NotInstalled

logRequest : Request -> Task {} *
logRequest = \req ->
    datetime = Utc.now! |> Utc.toIso8601Str

    Stdout.line "$(datetime) $(Http.methodToStr req.method) $(req.url)"

readEnvVar : Str -> Task Str [EnvVarNotSet Str]_
readEnvVar = \envVarName ->
    Env.var envVarName
    |> Task.mapErr \_ -> EnvVarNotSet envVarName

handleErr : AppError -> Task Response *
handleErr = \appErr ->

    # Build error message
    errMsg =
        when appErr is
            EnvVarNotSet varName -> "Environment variable \"$(varName)\" was not set. Please set it to the path of todos.db"
            Sqlite3NotInstalled -> "I failed to call `sqlite3 --version`, is sqlite installed?"
    # Log error to stderr
    Stderr.line! "Internal Server Error:\n\t$(errMsg)"
    _ <- Stderr.flush |> Task.attempt

    # Respond with Http 500 Error
    Task.ok {
        status: 500,
        headers: [],
        body: Str.toUtf8 "Internal Server Error.",
    }
