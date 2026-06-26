import InternalHttp

## A module for working with both inbound HTTP requests/responses in a webserver
## and outbound HTTP requests (`send!`/`get_utf8!`).
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

    # The single outbound host effect: hand a fully-marshalled request to the
    # host and get back a marshalled response. Transport failures are encoded by
    # the host as a sentinel status+body pair (see `send!`), not as a separate
    # error channel.
    host_send_request! : InternalHttp.RequestToAndFromHost => InternalHttp.ResponseToAndFromHost

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

    ## Send an HTTP request, succeeding with a [Response] or failing with an
    ## `HttpErr`.
    ##
    ## ```roc
    ## response = Http.send!({ Http.default_request & uri: "https://www.roc-lang.org" })?
    ## ```
    send! : Request => Try(Response, [HttpErr([Timeout, NetworkError, BadBody, Other(List(U8))])])
    send! = |request| {
        host_request = InternalHttp.to_host_request(request)
        response = InternalHttp.from_host_response(Http.host_send_request!(host_request))

        # The host signals transport failures with these reserved status+body
        # sentinels (produced in src/lib.rs); everything else is a real response.
        other_error_prefix = Str.to_utf8("OTHER ERROR\n")

        if response.status == 408 and response.body == Str.to_utf8("Timeout") {
            Err(HttpErr(Timeout))
        } else if response.status == 500 and response.body == Str.to_utf8("NetworkError") {
            Err(HttpErr(NetworkError))
        } else if response.status == 500 and response.body == Str.to_utf8("BadBody") {
            Err(HttpErr(BadBody))
        } else if response.status == 500 and List.starts_with(response.body, other_error_prefix) {
            Err(HttpErr(Other(List.drop_first(response.body, List.len(other_error_prefix)))))
        } else {
            Ok(response)
        }
    }

    ## Perform an HTTP GET and decode the response body as a UTF-8 [Str].
    ##
    ## ```roc
    ## hello_str = Http.get_utf8!("http://localhost:8000")?
    ## ```
    get_utf8! : Str => Try(Str, [BadBody(Str), HttpErr([Timeout, NetworkError, BadBody, Other(List(U8))])])
    get_utf8! = |uri|
        match send!({ ..default_request, uri: uri }) {
            Err(HttpErr(err)) => Err(HttpErr(err))
            Ok(response) =>
                match Str.from_utf8(response.body) {
                    Ok(str) => Ok(str)
                    Err(_) => Err(BadBody("get_utf8!: response body was not valid UTF-8"))
                }
        }
}
