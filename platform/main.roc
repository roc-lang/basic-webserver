platform "webserver"
    requires {} { main : Request -> Task Response [] }
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
        Http.{ Request, Response },
    ]
    provides [mainForHost]

mainForHost : Request -> Task Response []
mainForHost = \req -> main req
