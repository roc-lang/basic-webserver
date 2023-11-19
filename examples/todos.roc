app "Read todos from SQLite3 response with Json"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.Command,
        pf.Env,
        pf.Url,
        pf.Utc,
        Dict,
        "todos.html" as todoHtml : List U8,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \req ->

    # Get current date-time as ISO8601 string
    date <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await

    # Log request date, method and url to stdout
    {} <- "\(date) \(Http.methodToStr req.method) \(req.url)" |> Stdout.line |> Task.await

    # Read DB_PATH environment variable
    maybeDbPath <- Env.var "DB_PATH" |> Task.attempt

    # Route to handler based on url path
    when req.url |> Url.fromStr |> Url.path |> Str.split "/" is
        ["", ""] -> byteResponse 200 todoHtml
        ["", "todos", ..] -> routeTodos maybeDbPath req
        _ -> textResponse 404 "404 Not Found\n"

routeTodos : Result Str [VarNotFound], Request -> Task Response []
routeTodos = \maybeDbPath, req ->
    when (maybeDbPath, req.method) is
        (Ok dbPath, Get) ->
            # List todos
            listTodos dbPath

        (Ok dbPath, Post) ->
            # Create todo
            when taskFromQuery req.url is
                Ok props -> createTodo dbPath props
                Err InvalidQuery -> textResponse 400 "Invalid query string expected ?task=foo&status=bar"

        (Err VarNotFound, _) ->
            # No DB_PATH environment variable
            textResponse 500 "DB_PATH environment variable not found"

        (_, _) ->
            # Route not found
            textResponse 404 "404 Not Found\n"

listTodos : Str -> Task Response []
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

createTodo : Str, { task : Str, status : Str } -> Task Response []
createTodo = \dbPath, { task, status } ->
    output <-
        Command.new "sqlite3"
        |> Command.arg dbPath
        |> Command.arg ".mode json"
        |> Command.arg "INSERT INTO todos (task, status) VALUES ('\(task)', '\(status)');"
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

jsonResponse : List U8 -> Task Response []
jsonResponse = \bytes ->
    Task.ok {
        status: 200,
        headers: [
            { name: "Content-Type", value: Str.toUtf8 "application/json; charset=utf-8" },
        ],
        body: bytes,
    }

textResponse : U16, Str -> Task Response []
textResponse = \status, str ->
    Task.ok {
        status,
        headers: [
            { name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" },
        ],
        body: Str.toUtf8 str,
    }

byteResponse : U16, List U8 -> Task Response []
byteResponse = \status, bytes ->
    Task.ok {
        status,
        headers: [
            { name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" },
        ],
        body: bytes,
    }
