module [
    Err,
    Algorithm,
    verify,
]

import PlatformTasks

Err : [
    AlgorithmMismatch Str,
    InvalidSignature Str,
    BadFormat Str,
    BadJson Str,
    MissingClaims,
    MissingHeader,
    MissingKeyId,
    MissingSignature,
    Other Str,
]

Algorithm : [
    Hs256,
    Hs384,
    Hs512,
    Rs256,
    Rs384,
    Rs512,
    Es256,
    Es384,
    Es512,
    Ps256,
    Ps384,
    Ps512,
    Unsecured,
]

algoToU8 : Algorithm -> U8
algoToU8 = \algo ->
    when algo is
        Hs256 -> 1
        Hs384 -> 2
        Hs512 -> 3
        Rs256 -> 4
        Rs384 -> 5
        Rs512 -> 6
        Es256 -> 7
        Es384 -> 8
        Es512 -> 9
        Ps256 -> 10
        Ps384 -> 11
        Ps512 -> 12
        Unsecured -> 13

verify : {
    algorithm : Algorithm,
    secret : Str,
    token : Str,
} -> Task (Dict Str Str) [JwtErr Err]_
verify = \{algorithm, secret, token} ->
    PlatformTasks.jwtVerify {algo: algoToU8 algorithm, secret, token}
    |> Task.mapErr mapErrorFromHost
    |> Task.mapErr JwtErr
    |> Task.map \claims ->
        claims
        |> List.map \{name, value} -> (name, value)
        |> Dict.fromList

# we can return a Str from the host, and prepend
# it with a magic number for each variant
mapErrorFromHost : Str -> Err
mapErrorFromHost = \_ -> Other "TODO"
