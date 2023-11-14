app "Read Todos from SQLite3 db and send Json response"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Task.{ Task }, 
        pf.Http.{ Request, Response }, 
        pf.Command,
        pf.Env,
        pf.Url,
        Dict,
        "todos.html" as todoHtml : List U8,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \req ->

    {} <- Stdout.line "\(Http.methodToStr req.method) \(req.url)" |> Task.await

    dbPath <- 
        Env.var "DB_PATH"
        |> Task.onErr \_ -> crash "Unable to read DB_PATH; usage DB_PATH=examples/todos.db roc run examples/todos.roc"
        # TODO figure out why this doesn't work
        # |> Task.onErr \_ -> Task.ok { status: 500, headers: [], body: "Unable to read DB_PATH" |> Str.toUtf8 }
        |> Task.await

    when req.url |> Url.fromStr |> Url.path |> Str.split "/" is
        ["", "todos", ..] -> handleTodos dbPath req
        ["", "index.html", ..] -> Task.ok { status: 200, headers: [contentTypeHtml], body: todoHtml } 
        _ -> notFound

notFound : Task Response []
notFound = 
    Task.ok { status: 404, headers: [], body: "Not Found" |> Str.toUtf8 }

badRequest : Str -> Task Response []
badRequest = \msg ->
    Task.ok { status: 400, headers: [], body: msg |> Str.toUtf8 }

handleTodos : Str, Request -> Task Response []
handleTodos = \dbPath, req ->
    when req.method is 
        Get -> listTodos dbPath
        Post -> 
            when taskFromQuery req.url is
                Ok props -> createTodo dbPath props
                Err InvalidQuery -> badRequest "Invalid query string expected ?task=foo&status=bar"
        _ -> notFound

listTodos : Str -> Task Response []
listTodos = \dbPath ->
    Command.new "sqlite3"
    |> Command.arg dbPath
    |> Command.arg ".mode json"
    |> Command.arg "SELECT id, task, status FROM todos;"
    |> Command.output
    |> Task.map \output -> { status: 200, headers: [contentTypeJson], body: output.stdout }
    |> Task.onErr \(output, _) -> Task.ok { status: 500, headers: [], body: output.stderr }

createTodo : Str, {task: Str, status: Str} -> Task Response []
createTodo = \dbPath, {task, status} ->
    Command.new "sqlite3"
    |> Command.arg dbPath
    |> Command.arg ".mode json"
    |> Command.arg "INSERT INTO todos (task, status) VALUES ('\(task)', '\(status)');"
    |> Command.arg "SELECT id, task, status FROM todos WHERE id = last_insert_rowid();"
    |> Command.output
    |> Task.map \output -> { status: 200, headers: [contentTypeJson], body: output.stdout }
    |> Task.onErr \(output, _) -> Task.ok { status: 500, headers: [], body: output.stderr }

taskFromQuery : Str -> Result {task: Str, status: Str} [InvalidQuery]
taskFromQuery = \url ->
    params = url |> Url.fromStr |> Url.queryParams

    when (params |> Dict.get "task", params |> Dict.get "status") is
        (Ok task, Ok status) -> Ok {task: Str.replaceEach task "%20" " ", status: Str.replaceEach status "%20" " "}
        _ -> Err InvalidQuery

contentTypeJson : Http.Header
contentTypeJson = { name : "Content-Type", value: "application/json; charset=utf-8" |> Str.toUtf8 } 

contentTypeHtml : Http.Header
contentTypeHtml = { name : "Content-Type", value: "text/html; charset=utf-8" |> Str.toUtf8 } 