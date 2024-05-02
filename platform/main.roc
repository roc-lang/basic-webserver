platform "webserver"
    requires {} { main : Request -> Task Response _ }
    exposes [
        Path,
        Dir,
        Env,
        File,
        FileMetadata,
        Http,
        Stderr,
        Stdout,
        Task,
        Tcp,
        Url,
        Utc,
        Sleep,
        Command,
        SQLite3,
    ]
    packages {}
    imports [
        Task.{ Task },
        Stderr.{ line },
        Http.{ Request, Method, Response },
    ]
    provides [mainForHost]

mainForHost : Request -> Task Response []
mainForHost = \req ->
    main req
    |> Task.onErr \err ->
        line! "Internal server error: `main` returned Task.err $(Inspect.toStr err)"
        Task.ok! {
            status: 500,
            headers: [],
            body: Str.toUtf8 "<h1>Internal Server Error</h1>\n",
        }
