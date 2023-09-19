platform "webserver"
    requires {} { main : Request -> Task Str [] } # TODO change to U16 for status code
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
    imports [Task.{ Task }, Request.{ Request }]
    provides [mainForHost]

mainForHost : Request -> Task Str []
mainForHost = \req -> main req
# TODO add a hosted effect for getRequest which gets a threadlocal for the current request.
# TODO add a hosted effect for setResponse which sets a threadlocal for the response. Don't expose it in userspace,
# just call it here after everything else is done, so we have the respsone set before we return.
