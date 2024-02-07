interface Http
    exposes [
        Request,
        Method,
        methodToStr,
        Header,
        TimeoutConfig,
        Body,
        Response,
        Metadata,
        Error,
        header,
        emptyBody,
        bytesBody,
        stringBody,
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

## Represents an HTTP request body.
Body : InternalHttp.InternalBody

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
    body: Http.emptyBody,
    timeout: NoTimeout,
}

## An HTTP header for configuring requests.
##
## See common headers [here](https://en.wikipedia.org/wiki/List_of_HTTP_header_fields).
##
header : Str, Str -> Header
header = \name, value -> { name, value: Str.toUtf8 value }

## An empty HTTP request [Body].
emptyBody : Body
emptyBody =
    EmptyBody

## A request [Body] with raw bytes.
##
## ```
## # A application/json body of "{}".
## Http.bytesBody
##     (MimeType "application/json")
##     [123, 125]
## ```
bytesBody : Str, List U8 -> Body
bytesBody = \mimeType, body -> Body { mimeType, body }

## A request [Body] with a string.
##
## ```
## Http.stringBody
##     (MimeType "application/json")
##     "{\"name\": \"Louis\",\"age\": 22}"
## ```
stringBody : Str, Str -> Body
stringBody = \mimeType, str -> Body { mimeType, body: Str.toUtf8 str }

# jsonBody : a -> Body where a implements Encoding
# jsonBody = \val ->
#     Body (MimeType "application/json") (Encode.toBytes val Json.format)
#
# multiPartBody : List Part -> Body
# multiPartBody = \parts ->
#     boundary = "7MA4YWxkTrZu0gW" # TODO: what's this exactly? a hash of all the part bodies?
#     beforeName = Str.toUtf8 "-- \(boundary)\r\nContent-Disposition: form-data; name=\""
#     afterName = Str.toUtf8 "\"\r\n"
#     appendPart = \buffer, Part name partBytes ->
#         buffer
#         |> List.concat beforeName
#         |> List.concat (Str.toUtf8 name)
#         |> List.concat afterName
#         |> List.concat partBytes
#     bodyBytes = List.walk parts [] appendPart
#     Body (MimeType "multipart/form-data;boundary=\"\(boundary)\"") bodyBytes
# bytesPart : Str, List U8 -> Part
# bytesPart =
#     Part
# stringPart : Str, Str -> Part
# stringPart = \name, str ->
#     Part name (Str.toUtf8 str)

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

#                 BadBody "Invalid UTF-8 at byte offset \(position)"

## Convert an [Error] to a [Str].
errorToString : Error -> Str
errorToString = \err ->
    when err is
        BadRequest e -> "Invalid Request: \(e)"
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
