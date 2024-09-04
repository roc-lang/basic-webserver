app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Jwt

Model : {}

server = { init, respond }

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->
    crash "todo"

## We hardcode the JWT here and ignore the request for simplicity, but normally this is how
## you would decode the request body (assuming the token is in the body and not a URL param)
## ```
## exampleBody : Result (Dict Str Str) _
## exampleBody = Http.parseFormUrlEncoded req.body
## ```
# exampleBody : Result (Dict Str Str) _
# exampleBody =
#    Dict.single "id_token" "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.joReqPNNkWQ8zQCW3UQnhc_5NMrSZEOQYpk6sDS6Y-o"
#    |> Ok

# token : Str
# token =
#    exampleBody
#    |> Result.try \decodedBody -> decodedBody |> Dict.get "id_token"
#    |> Result.withDefault "TOKEN MISSING"

# when Jwt.verify { secret: "shhh_very_secret", token } |> Task.result! is
#    Err (JwtErr err) ->
#        Task.ok {
#            status: 200,
#            headers: [
#                { name: "Content-Type", value: "text/plain" },
#            ],
#            body: Str.toUtf8 "UNABLE TO DECODE JWT\n$(Inspect.toStr err)\n",
#        }

#    Ok claims ->
#        { sub, name, iat } = getClaims claims |> Task.fromResult!

#        message = "Decoded JWT\nsubject: $(sub)\nname: $(name)\nissued at: $(iat)\n"

#        Stdout.line! message

#        Task.ok {
#            status: 200,
#            headers: [
#                { name: "Content-Type", value: "text/plain" },
#            ],
#            body: Str.toUtf8 message,
#        }

init : Task Model [ServerErr Str]_
init =
    #token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMiwiZXhwIjoxNjE2MjM5MDIyfQ.OgPG5wxM-U07VyOHf77ZKQvISflwjygcV1eC6-9T99sByIQe7czrTlJdV-zBsdeK4HeybHAWchRjem7d4LyZftArQQKI9J2dtno6FDCtOA1UslqaklEP7xpAMctgSZwxP678hdXO1-JUPWH29euUy-oDyb5p1YX3Qir3QXHhuPWogRHGnXlqtredOCtI_izZ_8DF6N3sU7KZPkJ70mOmEU7vYj6zfv53VYhcwSmzGq_UHghzI5OBXdaFUhBoLFbqiIPz8HNfr1LKNhA-ZcJkysilO5YXbxTZ23mH8tX9PnOYaJOCNxLsfMjZtCudHs6t_tBQJjVw9i5JpHjVT2znIg"

    #dbg token

    #validation = { Jwt.defaultValidation & algorithms: [RS256] }

    #dbg validation

    _ = Jwt.decodingKeyFromRsaPem
        """
        -----BEGIN PUBLIC KEY-----
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu1SU1LfVLPHCozMxH2Mo
        4lgOEePzNm0tRgeLezV6ffAt0gunVTLw7onLRnrq0/IzW7yWR7QkrmBL7jTKEn5u
        +qKhbwKfBstIs+bMY2Zkp18gnTxKLxoS2tFczGkPLPgizskuemMghRniWaoLcyeh
        kd3qqGElvW/VDL5AaWTg0nLVkjRo9z+40RQzuVaE8AkAFmxZzow3x+VJYKdjykkJ
        0iT9wCS0DRTXu269V264Vf/3jvredZiKRkgwlL9xNAwxXFg0x/XFw005UWVRIkdg
        cKWTjpBP2dPwVZ4WWC+9aGVd+Gyn1o0CLelf4rEjGoXbAAEgAqeGUxrcIlbjXfbc
        mwIDAQAB
        -----END PUBLIC KEY-----
        """
        |> Task.onErr! \{} -> crash "got an error"

    # decodedToken = Jwt.decode! { token, key, validation }
    # dbg decodedToken
    Task.err TODO

#    {
#        secret: "shhh_very_secret",
#        token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.joReqPNNkWQ8zQCW3UQnhc_5NMrSZEOQYpk6sDS6Y-o",
#    }
#        |> Jwt.verify
#        |> Task.await assertClaims
#        |> Task.mapErr! \err -> HS256TestErr err

#    {
#        secret: "shhh_very_secret",
#        token: "eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.i4IWr5r6Q597a6yCTJsvlkhHlt_AB1FP72Pd29hoelY32rfX0xT7KnVPf_UNaugJ",
#    }
#        |> Jwt.verify
#        |> Task.await assertClaims
#        |> Task.mapErr! \err -> HS384TestErr err

#    {
#        secret: examplePEM,
#        token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.Eci61G6w4zh_u9oOCk_v1M_sKcgk0svOmW4ZsL-rt4ojGUH2QY110bQTYNwbEVlowW7phCg7vluX_MCKVwJkxJT6tMk2Ij3Plad96Jf2G2mMsKbxkC-prvjvQkBFYWrYnKWClPBRCyIcG0dVfBvqZ8Mro3t5bX59IKwQ3WZ7AtGBYz5BSiBlrKkp6J1UmP_bFV3eEzIHEFgzRa3pbr4ol4TK6SnAoF88rLr2NhEz9vpdHglUMlOBQiqcZwqrI-Z4XDyDzvnrpujIToiepq9bCimPgVkP54VoZzy-mMSGbthYpLqsL_4MQXaI1Uf_wKFAUuAtzVn4-ebgsKOpvKNzVA",
#    }
#        |> Jwt.verify
#        |> Task.await assertClaims
#        |> Task.mapErr! \err -> RS512TestErr err

#    Stdout.line! "All tests passed"

#    Task.ok {}

# getClaims : Dict Str Str -> Result { sub : Str, name : Str, iat : Str } [MissingSubject, MissingName, MissingTimeIssued]
# getClaims = \claims ->

#    sub = claims |> Dict.get "sub" |> Result.mapErr? \KeyNotFound -> MissingSubject
#    name = claims |> Dict.get "name" |> Result.mapErr? \KeyNotFound -> MissingName
#    iat = claims |> Dict.get "iat" |> Result.mapErr? \KeyNotFound -> MissingTimeIssued

#    Ok { sub, name, iat }

# assertClaims : Dict Str Str -> Task {} _
# assertClaims = \claims ->
#    when (Dict.get claims "sub", Dict.get claims "name", Dict.get claims "iat") is
#        (Ok sub, Ok name, Ok iat) ->
#            if sub == "1234567890" && name == "John Doe" && iat == "1516239022" then
#                Task.ok {}
#            else
#                Task.err IncorrectClaims

#        _ -> Task.err MissingClaims
