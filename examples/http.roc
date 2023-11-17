app "http"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.Utc,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \req ->

    # Log the date, time, method, and url to stdout
    dateTime <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await
    {} <- Stdout.line "\(dateTime) \(Http.methodToStr req.method) \(req.url)" |> Task.await

    # Fetch the Roc website
    result <-
        { Http.defaultRequest & url: "https://www.roc-lang.org" }
        |> Http.send
        |> Task.attempt

    # Respond with the website content
    when result is
        Ok str -> respond 200 str
        Err _ -> respond 500 "Error 500 Internal Server Error\n"

respond : U16, Str -> Task Response []
respond = \code, body ->
    Task.ok {
        status: code,
        headers: [
            { name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" },
        ],
        body: Str.toUtf8 body,
    }
