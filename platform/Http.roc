interface Http
    exposes [
        Request,
        Method,
        methodToStr,
        Header,
        TimeoutConfig,
        Response,
        Metadata,
        Error,
        header,
        handleStringResponse,
        defaultRequest,
        errorToString,
        send,
        getUtf8,
    ]
    imports [Effect, InternalTask, Task.{ Task }, InternalHttp]

## Represents an HTTP request.
Request : InternalHttp.InternalRequest

## Represents an HTTP method.
Method : InternalHttp.InternalMethod

## Represents an HTTP header e.g. `Content-Type: application/json`
Header : InternalHttp.InternalHeader

## Represents a timeout configuration for an HTTP request.
TimeoutConfig : InternalHttp.InternalTimeoutConfig

## Represents an HTTP response.
Response : InternalHttp.InternalResponse

## Represents HTTP metadata, such as the URL or status code.
Metadata : InternalHttp.InternalMetadata

## Represents an HTTP error.
Error : InternalHttp.InternalError

## A default [Request] value.
##
## ```
## # GET "roc-lang.org"
## { Http.defaultRequest &
##     url: "https://www.roc-lang.org",
## }
## ```
##
defaultRequest : Request
defaultRequest = {
    method: Get,
    headers: [],
    url: "",
    mimeType: "text/plain",
    body: [],
    timeout: NoTimeout,
}

## An HTTP header for configuring requests.
##
## See common headers [here](https://en.wikipedia.org/wiki/List_of_HTTP_header_fields).
##
header : Str, Str -> Header
header = \name, value -> { name, value: Str.toUtf8 value }

## Map a [Response] body to a [Str] or return an [Error].
handleStringResponse : Response -> Result Str Error
handleStringResponse = \response ->
    response.body
    |> Str.fromUtf8
    |> Result.mapErr \_ -> BadBody "" # TODO FIX THIS FUNCTION

# when response is
#     BadRequest err -> Err (BadRequest err)
#     Timeout -> Err Timeout
#     NetworkError -> Err NetworkError
#     BadStatus metadata _ -> Err (BadStatus metadata.statusCode)
#     GoodStatus _ bodyBytes ->
#         Str.fromUtf8 bodyBytes
#         |> Result.mapErr
#             \BadUtf8 _ pos ->
#                 position = Num.toStr pos

#                 BadBody "Invalid UTF-8 at byte offset $(position)"

## Convert an [Error] to a [Str].
errorToString : Error -> Str
errorToString = \err ->
    when err is
        BadRequest e -> "Invalid Request: $(e)"
        Timeout -> "Request timed out"
        NetworkError -> "Network error"
        BadStatus code -> Str.concat "Request failed with status " (Num.toStr code)
        BadBody details -> Str.concat "Request failed. Invalid body. " details

## Task to send an HTTP request, succeeds with a value of [Str] or fails with an
## [Error].
##
## ```
## # Prints out the HTML of the Roc-lang website.
## result <-
##     { Http.defaultRequest &
##         url: "https://www.roc-lang.org",
##     }
##     |> Http.send
##     |> Task.attempt
##
## when result is
##     Ok responseBody -> Stdout.line responseBody
##     Err _ -> Stdout.line "Oops, something went wrong!"
## ```
send : Request -> Task Str Error
send = \req ->
    # TODO: Fix our C ABI codegen so that we don't this Box.box heap allocation
    Effect.sendRequest (Box.box req)
    |> Effect.map handleStringResponse
    |> InternalTask.fromEffect

getUtf8 : Str -> Task Str Error
getUtf8 = \url ->
    send { defaultRequest & url }

methodToStr : Method -> Str
methodToStr = \method ->
    when method is
        Get -> "GET"
        Post -> "POST"
        Put -> "PUT"
        Patch -> "PATCH"
        Delete -> "DELETE"
        Head -> "HEAD"
        Options -> "OPTIONS"
        Connect -> "CONNECT"
        Trace -> "TRACE"
