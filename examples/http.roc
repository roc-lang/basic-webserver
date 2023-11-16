app "app"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Task.{ Task, attempt, ok },
        pf.Http.{ Request, Response, defaultRequest, send },
    ]
    provides [main] to pf

main = \_ ->

    # Send an HTTP request to fetch the Roc website
    result <-
        { defaultRequest & url: "https://www.roc-lang.org" }
        |> send
        |> attempt

    # Respond with the website content
    when result is
        Ok str -> respond 200 str
        Err _ -> respond 500 "Error 500 Internal Server Error\n"

respond = \code, body ->
    ok {
        status: code,
        headers: [
            { name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" },
        ],
        body: Str.toUtf8 body,
    }
