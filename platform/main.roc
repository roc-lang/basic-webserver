platform "webserver"
    # UNCOMMENT FOR GLUE GEN
    # requires {} { main : Request -> ({} -> Response) }
    requires {} { main : Request -> Task Response [] }
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
        Task.{ Task }, # COMMENT FOR GLUE GEN
        Http.{ Request, Method, Response },
    ]
    provides [mainForHost]

# UNCOMMENT FOR GLUE GEN
# mainForHost : Request -> ({} -> Response)
mainForHost : Request -> Task Response []
mainForHost = \req -> main req
