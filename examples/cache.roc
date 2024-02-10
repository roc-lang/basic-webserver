app "cache"
    packages { pf: "../platform/main.roc" }
    imports [
        # pf.Stdout,
        pf.Cache,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->

    key = 123
    value = "The value is 123" |> Str.toUtf8

    # Store value in cache
    {} <- Cache.set key value |> Task.await

    # Retrieve value from cache
    result <- Cache.get key |> Task.attempt

    when result is 
        Ok bytes if bytes == value -> Task.ok { status: 200, headers: [], body: value }
        _ -> Task.ok { status: 500, headers: [], body: Str.toUtf8 "Unable to retrieve value from cache"}
