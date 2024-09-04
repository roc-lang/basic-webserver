module [
    DecodingKey,
    decodingKeyFromSecret,
    decodingKeyFromRsaPem,
]

import PlatformTasks

DecodingKey := [
    Simple PlatformTasks.JwtDecodingKey Str,
]
    implements [
        Inspect { toInspector: decodingKeyInspector },
    ]

# Redact the secret from the inspect output to prevent leaking it in logs
decodingKeyInspector : DecodingKey -> Inspector f where f implements InspectFormatter
decodingKeyInspector = \@DecodingKey _ -> Inspect.str "****JWT SECRET REDACTED****"

# TODO use an error union https://docs.rs/jsonwebtoken/latest/jsonwebtoken/errors/enum.ErrorKind.html

## Create a decoding key from a secret string
decodingKeyFromSecret : Str -> Task DecodingKey [JwtErr Str]
decodingKeyFromSecret = \secret ->
    PlatformTasks.jwtDecodingKeyFromSimpleSecret secret
    |> Task.map \key -> @DecodingKey (Simple key secret)
    |> Task.mapErr \err -> JwtErr err

## Create a decoding key from a RSA private key in PEM format
decodingKeyFromRsaPem : Str -> Task DecodingKey [JwtErr Str]
decodingKeyFromRsaPem = \secret ->
    PlatformTasks.jwtDecodingKeyFromRsaPem secret
    |> Task.map \key -> @DecodingKey (Simple key secret)
    |> Task.mapErr \err -> JwtErr err
