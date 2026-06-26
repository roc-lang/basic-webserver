import InternalHttp

## A module for working with inbound HTTP requests and responses in a webserver.
##
## Outbound HTTP (`send!`/`get!`) is not yet ported to the new compiler; see the
## `.todoroc` modules.
Http :: [].{
    ## Represents an HTTP method: `[OPTIONS, GET, POST, PUT, DELETE, HEAD, TRACE, CONNECT, PATCH, EXTENSION(Str)]`
    Method : InternalHttp.Method

    ## Represents an HTTP header e.g. `Content-Type: application/json`.
    ## Header is a `{ name : Str, value : Str }`.
    Header : InternalHttp.Header

    ## Represents an HTTP request.
    ## Request is a record:
    ## ```
    ## {
    ##    method : Method,
    ##    headers : List(Header),
    ##    uri : Str,
    ##    body : List(U8),
    ##    timeout_ms : [TimeoutMilliseconds(U64), NoTimeout],
    ## }
    ## ```
    Request : InternalHttp.Request

    ## Represents an HTTP response.
    ##
    ## Response is a record with the following fields:
    ## ```
    ## {
    ##     status : U16,
    ##     headers : List(Header),
    ##     body : List(U8),
    ## }
    ## ```
    Response : InternalHttp.Response

    ## A default [Request] value.
    ## ```
    ## {
    ##     method: GET,
    ##     headers: [],
    ##     uri: "",
    ##     body: [],
    ##     timeout_ms: NoTimeout,
    ## }
    ## ```
    default_request : Request
    default_request = {
        method: GET,
        headers: [],
        uri: "",
        body: [],
        timeout_ms: NoTimeout,
    }

    ## An HTTP header for configuring requests.
    ##
    ## See common headers [here](https://en.wikipedia.org/wiki/List_of_HTTP_header_fields).
    ##
    ## Example: `header(("Content-Type", "application/json"))`
    header : (Str, Str) -> Header
    header = |(name, value)| { name, value }
}
