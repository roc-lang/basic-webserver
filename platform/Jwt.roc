module [
    Err,
    Token,
    decode,

    Header,
    Claim,
    Validation,
    defaultValidation,

    DecodingKey,
    decodingKeyFromSecret,
    decodingKeyFromRsaPem,
]

import PlatformTasks
import InternalJwt

Err : InternalJwt.Err
Token : InternalJwt.Token
Header : InternalJwt.Header
Claim : InternalJwt.Claim

## Validation options for the JWT
## refer to [docs.rs/jsonwebtoken](https://docs.rs/jsonwebtoken/latest/jsonwebtoken/struct.Validation.html) for more detailed information
Validation : InternalJwt.Validation

## Default values for validation options
##
## Example:
## ```
## validation = { Jwt.defaultValidation & audience: "https://roc-lang.org" }
## ```
defaultValidation : Validation
defaultValidation = InternalJwt.defaultValidation

## A secret key used to decode a JWT.
##
## This should be created once and reused multiple times to improve performance.
DecodingKey := [
    Simple (Box {}) Str,
    RsaPem (Box {}) Str,
]
    implements [
        Inspect { toInspector: decodingKeyInspector },
    ]

# Redact the secret from the inspect output to prevent leaking it in logs
decodingKeyInspector : DecodingKey -> Inspector f where f implements InspectFormatter
decodingKeyInspector = \@DecodingKey _ -> Inspect.str "****JWT SECRET REDACTED****"

# We wrapped the key in an opaque type, but we need to provide the
# pointer to the underlying decoding key for the host to use.
unwrapDecodingKey : DecodingKey -> Box {}
unwrapDecodingKey = \@DecodingKey key ->
    when key is
        Simple k _ -> k
        RsaPem k _ -> k

## Create a decoding key from a secret string
decodingKeyFromSecret : Str -> Task DecodingKey Err
decodingKeyFromSecret = \secret ->
    PlatformTasks.jwtDecodingKeyFromSimpleSecret secret
    |> Task.map \key -> @DecodingKey (Simple key secret)

## Create a decoding key from a RSA private key in PEM format
decodingKeyFromRsaPem : Str -> Task DecodingKey {}
decodingKeyFromRsaPem = \secret ->
    PlatformTasks.jwtDecodingKeyFromRsaPem secret
    |> Task.map \key -> @DecodingKey (RsaPem key secret)

## Decode and validate JWT token
decode :
    {
        token : Str,
        key : DecodingKey,
        validation : Validation,
    }
    -> Task Token Err
decode = \{ token, key, validation } ->
    PlatformTasks.jwtDecode token (unwrapDecodingKey key) validation
