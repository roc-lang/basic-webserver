app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Utc

main : Request -> Task Response []
main = \req ->

    # Log request datetime, method and url
    datetime = Utc.now! |> Utc.toIso8601Str
    Stdout.line! "$(datetime) $(Http.methodToStr req.method) $(req.url)"

    # Respond with request body
    if List.isEmpty req.body then
        Task.ok { status: 200, headers: [], body: [] }
    else
        Task.ok { status: 200, headers: [], body: req.body }
