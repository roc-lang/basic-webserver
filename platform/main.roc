platform "webserver"
    requires {} { main : Request -> Task Response [] } # TODO change to U16 for status code
    exposes [
        Path,
        Header,
        Request,
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
    imports [Task.{ Task }, Request.{ Request, Method }, Response.{ Response }]
    provides [mainForHost]

mainForHost : Request -> Task Response []
mainForHost = \req -> main req
