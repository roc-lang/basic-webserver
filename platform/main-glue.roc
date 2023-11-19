platform "webserver"
    requires {} { main : Request -> ({} -> Response) }
    exposes [
        Path,
        Arg,
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
        Http.{ Request, Method, Response },
    ]
    provides [mainForHost]

mainForHost : Request -> ({} -> Response)
mainForHost = \req -> main req
