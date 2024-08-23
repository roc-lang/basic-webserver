# Webapp for todos using a SQLite 3 database
app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Env
import pf.Sqlite
import pf.Url
import pf.Utc
import "todos.html" as todoHtml : List U8

Model : {
    listTodosStmt : Sqlite.Stmt,
    beginStmt : Sqlite.Stmt,
    createTodoStmt : Sqlite.Stmt,
    lastCreatedTodoStmt : Sqlite.Stmt,
    endStmt : Sqlite.Stmt,
}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init =
    dbPath = Env.var "DB_PATH" |> Task.mapErr! \_ -> Exit -1 "<DB_PATH> not set on environment"

    listTodosStmt =
        Sqlite.prepare {
            path: dbPath,
            query: "SELECT id, task, status FROM todos",
        }
            |> Task.mapErr! \err -> Exit -2 "Failed to prepare Sqlite statement: $(Inspect.toStr err)"

    beginStmt =
        Sqlite.prepare {
            path: dbPath,
            query: "BEGIN",
        }
            |> Task.mapErr! \err -> Exit -2 "Failed to prepare Sqlite statement: $(Inspect.toStr err)"

    createTodoStmt =
        Sqlite.prepare {
            path: dbPath,
            query: "INSERT INTO todos (task, status) VALUES (:task, :status)",
        }
            |> Task.mapErr! \err -> Exit -2 "Failed to prepare Sqlite statement: $(Inspect.toStr err)"

    lastCreatedTodoStmt =
        Sqlite.prepare {
            path: dbPath,
            query: "SELECT id, task, status FROM todos WHERE id = last_insert_rowid()",
        }
            |> Task.mapErr! \err -> Exit -2 "Failed to prepare Sqlite statement: $(Inspect.toStr err)"

    endStmt =
        Sqlite.prepare {
            path: dbPath,
            query: "END",
        }
            |> Task.mapErr! \err -> Exit -2 "Failed to prepare Sqlite statement: $(Inspect.toStr err)"

    Task.ok {
        listTodosStmt,
        beginStmt,
        createTodoStmt,
        lastCreatedTodoStmt,
        endStmt,
    }

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, model ->
    responseTask =
        logRequest! req

        splitUrl =
            req.url
            |> Url.fromStr
            |> Url.path
            |> Str.split "/"

        # Route to handler based on url path
        when splitUrl is
            ["", ""] -> byteResponse 200 todoHtml
            ["", "todos", ..] -> routeTodos model req
            _ -> textResponse 404 "URL Not Found (404)"

    # Handle any application errors
    responseTask |> Task.onErr handleErr

AppError : [
    EnvVarNotSet Str,
]

routeTodos : Model, Request -> Task Response *
routeTodos = \model, req ->
    when req.method is
        Get ->
            listTodos model

        Post ->
            # Create todo
            when taskFromQuery req.url is
                Ok props -> createTodo model props
                Err InvalidQuery -> textResponse 400 "Invalid query string, I expected: ?task=foo&status=bar"

        otherMethod ->
            # Not supported
            textResponse 405 "HTTP method $(Inspect.toStr otherMethod) is not supported for the URL $(req.url)"

listTodos : Model -> Task Response *
listTodos = \model ->
    result = listTodosQuery model |> Task.result!

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

listTodosQuery : Model -> Task (List { id : I64, task : Str, status : Str }) _
listTodosQuery = \{ listTodosStmt } ->
    Sqlite.queryPrepared {
        stmt: listTodosStmt,
        bindings: [],
        rows: { Sqlite.decodeRecord <-
            id: Sqlite.i64 "id",
            task: Sqlite.str "task",
            status: Sqlite.str "status",
        },
    }

createTodo : Model, { task : Str, status : Str } -> Task Response *
createTodo = \model, params ->
    result = createTodoTransaction model params |> Task.result!

    when result is
        Ok task ->
            task
            |> encodeTask
            |> Str.toUtf8
            |> jsonResponse

        Err err ->
            errResponse err

createTodoTransaction : Model, { task : Str, status : Str } -> Task { id : I64, task : Str, status : Str } _
createTodoTransaction = \{ beginStmt, createTodoStmt, lastCreatedTodoStmt, endStmt }, { task, status } ->
    # TODO: create a nice transaction wrapper that will rollback if any intermediate stage fails
    # Currently, if this fails part way through, it will just lock the database with a left open trasaction.
    Sqlite.executePrepared! {
        stmt: beginStmt,
        bindings: [],
    }
    Sqlite.executePrepared! {
        stmt: createTodoStmt,
        bindings: [
            { name: ":task", value: String task },
            { name: ":status", value: String status },
        ],
    }
    createdTask =
        Sqlite.queryExactlyOnePrepared! {
            stmt: lastCreatedTodoStmt,
            bindings: [],
            row: { Sqlite.decodeRecord <-
                id: Sqlite.i64 "id",
                task: Sqlite.str "task",
                status: Sqlite.str "status",
            },
        }
    Sqlite.executePrepared! {
        stmt: endStmt,
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

logRequest : Request -> Task {} *
logRequest = \req ->
    datetime = Utc.now! |> Utc.toIso8601Str

    Stdout.line! "$(datetime) $(Http.methodToStr req.method) $(req.url)"

handleErr : AppError -> Task Response *
handleErr = \appErr ->

    # Build error message
    errMsg =
        when appErr is
            EnvVarNotSet varName -> "Environment variable \"$(varName)\" was not set. Please set it to the path of todos.db"

    # Log error to stderr
    Stderr.line! "Internal Server Error:\n\t$(errMsg)"
    Stderr.flush!

    # Respond with Http 500 Error
    Task.ok {
        status: 500,
        headers: [],
        body: Str.toUtf8 "Internal Server Error.",
    }
