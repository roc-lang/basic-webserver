import http.Header
import http.Method
import http.Request
import http.Response

## Host-ABI types for outbound HTTP. Inbound server requests have a distinct
## streaming representation in InternalServer.
InternalHttp :: [].{
    ConnectReason : [
        ConnectionAborted,
        ConnectionRefused,
        ConnectionReset,
        HostUnreachable,
        NetworkUnreachable,
        AddressNotAvailable,
        PermissionDenied,
        TimedOut,
        Other,
    ]

    ## A failure to exchange an HTTP request with its destination. These tags
    ## are stable programmatic categories; detail strings are diagnostic only.
    ## ExchangeFailed covers the indivisible Client::request stage (writing the
    ## request and waiting for response headers). ResponseBodyFailed occurs only
    ## after valid response headers have been received.
    TransportErr : [
        Timeout,
        DnsFailed({ host : Str, detail : Str }),
        ConnectFailed({
            host : Str,
            port : U16,
            reason : ConnectReason,
            detail : Str,
        }),
        TlsFailed({ host : Str, detail : Str }),
        ConnectionClosed,
        ExchangeFailed(Str),
        ResponseBodyFailed(Str),
        InvalidResponse(Str),
        Cancelled,
        Other(Str),
    ]

    SendErr : [
        InvalidRequest(Str),
        Transport(TransportErr),
    ]

    HostHeader : { name : Str, value : Str }

    OutboundRequestToHost : {
        method : U8,
        method_ext : Str,
        headers : List(HostHeader),
        uri : Str,
        body : List(U8),
        timeout_ms : U64,
    }

    OutboundResponseFromHost : {
        status : U16,
        headers : List(HostHeader),
        body : List(U8),
    }

    to_host_request : Request.Request -> OutboundRequestToHost
    to_host_request = |request| {
        method = Request.method(request)

        {
            method: to_host_method(method),
            method_ext: to_host_method_ext(method),
            headers: Request.headers(request).map(to_host_header),
            uri: Request.uri(request),
            body: Request.body(request),
            timeout_ms: to_host_timeout(Request.timeout(request)),
        }
    }

    from_host_response : OutboundResponseFromHost -> Response.Response
    from_host_response = |response|
        Response.from_status(response.status)
            .with_headers(response.headers.map(from_host_header))
            .with_body(response.body)

    to_host_method : Method.Method -> U8
    to_host_method = |method|
        match method {
            OPTIONS => 5
            GET => 3
            POST => 7
            PUT => 8
            DELETE => 1
            HEAD => 4
            TRACE => 9
            CONNECT => 0
            PATCH => 6
            QUERY => 2
            Unknown(_) => 2
        }

    to_host_method_ext : Method.Method -> Str
    to_host_method_ext = |method|
        match method {
            QUERY => "QUERY"
            Unknown(ext) => ext
            _ => ""
        }

    to_host_timeout : [TimeoutMilliseconds(U64), NoTimeout] -> U64
    to_host_timeout = |timeout|
        match timeout {
            TimeoutMilliseconds(ms) => ms
            NoTimeout => 0
        }

    to_host_header : Header.Header -> HostHeader
    to_host_header = |header| { name: header.name, value: header.value }

    from_host_header : HostHeader -> Header.Header
    from_host_header = |{ name, value }| { name, value }
}
