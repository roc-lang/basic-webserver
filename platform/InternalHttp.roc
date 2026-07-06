# Host-ABI types and conversions shared between the host and the Http module.
# The `*ToAndFromHost` records map 1:1 to the generated Rust glue types in
# src/roc_platform_abi.rs.
import http.Header
import http.Method
import http.Request
import http.Response

InternalHttp :: [].{
    HostHeader : { name : Str, value : Str }

    # FOR HOST

    RequestToAndFromHost : {
        method : U8,
        method_ext : Str,
        headers : List(HostHeader),
        uri : Str,
        body : List(U8),
        timeout_ms : U64,
    }

    ResponseToAndFromHost : {
        status : U16,
        headers : List(HostHeader),
        body : List(U8),
    }

    to_host_response : Response.Response -> ResponseToAndFromHost
    to_host_response = |response| {
        status: Response.status(response),
        headers: Response.headers(response).map(to_host_header),
        body: Response.body(response),
    }

    to_host_request : Request.Request -> RequestToAndFromHost
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
            QUERY => 10
            Unknown(_) => 2
        }

    to_host_method_ext : Method.Method -> Str
    to_host_method_ext = |method|
        match method {
            Unknown(ext) => ext
            _ => ""
        }

    to_host_timeout : [TimeoutMilliseconds(U64), NoTimeout] -> U64
    to_host_timeout = |timeout|
        match timeout {
            TimeoutMilliseconds(ms) => ms
            NoTimeout => 0
        }

    from_host_request : RequestToAndFromHost -> Request.Request
    from_host_request = |{ method, method_ext, headers, uri, body, timeout_ms }|
        Request.from_method(from_host_method(method, method_ext))
            .with_headers(headers.map(from_host_header))
            .with_uri(uri)
            .with_body(body)
            .with_timeout(from_host_timeout(timeout_ms))

    from_host_method : U8, Str -> Method.Method
    from_host_method = |tag, ext|
        match tag {
            5 => OPTIONS
            3 => GET
            7 => POST
            8 => PUT
            1 => DELETE
            4 => HEAD
            9 => TRACE
            0 => CONNECT
            6 => PATCH
            10 => QUERY
            2 => Unknown(ext)
            _ => {
                crash "invalid method tag from host"
            }
        }

    from_host_timeout : U64 -> [TimeoutMilliseconds(U64), NoTimeout]
    from_host_timeout = |timeout|
        match timeout {
            0 => NoTimeout
            _ => TimeoutMilliseconds(timeout)
        }

    from_host_response : ResponseToAndFromHost -> Response.Response
    from_host_response = |{ status, headers, body }|
        Response.from_status(status)
            .with_headers(headers.map(from_host_header))
            .with_body(body)

    to_host_header : Header.Header -> HostHeader
    to_host_header = |header| { name: header.name, value: header.value }

    from_host_header : HostHeader -> Header.Header
    from_host_header = |{ name, value }| { name, value }
}
