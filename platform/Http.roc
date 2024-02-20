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
        parseFormUrlEncoded,
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

## Parse URL-encoded form values (`todo=foo&status=bar`) into a Dict (`("todo", "foo"), ("status", "bar")`).
##
## ```
## expect
##     bytes = Str.toUtf8 "todo=foo&status=bar"
##     parsed = parseFormUrlEncoded bytes |> Result.withDefault (Dict.empty {})
##
##     Dict.toList parsed == [("todo", "foo"), ("status", "bar")]
## ```
parseFormUrlEncoded : List U8 -> Result (Dict Str Str) [BadUtf8]
parseFormUrlEncoded = \bytes ->

    chainUtf8 = \bytesList, tryFun -> Str.fromUtf8 bytesList |> mapUtf8Err |> Result.try tryFun

    # simplify `BadUtf8 Utf8ByteProblem ...` error
    mapUtf8Err = \err -> err |> Result.mapErr \_ -> BadUtf8

    parse = \bytesRemaining, state, key, chomped, dict ->
        tail = List.dropFirst bytesRemaining 1

        when bytesRemaining is
            [] if List.isEmpty chomped -> dict |> Ok
            [] ->
                # chomped last value
                keyStr <- key |> chainUtf8
                valueStr <- chomped |> chainUtf8

                Dict.insert dict keyStr valueStr |> Ok

            ['=', ..] -> parse tail ParsingValue chomped [] dict # put chomped into key
            ['&', ..] ->
                keyStr <- key |> chainUtf8
                valueStr <- chomped |> chainUtf8

                parse tail ParsingKey [] [] (Dict.insert dict keyStr valueStr)

            ['%', secondByte, thirdByte, ..] ->
                hex = Num.toU8 (hexBytesToU32 [secondByte, thirdByte])

                parse (List.dropFirst tail 2) state key (List.append chomped hex) dict

            [firstByte, ..] -> parse tail state key (List.append chomped firstByte) dict

    parse bytes ParsingKey [] [] (Dict.empty {})

expect hexBytesToU32 ['2', '0'] == 32

expect
    bytes = Str.toUtf8 "todo=foo&status=bar"
    parsed = parseFormUrlEncoded bytes |> Result.withDefault (Dict.empty {})

    Dict.toList parsed == [("todo", "foo"), ("status", "bar")]

expect
    Str.toUtf8 "task=asdfs%20adf&status=qwerwe"
    |> parseFormUrlEncoded
    |> Result.withDefault (Dict.empty {})
    |> Dict.toList
    |> Bool.isEq [("task", "asdfs adf"), ("status", "qwerwe")]

hexBytesToU32 : List U8 -> U32
hexBytesToU32 = \bytes ->
    bytes
    |> List.reverse
    |> List.walkWithIndex 0 \accum, byte, i -> accum + (Num.powInt 16 (Num.toU32 i)) * (hexToDec byte)
    |> Num.toU32

expect hexBytesToU32 ['0', '0', '0', '0'] == 0
expect hexBytesToU32 ['0', '0', '0', '1'] == 1
expect hexBytesToU32 ['0', '0', '0', 'F'] == 15
expect hexBytesToU32 ['0', '0', '1', '0'] == 16
expect hexBytesToU32 ['0', '0', 'F', 'F'] == 255
expect hexBytesToU32 ['0', '1', '0', '0'] == 256
expect hexBytesToU32 ['0', 'F', 'F', 'F'] == 4095
expect hexBytesToU32 ['1', '0', '0', '0'] == 4096
expect hexBytesToU32 ['1', '6', 'F', 'F', '1'] == 94193

hexToDec : U8 -> U32
hexToDec = \byte ->
    when byte is
        '0' -> 0
        '1' -> 1
        '2' -> 2
        '3' -> 3
        '4' -> 4
        '5' -> 5
        '6' -> 6
        '7' -> 7
        '8' -> 8
        '9' -> 9
        'A' -> 10
        'B' -> 11
        'C' -> 12
        'D' -> 13
        'E' -> 14
        'F' -> 15
        _ -> crash "Impossible error: the `when` block I'm in should have matched before reaching the catch-all `_`."

expect hexToDec '0' == 0
expect hexToDec 'F' == 15
