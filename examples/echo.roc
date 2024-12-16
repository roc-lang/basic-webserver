app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Utc

Model : {}

init! : {} => Result Model []
init! = \{} -> Ok {}

respond! : Request, Model => Result Response [StdoutErr _]
respond! = \req, _ ->
    # Log request datetime, method and url
    datetime = Utc.to_iso_8601 (Utc.now! {})

    Stdout.line!? "$(datetime) $(Inspect.toStr req.method) $(req.uri)"

    # Respond with request body
    if List.isEmpty req.body then
        success []
    else
        success req.body

success = \body -> Ok { status: 200, headers: [], body }
