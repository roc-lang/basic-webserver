interface InternalHttp
    exposes [
        InternalRequest, 
        InternalMethod, 
        InternalHeader, 
        InternalTimeoutConfig, 
        InternalPart, 
        InternalBody, 
        InternalResponse, 
        InternalMetadata, 
        InternalError,
    ]
    imports []

InternalRequest : {
    method : InternalMethod,
    headers : List InternalHeader,
    url : Str,
    body : InternalBody,
    timeout : InternalTimeoutConfig,
}

InternalMethod : [Options, Get, Post, Put, Delete, Head, Trace, Connect, Patch]

InternalHeader : { name : Str, value: List U8 }

# Name is distinguished from the Timeout tag used in InternalResponse and InternalError
InternalTimeoutConfig : [TimeoutMilliseconds U64, NoTimeout]

InternalPart : [Part Str (List U8)]

InternalBody : [
    Body InternalBodyBody,
    EmptyBody,
]

InternalBodyBody : { mimeType: Str, body: List U8} # separate definition to help out glue gen

InternalResponse : { status : U16, headers : List InternalHeader, body: List U8 }

InternalMetadata : {
    url : Str,
    statusCode : U16,
    statusText : Str,
    headers : List InternalHeader,
}

InternalError : [
    BadRequest Str,
    Timeout,
    NetworkError,
    BadStatus U16,
    BadBody Str,
]
