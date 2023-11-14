app "app"
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

    millis <- Utc.now |> Task.map Utc.toMillisSinceEpoch |> Task.map Num.toStr |> Task.await

    method = Http.methodToStr req.method

    logLine = "\(millis) \(method) \(req.url)"

    {} <- Stdout.line logLine |> Task.await

    Task.ok { status: 200, headers: [], body: Str.toUtf8 logLine }
