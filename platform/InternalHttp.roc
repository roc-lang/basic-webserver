module [
    Request,
    RequestToAndFromHost,
    fromHostRequest,
    Response,
    ResponseToHost,
    ResponseFromHost,
    Method,
    Header,
    TimeoutConfig,
    Error,
    ErrorBody,
    errorBodyToUtf8,
    errorBodyFromUtf8,
]

Request : {
    method : Method,
    headers : List Header,
    url : Str,
    mimeType : Str,
    body : List U8,
    timeout : TimeoutConfig,
}

RequestToAndFromHost : {
    method : Str,
    headers : List Header,
    url : Str,
    mimeType : Str,
    body : List U8,
    timeoutMilliseconds : U64,
}

fromHostRequest : RequestToAndFromHost -> Request
fromHostRequest = \{ method, headers, url, mimeType, body, timeoutMilliseconds } -> {
    method: methodFromStr method,
    headers,
    url,
    mimeType,
    body,
    timeout: if timeoutMilliseconds == 0 then NoTimeout else TimeoutMilliseconds timeoutMilliseconds,
}

# Name is distinguished from the Timeout tag used in Response and Error
TimeoutConfig : [TimeoutMilliseconds U64, NoTimeout]

Method : [Options, Get, Post, Put, Delete, Head, Trace, Connect, Patch]

methodFromStr : Str -> Method
methodFromStr = \str ->
    when str is
        "Options" -> Options
        "Get" -> Get
        "Post" -> Post
        "Put" -> Put
        "Delete" -> Delete
        "Head" -> Head
        "Trace" -> Trace
        "Connect" -> Connect
        "Patch" -> Patch
        _ -> crash "unrecognized method from host"

Header : {
    name : Str,
    value : Str,
}

Response : ResponseToHost

ResponseToHost : {
    status : U16,
    headers : List Header,
    body : List U8,
}

ResponseFromHost : {
    variant : Str,
    metadata : Metadata,
    body : List U8,
}

Metadata : {
    url : Str,
    statusCode : U16,
    statusText : Str,
    headers : List Header,
}

Error : [
    BadRequest Str,
    Timeout U64,
    NetworkError,
    BadStatus { code : U16, body : ErrorBody },
    BadBody Str,
]

ErrorBody := List U8 implements [
        Inspect {
            toInspector: errorBodyToInspector,
        },
    ]

errorBodyToInspector : ErrorBody -> _
errorBodyToInspector = \@ErrorBody val ->
    Inspect.custom \fmt ->
        when val |> List.takeFirst 50 |> Str.fromUtf8 is
            Ok str -> Inspect.apply (Inspect.str str) fmt
            Err _ -> Inspect.apply (Inspect.str "Invalid UTF-8 data") fmt

errorBodyToUtf8 : ErrorBody -> List U8
errorBodyToUtf8 = \@ErrorBody body -> body

errorBodyFromUtf8 : List U8 -> ErrorBody
errorBodyFromUtf8 = \body -> @ErrorBody body
