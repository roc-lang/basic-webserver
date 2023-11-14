app "Read Todos from SQLite3 db and send Json response"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Task.{ Task }, 
        pf.Http.{ Request, Response }, 
        pf.Command,
        pf.Env,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \req ->

    method = Http.methodToStr req.method

    {} <- 
        Stdout.line "\(method) \(req.url)" 
        |> Task.await

    dbPath <- 
        Env.var "DB_PATH"
        |> Task.onErr \_ -> crash "Unable to read DB_PATH; usage DB_PATH=examples/todos.db roc run examples/todos.roc"
        # TODO figure out why this doesn't work
        # |> Task.onErr \_ -> Task.ok { status: 500, headers: [], body: "Unable to read DB_PATH" |> Str.toUtf8 }
        |> Task.await

    Command.new "sqlite3"
    |> Command.arg dbPath
    |> Command.arg ".mode json"
    |> Command.arg "SELECT task, status FROM todos;"
    |> Command.output
    |> Task.map \output -> { status: 200, headers: [], body: output.stdout }
    |> Task.onErr \(output, _) -> Task.ok { status: 500, headers: [], body: output.stderr }