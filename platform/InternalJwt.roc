module [
    Token,
    DecodingKey,
    Header,
    Claim,
    Validation,
    defaultValidation,
    Err,
]

# [jsonwebtoken::TokenData](https://docs.rs/jsonwebtoken/latest/jsonwebtoken/struct.TokenData.html)
Token : {
    header : Header,
    claims : List Claim,
}

# [jsonwebtoken::Algorithm](https://docs.rs/jsonwebtoken/latest/jsonwebtoken/enum.Algorithm.html)
Algorithm : [
    HS256,
    HS384,
    HS512,
    ES256,
    ES384,
    RS256,
    RS384,
    RS512,
    PS256,
    PS384,
    PS512,
    EdDSA,
]

# A boxed [jsonwebtoken::DecodingKey](https://docs.rs/jsonwebtoken/latest/jsonwebtoken/struct.DecodingKey.html)
# stored in a threadsafe refcounted heap
DecodingKey := Box {}

# [jsonwebtoken::Header](https://docs.rs/jsonwebtoken/latest/jsonwebtoken/struct.Header.html)
Header : {
    typ : Str,
    alg : Str,
    cty : Str,
    jku : Str,
    jwk : Str,
    kid : Str,
    x5u : Str,
    x5c : Str,
    x5t : Str,
    x5tS256 : Str,
}

# simplified for generating glue across host boundary
# using a Dict Str Str would be preferable but not yet supported
Claim : { key : Str, value : Str }

## Validation options for the JWT
## refer to [docs.rs/jsonwebtoken](https://docs.rs/jsonwebtoken/latest/jsonwebtoken/struct.Validation.html) for more detailed information
Validation : {
    requiredClaims : List Str,
    leeway : U64,
    rejectExiringLessThan : U64,
    validateExp : Bool,
    validateNbf : Bool,
    validateAud : Bool,
    audience : Str,
    issuer : Str,
    subject : Str,
    # TODO support more algorithms
    algorithms : List Algorithm,
}

defaultValidation : Validation
defaultValidation = {
    requiredClaims: ["exp"],
    leeway: 60,
    rejectExiringLessThan: 0,
    validateExp: Bool.true,
    validateNbf: Bool.false,
    validateAud: Bool.true,
    audience: "",
    issuer: "",
    subject: "",
    algorithms: [HS256],
}

# [jsonwebtoken::errors::ErrorKind](https://docs.rs/jsonwebtoken/latest/jsonwebtoken/errors/enum.ErrorKind.html)
Err : [
    InvalidToken Str,
    InvalidSignature Str,
    InvalidKey Str,
    InvalidAlgorithm Str,
    MissingClaim Str,
    InvalidClaim Str,
    Other Str
]
