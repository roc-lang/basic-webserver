app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Utc

main : Request -> Task Response []
main = \req ->

    # Log request datetime, method and url
    datetime <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await
    {} <- Stdout.line "$(datetime) $(Http.methodToStr req.method) $(req.url)" |> Task.await

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "<b>Hello, world!</b>\n" }
