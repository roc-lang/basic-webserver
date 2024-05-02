interface HttpResponse
    exposes [
        Response,
        # Convenience functions for returning Responses
        ok,
        noContent,
        err,
        badRequest,
        unauthorized,
        forbidden,
        notFound,
    ]
    imports [
        Task.{ Task },
        InternalHttp,
        HttpHeader.{ Header },
    ]

## Represents an HTTP response.
Response : InternalHttp.InternalResponse

## Makes a [HTTP 200](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/200) OK [Response].
ok : List Header, List U8 -> Task Response *
ok = \headers, body ->
    Task.ok {
        status: 200,
        headers: headers,
        body: body,
    }

## Makes a [HTTP 204](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/204) No Content [Response].
##
noContent : List Header, List U8 -> Task Response *
noContent = \headers, body ->
    Task.ok {
        status: 200,
        headers: headers,
        body: body,
    }

## Makes a [HTTP 500](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/500) Internal Server Error [Response].
err : List Header, List U8 -> Task Response *
err = \headers, body ->
    Task.ok {
        status: 500,
        headers: headers,
        body: body,
    }

## Makes a [HTTP 400](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/400) Not Found [Response].
badRequest : List Header, List U8 -> Task Response *
badRequest = \headers, body ->
    Task.ok {
        status: 400,
        headers: headers,
        body: body,
    }

## Makes a [HTTP 404](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/404) Not Found [Response].
notFound : List Header, List U8 -> Task Response *
notFound = \headers, body ->
    Task.ok {
        status: 404,
        headers: headers,
        body: body,
    }

## Makes a [HTTP 401](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/401) Unauthorized [Response].
unauthorized : List Header, List U8 -> Task Response *
unauthorized = \headers, body ->
    Task.ok {
        status: 401,
        headers: headers,
        body: body,
    }

## Makes a [HTTP 403](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/403) Forbidden [Response].
forbidden : List Header, List U8 -> Task Response *
forbidden = \headers, body ->
    Task.ok {
        status: 403,
        headers: headers,
        body: body,
    }
