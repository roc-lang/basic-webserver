app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Utc

# Model is produced by `init`.
Model : Str

server = { init, respond }

# With `init` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`,...
# In this example it is just `Task.ok "🎁"`.

init : Task Model [Exit I32 Str]_
init = Task.ok "🎁"

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, model ->
    # Log request datetime, method and url
    datetime = Utc.now! |> Utc.toIso8601Str

    Stdout.line! "$(datetime) $(Http.methodToStr req.method) $(req.url)"

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "<b>init gave me $(model)</b>" }
