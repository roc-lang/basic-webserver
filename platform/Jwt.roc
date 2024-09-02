module [
    Err,
    Algorithm,
    verify,
]

import PlatformTasks

Err : PlatformTasks.JwtErr

Algorithm : [
    HS256,
    HS384,
    HS512,
    RS256,
    RS384,
    RS512,
    # TODO add support for other algorithms
    # See https://docs.rs/jwt/0.16.0/jwt/index.html for more information
    # Note: at this time, by default only the `hmac` crate’s Hmac type is supported.
    # Es256,
    # Es384,
    # Es512,
    # Ps256,
    # Ps384,
    # Ps512,
    # Unsecured,
]

verify :
    {
        secret : Str,
        token : Str,
    }
    -> Task (Dict Str Str) [JwtErr Err]_
verify = \args ->
    PlatformTasks.jwtVerify args
    |> Task.mapErr \err -> JwtErr err
    |> Task.map \claims ->
        claims
        |> List.map \{ name, value } -> (name, value)
        |> Dict.fromList
