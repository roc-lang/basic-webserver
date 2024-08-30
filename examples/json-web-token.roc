app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Jwt




# Model is produced by `init`.
Model : {}

# With `init` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`,...
# In this case we don't have anything to initialize, so it is just `Task.ok {}`.

server = { init: Task.ok {}, respond }

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->

    # We hardcode the JWT here and ignore the request for simplicity, but normally this is how
    # you would decode the request body (assuming the token is in the body and not a URL param)
    # ```
    # exampleBody = Http.parseFormUrlEncoded req.body
    # ```
    exampleBody : Result (Dict Str Str) _
    exampleBody =
        Dict.empty {}
        |> Dict.insert "id_token" "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.joReqPNNkWQ8zQCW3UQnhc_5NMrSZEOQYpk6sDS6Y-o"
        |> Ok

    token : Str
    token =
        exampleBody
        |> Result.try \decodedBody -> decodedBody |> Dict.get "id_token"
        |> Result.withDefault "TOKEN MISSING"

    result = Jwt.verify { secret: "shhh_very_secret", algorithm: Hs256, token }

    Stdout.line! "Decoded JWT: $(Inspect.toStr result)"

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "<b>$(Inspect.toStr result)</br>" }
