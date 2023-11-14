platform "webserver"
    requires {} { main : Request -> Task Response [] } # TODO change to U16 for status code
    exposes [
        Path,
        Arg,
        Dir,
        Env,
        File,
        FileMetadata,
        Http,
        Stderr,
        Stdin,
        Stdout,
        Task,
        Tcp,
        Url,
        Utc,
        Sleep,
        Command,
    ]
    packages {}
    imports [Task.{ Task }, Http.{ Request, Method, Response }]
    provides [mainForHost]

# NOTE use mainForHost : Request -> Task Response [Err] to generate glue
mainForHost : Request -> Task Response []
mainForHost = \req -> main req
