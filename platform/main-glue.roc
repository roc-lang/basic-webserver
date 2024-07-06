platform "webserver"
    requires {} { main : Request -> ({} -> Response) }
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
    ]
    packages {}
    imports [
        Http.{ Request, Response },
    ]
    provides [mainForHost]

mainForHost : Request -> ({} -> Response)
mainForHost = \req -> main req
