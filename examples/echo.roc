app "echo"
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

    # Log request datetime, method and url
    datetime <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await
    {} <- Stdout.line "$(datetime) $(Http.methodToStr req.method) $(req.url)" |> Task.await

    # Respond with request body
    if List.isEmpty req.body then
        Task.ok { status: 200, headers: [], body: [] }
    else
        Task.ok { status: 200, headers: [], body: req.body }

