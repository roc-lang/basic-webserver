module [
    Request,
    Method,
    Header,
    TimeoutConfig,
    Response,
    Err,
    header,
    handleStringResponse,
    defaultRequest,
    errorToString,
    errorBodyToBytes,
    send,
    get,
    getUtf8,
    methodToStr,
]

import Effect
import InternalTask
import Task exposing [Task]
import InternalHttp exposing [errorBodyToUtf8, errorBodyFromUtf8]

## Represents an HTTP request.
Request : InternalHttp.Request

## Represents an HTTP method.
Method : InternalHttp.Method

## Represents an HTTP header e.g. `Content-Type: application/json`
Header : InternalHttp.Header

## Represents a timeout configuration for an HTTP request.
TimeoutConfig : InternalHttp.TimeoutConfig

## Represents an HTTP response.
Response : InternalHttp.Response

## Represents an HTTP error.
Err : InternalHttp.Error

## Convert the ErrorBody of a BadStatus error to List U8.
errorBodyToBytes = errorBodyFromUtf8

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
    mimeType: "",
    body: [],
    timeout: NoTimeout,
}

## An HTTP header for configuring requests.
##
## See common headers [here](https://en.wikipedia.org/wiki/List_of_HTTP_header_fields).
##
header : Str, Str -> Header
header = \name, value ->
    { name, value }

## Map a [Response] body to a [Str] or return an [Err].
handleStringResponse : Response -> Result Str Err
handleStringResponse = \response ->
    response.body
    |> Str.fromUtf8
    |> Result.mapErr \BadUtf8 _ pos ->
        position = Num.toStr pos

        BadBody "Invalid UTF-8 at byte offset $(position)"

## Convert an [Err] to a [Str].
errorToString : Err -> Str
errorToString = \err ->
    when err is
        BadRequest e -> "Invalid Request: $(e)"
        Timeout ms -> "Request timed out after $(Num.toStr ms) ms."
        NetworkError -> "Network error."
        BadStatus { code, body } ->
            when body |> errorBodyToUtf8 |> Str.fromUtf8 is
                Ok bodyStr -> "Request failed with status $(Num.toStr code): $(bodyStr)"
                Err _ -> "Request failed with status $(Num.toStr code)."

        BadBody details -> "Request failed: Invalid body: $(details)"

## Task to send an HTTP request, succeeds with a value of [Str] or fails with an
## [Err].
##
## ```
## # Prints out the HTML of the Roc-lang website.
## response <-
##     { Http.defaultRequest & url: "https://www.roc-lang.org" }
##     |> Http.send
##     |> Task.await
##
## response.body
## |> Str.fromUtf8
## |> Result.withDefault "Invalid UTF-8"
## |> Stdout.line
## ```
send : Request -> Task Response [HttpErr Err]
send = \req ->

    timeoutMs =
        when req.timeout is
            NoTimeout -> 0
            TimeoutMilliseconds ms -> ms

    method = methodToStr req.method

    reqToHost : InternalHttp.RequestToAndFromHost
    reqToHost = {
        method,
        headers: req.headers,
        url: req.url,
        mimeType: req.mimeType,
        body: req.body,
        timeoutMs,
    }

    # TODO: Fix our C ABI codegen so that we don't need this Box.box heap allocation
    Effect.sendRequest (Box.box reqToHost)
    |> Effect.map Ok
    |> InternalTask.fromEffect
    |> Task.await \{ variant, body, metadata } ->
        when variant is
            "Timeout" -> Task.err (Timeout timeoutMs)
            "NetworkErr" -> Task.err NetworkError
            "BadStatus" ->
                Task.err
                    (
                        BadStatus {
                            code: metadata.statusCode,
                            body: errorBodyFromUtf8 body,
                        }
                    )

            "GoodStatus" ->
                Task.ok {
                    status: metadata.statusCode,
                    headers: metadata.headers,
                    body,
                }

            "BadRequest" | _other -> Task.err (BadRequest metadata.statusText)
    |> Task.mapErr HttpErr

## Try to perform an HTTP get request and convert (decode) the received bytes into a Roc type.
## Very useful for working with Json.
##
## ```
## import json.Json
##
## # On the server side we send `Encode.toBytes {foo: "Hello Json!"} Json.utf8`
## { foo } = Http.get! "http://localhost:8000" Json.utf8
## ```
get : Str, fmt -> Task body [HttpErr Http.Err, HttpDecodingFailed] where body implements Decoding, fmt implements DecoderFormatting
get = \url, fmt ->
    response = send! { defaultRequest & url }

    Decode.fromBytes response.body fmt
    |> Result.mapErr \_ -> HttpDecodingFailed
    |> Task.fromResult

getUtf8 : Str -> Task Str [HttpErr Http.Err]
getUtf8 = \url ->
    response = send! { defaultRequest & url }

    response.body
    |> Str.fromUtf8
    |> Result.mapErr \_ -> HttpErr (BadBody "Invalid UTF-8")
    |> Task.fromResult

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
