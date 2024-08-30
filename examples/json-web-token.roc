app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Jwt

Model : {}

server = { init: Task.ok {}, respond }

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->

    Stdout.line! "Verify a Json Web Token (JWT)"

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

    when Jwt.verify { secret: "shhh_very_secret", algorithm: Hs256, token } |> Task.result! is
        Err (JwtErr err) ->
            Task.ok {
                status: 200,
                headers: [
                    { name: "Content-Type", value: "text/plain" },
                ],
                body: Str.toUtf8 "UNABLE TO DECODE JWT\n$(Inspect.toStr err)\n",
            }

        Ok claims ->
            sub = claims |> Dict.get "sub" |> Result.withDefault "SUBJECT CLAIM MISSING"
            name = claims |> Dict.get "name" |> Result.withDefault "NAME MISSING"
            iat = claims |> Dict.get "iat" |> Result.withDefault "TIME FIELD MISSING"

            message = "Decoded JWT\nsubject: $(sub)\nname: $(name)\nissued at: $(iat)\n"

            Stdout.line! message

            Task.ok {
                status: 200,
                headers: [
                    { name: "Content-Type", value: "text/plain" },
                ],
                body: Str.toUtf8 message,
            }
