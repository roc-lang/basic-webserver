module [
    Request,
    RequestToAndFromHost,
    ResponseToAndFromHost,
    Method,
    Header,
    TimeoutConfig,
    Error,
    ErrorBody,
    fromHostRequest,
    errorBodyToUtf8,
    errorBodyFromUtf8,
    methodToStr,
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
    method : [Options, Get, Post, Put, Delete, Head, Trace, Connect, Patch, Extension],
    methodExt : Str,
    headers : List Header,
    url : Str,
    mimeType : Str,
    body : List U8,
    timeoutMilliseconds : U64,
}

fromHostRequest : RequestToAndFromHost -> Request
fromHostRequest = \{ method, methodExt, headers, url, mimeType, body, timeoutMilliseconds } -> {
    method: toMethod method methodExt,
    headers,
    url,
    mimeType,
    body,
    timeout: if timeoutMilliseconds == 0 then NoTimeout else TimeoutMilliseconds timeoutMilliseconds,
}

# Name is distinguished from the Timeout tag used in Response and Error
TimeoutConfig : [TimeoutMilliseconds U64, NoTimeout]

Method : [Options, Get, Post, Put, Delete, Head, Trace, Connect, Patch, Extension Str]

toMethod : [Options, Get, Post, Put, Delete, Head, Trace, Connect, Patch, Extension], Str -> Method
toMethod = \tag, ext ->
    when tag is
        Options -> Options
        Get -> Get
        Post -> Post
        Put -> Put
        Delete -> Delete
        Head -> Head
        Trace -> Trace
        Connect -> Connect
        Patch -> Patch
        Extension -> Extension ext

Header : {
    name : Str,
    value : Str,
}

ResponseToAndFromHost : {
    status : U16,
    headers : List Header,
    body : List U8,
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

methodToStr : Method -> Str
methodToStr = \method ->
    when method is
        Options -> "Options"
        Get -> "Get"
        Post -> "Post"
        Put -> "Put"
        Delete -> "Delete"
        Head -> "Head"
        Trace -> "Trace"
        Connect -> "Connect"
        Patch -> "Patch"
        Extension ext -> ext
