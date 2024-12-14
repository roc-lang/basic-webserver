app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Utc

# Model is produced by `init`.
Model : {}

# With `init` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`,...
# In this case we don't have anything to initialize, so it is just `Task.ok {}`.

init! : {} => Result Model []
init! = \{} -> Ok {}

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = \req, _ ->
    # Log request datetime, method and url
    datetime = Utc.now! {} |> Utc.toIso8601Str

    try Stdout.line! "$(datetime) $(Http.methodToStr req.method) $(req.url)"

    Ok {
        status: 200,
        headers: [],
        body: Str.toUtf8 "<b>Hello from server</b></br>",
        xxx: 0,
        yyy: 0,
        zzz: 0,
    }
