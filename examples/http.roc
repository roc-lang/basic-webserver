app "app"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->

    result <-
        { Http.defaultRequest & url: "https://www.roc-lang.org" }
        |> Http.send
        |> Task.attempt

    when result is
        Ok bytes ->
            Task.ok { status: 200, headers: [], body: Str.toUtf8 bytes }

        Err _ -> serverError

serverError : Task Response []
serverError = Task.ok { status: 500, headers: [], body: Str.toUtf8 "Error 500 Internal Server Error\n" }
