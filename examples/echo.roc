app "Log the request and echo the request back"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout.{ line },
        pf.Task.{ Task, map, ok, await },
        pf.Http.{ Request, Response, methodToStr },
        pf.Utc.{ now, toIso8601Str },
    ]
    provides [main] to pf

main = \req ->

    # Log request date, method and url
    date <- now |> map toIso8601Str |> await
    {} <- line "\(date) \(methodToStr req.method) \(req.url)" |> await

    # Respond with request body
    when req.body is
        EmptyBody -> ok { status: 200, headers: [], body: [] }
        Body internal -> ok { status: 200, headers: [], body: internal.body }

