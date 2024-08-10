app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Utc

Model : Str

server = { init, respond }

init : Task Model [Exit I32 Str]_
init =
    Stdout.line! "SERVER INFO: Doing stuff before the server starts..."
    Task.ok "This is from init!"

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, model ->
    # Log request datetime, method and url
    datetime = Utc.now! |> Utc.toIso8601Str

    Stdout.line! "$(datetime) $(Http.methodToStr req.method) $(req.url)"

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "<b>Hello, world!</b></br>$(model)" }
