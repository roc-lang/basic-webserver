app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Http exposing [Request, Response]
import pf.Cmd
import pf.Utc

Model : {}

init! : {} => Result Model _
init! = \{} -> Ok {}

respond! : Request, Model => Result Response [CmdStatusErr _]
respond! = \req, _ ->

    # Log request date, method and url using echo program
    datetime = Utc.to_iso_8601 (Utc.now! {})

    try Cmd.exec! "echo" ["$(datetime) $(Inspect.toStr req.method) $(req.uri)"]

    Ok {
        status: 200,
        headers: [],
        body: Str.toUtf8 "Command succeeded.",
    }
