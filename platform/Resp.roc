interface Resp
    exposes [
        Resp,
        ok,
        notFound,
        withHeader,
        withContentType,
        headers,
    ]
    imports [InternalHttp]


## Represents an HTTP response from the webserver.
Resp := {
    statusCode : U16,
    statusText : Str,
    headers : List { key : Str, value : Str },
    body : Str,
}

## HTTP 200 OK
## https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/200
##
## Defaults to `Content-Type: text/plain; charset=utf-8`
ok : Str -> Resp
ok = \body -> utf8Resp 200 "OK" body

## HTTP 204 No Content
## https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/204
##
## Defaults to `Content-Type: text/plain; charset=utf-8`
noContent : Resp
noContent = utf8Resp 204 "No Content" ""

## HTTP 404 Not Found
## https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/404
##
## Defaults to `Content-Type: text/plain; charset=utf-8`
notFound : Str -> Resp
notFound = \body -> utf8Resp 404 "Not Found" body

withHeader : Resp, Str, Str -> Resp
withHeader = \@Resp resp, key, value ->
    @Resp { resp & headers: List.append resp.headers { key, value } }

## Sets the response's [`Content-Type`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type) header.
## If this response already had a Content-Type header, it will be replaced with the given value; if it did not have one,
## one will be added. In the unlikely (but allowed by the HTTP spec) event that it had multiple Content-Type headers,
## only the first will be replaced.
##
## e.g. `|> withContentType "text/html; charset=utf-8"`
##
## https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type
withContentType : Resp, Str -> Resp
withContentType = \@Resp resp, contentType ->
    when List.findFirstIndex resp.headers (\{key} -> key == "Content-Type") is
        Ok index -> @Resp { resp & headers: List.update resp.headers index \{ key } -> { key, value: contentType } }
        Err NotFound -> withHeader (@Resp resp) "Content-Type" contentType

headers : Resp -> List { key : Str, value : Str }
headers = \@Resp resp -> resp.headers

## Internal helper
utf8Resp : U16, Str, Str -> Resp
utf8Resp = \statusCode, statusText, body ->
    @Resp { statusCode, statusText, body, headers: defaultHeaders }

## Used by utf8Resp
defaultHeaders : List { key : Str, value : Str }
defaultHeaders = [{ key: "Content-Type", value: "text/plain; charset=utf8"}]
