platform "webserver"
    requires {} { main : Request -> Task Response [Err] } # TODO change to U16 for status code
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

mainForHost : Request -> Task Response [Err]
mainForHost = \req -> main req
