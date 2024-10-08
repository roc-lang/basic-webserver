app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Sleep

Model : {}

server = { init: Task.ok {}, respond }

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->
    # Let the user know we're sleeping
    Stdout.line! "Sleeping for 1 second..."

    # Sleep for 1 second
    Sleep.millis! 1000

    # Delayed Http response
    body = Str.toUtf8 "Response delayed by 1 second"
    headers = []
    status = 200

    Task.ok { status, headers, body }
