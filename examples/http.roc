app "Fetch Roc website and return content"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout.{ line },
        pf.Task.{ Task, map, attempt, ok, await },
        pf.Http.{ Request, Response, methodToStr, defaultRequest, send },
        pf.Utc.{ now, toIso8601Str },
    ]
    provides [main] to pf

main = \req ->

    # Log the date, time, method, and url to stdout
    dateTime <- now |> map toIso8601Str |> await
    {} <- line "\(dateTime) \(methodToStr req.method) \(req.url)" |> await

    # Fetch the Roc website
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
