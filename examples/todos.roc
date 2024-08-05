# Webapp for todos using a SQLite 3 database
app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Command
import pf.Env
import pf.Sqlite
import pf.Url
import pf.Utc
import "todos.html" as todoHtml : List U8

main : Request -> Task Response []
main = \req ->

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
            _ -> textResponse 404 "URL Not Found (404)\n"

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
            textResponse 405 "HTTP method $(Inspect.toStr otherMethod) is not supported for the URL $(req.url)\n"

listTodos : Str -> Task Response *
listTodos = \dbPath ->
    result = listTodosQuery dbPath |> Task.result!

    when result is
        Ok tasks ->
            tasks
            |> List.map encodeTask
            |> Str.joinWith ","
            |> \list -> "[$(list)]"
            |> Str.toUtf8
            |> jsonResponse

        Err err ->
            errResponse err

listTodosQuery : Str -> Task (List { id : I64, task : Str, status : Str }) _
listTodosQuery = \dbPath ->
    Sqlite.query {
        path: dbPath,
        query: "SELECT id, task, status FROM todos",
        bindings: [],
        rows: { Sqlite.decodeRecord <-
            id: Sqlite.i64 "id",
            task: Sqlite.str "task",
            status: Sqlite.str "status",
        },
    }

createTodo : Str, { task : Str, status : Str } -> Task Response *
createTodo = \dbPath, params ->
    result = createTodoTransaction dbPath params |> Task.result!

    when result is
        Ok task ->
            task
            |> encodeTask
            |> Str.toUtf8
            |> jsonResponse

        Err err ->
            errResponse err

createTodoTransaction : Str, { task : Str, status : Str } -> Task { id : I64, task : Str, status : Str } _
createTodoTransaction = \dbPath, { task, status } ->
    # TODO: create a nice transaction wrapper that will rollback if any intermediate stage fails
    # Currently, if this fails part way through, it will just lock the database with a left open trasaction.
    Sqlite.execute! {
        path: dbPath,
        query: "BEGIN",
        bindings: [],
    }
    Sqlite.execute! {
        path: dbPath,
        query: "INSERT INTO todos (task, status) VALUES (:task, :status)",
        bindings: [
            { name: ":task", value: String task },
            { name: ":status", value: String status },
        ],
    }
    createdTask =
        Sqlite.queryExactlyOne! {
            path: dbPath,
            query: "SELECT id, task, status FROM todos WHERE id = last_insert_rowid()",
            bindings: [],
            row: { Sqlite.decodeRecord <-
                id: Sqlite.i64 "id",
                task: Sqlite.str "task",
                status: Sqlite.str "status",
            },
        }
    Sqlite.execute! {
        path: dbPath,
        query: "END",
        bindings: [],
    }
    Task.ok createdTask

taskFromQuery : Str -> Result { task : Str, status : Str } [InvalidQuery]
taskFromQuery = \url ->
    params = url |> Url.fromStr |> Url.queryParams

    when (params |> Dict.get "task", params |> Dict.get "status") is
        (Ok task, Ok status) -> Ok { task: Str.replaceEach task "%20" " ", status: Str.replaceEach status "%20" " " }
        _ -> Err InvalidQuery

encodeTask : { id : I64, task : Str, status : Str } -> Str
encodeTask = \{ id, task, status } ->
    # Maybe this should use our json encoder
    """
    {"id":$(Num.toStr id),"task":"$(task)","status":"$(status)"}
    """

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

errResponse : err -> Task Response * where err implements Inspect
errResponse = \err ->
    byteResponse 500 (Str.toUtf8 (Inspect.toStr err))

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
        body: Str.toUtf8 "Internal Server Error.\n",
    }
