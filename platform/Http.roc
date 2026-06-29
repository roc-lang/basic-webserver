import InternalHttp

## A module for working with both inbound HTTP requests/responses in a webserver
## and outbound HTTP requests (`send!`/`get_utf8!`/`get!`).
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

    ## A JSON value wrapper for types the current compiler cannot yet derive
    ## `encode_to` for structurally.
    JsonValue :: [
        Null,
        Boolean(Bool),
        String(Str),
        Unsigned(U64),
        Signed(I64),
        Array(List(JsonValue)),
        Object(List({ name : Str, value : JsonValue })),
    ].{
        null : JsonValue
        null = Null

        bool : Bool -> JsonValue
        bool = |value| Boolean(value)

        str : Str -> JsonValue
        str = |value| String(value)

        u64 : U64 -> JsonValue
        u64 = |value| Unsigned(value)

        i64 : I64 -> JsonValue
        i64 = |value| Signed(value)

        list : List(JsonValue) -> JsonValue
        list = |values| Array(values)

        object : List({ name : Str, value : JsonValue }) -> JsonValue
        object = |fields| Object(fields)

        field : (Str, JsonValue) -> { name : Str, value : JsonValue }
        field = |(name, value)| { name, value }

        encode_to : JsonValue, InternalJsonFormat -> (InternalJsonOutput -> Try(InternalJsonOutput, []))
        encode_to = |value, _format| |state| encode_json_value(value, state)
    }

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

    ## Perform an HTTP GET and decode the response body as JSON.
    ##
    ## JSON parser failures are returned as `JsonErr(Json)`.
    ##
    ## ```roc
    ## payload : Try({ foo : Str }, _)
    ## payload = Http.get!("http://localhost:8000")
    ## ```
    get! = |uri|
        match get_utf8!(uri) {
            Err(BadBody(err)) => Err(BadBody(err))
            Err(HttpErr(err)) => Err(HttpErr(err))
            Ok(body) =>
                match Json.parse(body) {
                    Ok(value) => Ok(value)
                    Err(err) => Err(JsonErr(err))
                }
        }

    ## Decode a request body as a UTF-8 [Str].
    body_utf8 : Request -> Try(Str, [BadBody(Str)])
    body_utf8 = |request|
        match Str.from_utf8(request.body) {
            Ok(str) => Ok(str)
            Err(_) => Err(BadBody("body_utf8: request body was not valid UTF-8"))
        }

    ## Decode a request body as JSON.
    body_json = |request|
        match body_utf8(request) {
            Err(BadBody(err)) => Err(BadBody(err))
            Ok(body) =>
                match Json.parse(body) {
                    Ok(value) => Ok(value)
                    Err(err) => Err(JsonErr(err))
                }
        }

    ## Encode a Roc value as UTF-8 JSON bytes.
    ##
    ## The current compiler-derived `encode_to` support covers records, empty
    ## records, [Str], [U64], aliases around those shapes, and custom nominal
    ## types that define `encode_to`.
    json_bytes : value -> List(U8)
        where [
            value.encode_to : value, InternalJsonFormat -> (InternalJsonOutput -> Try(InternalJsonOutput, [])),
        ]
    json_bytes = |value| Str.to_utf8(encode_json_string(value))

    ## Encode a Roc value as a 200 JSON [Response].
    json_response : value -> Response
        where [
            value.encode_to : value, InternalJsonFormat -> (InternalJsonOutput -> Try(InternalJsonOutput, [])),
        ]
    json_response = |value| json_response_with_status(200, value)

    ## Encode a Roc value as a JSON [Response] with the given status code.
    json_response_with_status : U16, value -> Response
        where [
            value.encode_to : value, InternalJsonFormat -> (InternalJsonOutput -> Try(InternalJsonOutput, [])),
        ]
    json_response_with_status = |status, value| {
        {
            status,
            headers: [header(("Content-Type", "application/json; charset=utf-8"))],
            body: json_bytes(value),
        }
    }
}

InternalJsonOutput : {
    output : Str,
    field_counts : List(U64),
}

InternalJsonFormat := [Default].{
    rename_field : InternalJsonFormat, Str -> Str
    rename_field = |_, name| name

    begin_record : InternalJsonOutput -> Try(InternalJsonOutput, [])
    begin_record = |state|
        Ok(
            {
                output: Str.concat(state.output, "{"),
                field_counts: List.append(state.field_counts, 0),
            },
        )

    encode_record_field : Str, InternalJsonOutput -> Try(InternalJsonOutput, [])
    encode_record_field = |name, state| {
        count = current_field_count(state.field_counts)
        prefix = if count == 0 { "" } else { "," }

        Ok(
            {
                output: Str.concat(
                    state.output,
                    Str.concat(prefix, Str.concat(quote_json_string(name), ":")),
                ),
                field_counts: List.append(List.drop_last(state.field_counts, 1), count + 1),
            },
        )
    }

    end_record : InternalJsonOutput -> Try(InternalJsonOutput, [])
    end_record = |state|
        Ok(
            {
                output: Str.concat(state.output, "}"),
                field_counts: List.drop_last(state.field_counts, 1),
            },
        )

    encode_str : Str, InternalJsonOutput -> Try(InternalJsonOutput, [])
    encode_str = |value, state|
        Ok({ ..state, output: Str.concat(state.output, quote_json_string(value)) })

    encode_u64 : U64, InternalJsonOutput -> Try(InternalJsonOutput, [])
    encode_u64 = |value, state|
        Ok({ ..state, output: Str.concat(state.output, U64.to_str(value)) })
}

encode_json_string : value -> Str
    where [
        value.encode_to : value, InternalJsonFormat -> (InternalJsonOutput -> Try(InternalJsonOutput, [])),
    ]
encode_json_string = |value| {
    encode_value = value.encode_to(InternalJsonFormat.Default)
    Ok(final) = encode_value({ output: "", field_counts: [] })
    final.output
}

encode_json_value : Http.JsonValue, InternalJsonOutput -> Try(InternalJsonOutput, [])
encode_json_value = |value, state|
    match value {
        Http.JsonValue.Null => Ok(append_json("null", state))
        Http.JsonValue.Boolean(bool) => Ok(append_json(if bool { "true" } else { "false" }, state))
        Http.JsonValue.String(str) => Ok(append_json(quote_json_string(str), state))
        Http.JsonValue.Unsigned(num) => Ok(append_json(U64.to_str(num), state))
        Http.JsonValue.Signed(num) => Ok(append_json(I64.to_str(num), state))
        Http.JsonValue.Array(values) => encode_json_array(values, state)
        Http.JsonValue.Object(fields) => encode_json_object(fields, state)
    }

encode_json_array : List(Http.JsonValue), InternalJsonOutput -> Try(InternalJsonOutput, [])
encode_json_array = |values, state| {
    initial = append_json("[", state)
    after_values = encode_json_array_items(values, initial, 0)?
    Ok(append_json("]", after_values))
}

encode_json_array_items : List(Http.JsonValue), InternalJsonOutput, U64 -> Try(InternalJsonOutput, [])
encode_json_array_items = |values, state, index| {
    if index >= List.len(values) {
        Ok(state)
    } else {
        match List.get(values, index) {
            Ok(value) => {
                with_prefix = if index == 0 { state } else { append_json(",", state) }
                after_value = encode_json_value(value, with_prefix)?
                encode_json_array_items(values, after_value, index + 1)
            }
            Err(_) => Ok(state)
        }
    }
}

encode_json_object : List({ name : Str, value : Http.JsonValue }), InternalJsonOutput -> Try(InternalJsonOutput, [])
encode_json_object = |fields, state| {
    initial = append_json("{", state)
    after_fields = encode_json_object_fields(fields, initial, 0)?
    Ok(append_json("}", after_fields))
}

encode_json_object_fields : List({ name : Str, value : Http.JsonValue }), InternalJsonOutput, U64 -> Try(InternalJsonOutput, [])
encode_json_object_fields = |fields, state, index| {
    if index >= List.len(fields) {
        Ok(state)
    } else {
        match List.get(fields, index) {
            Ok(field) => {
                prefix = if index == 0 { "" } else { "," }
                with_name = append_json(Str.concat(prefix, Str.concat(quote_json_string(field.name), ":")), state)
                after_value = encode_json_value(field.value, with_name)?
                encode_json_object_fields(fields, after_value, index + 1)
            }
            Err(_) => Ok(state)
        }
    }
}

append_json : Str, InternalJsonOutput -> InternalJsonOutput
append_json = |chunk, state| { ..state, output: Str.concat(state.output, chunk) }

current_field_count : List(U64) -> U64
current_field_count = |counts|
    match List.last(counts) {
        Ok(count) => count
        Err(_) => 0
    }

quote_json_string : Str -> Str
quote_json_string = |value| Str.concat(Str.concat("\"", escape_json_string(value)), "\"")

escape_json_string : Str -> Str
escape_json_string = |value| {
    escaped_bytes =
        List.fold(
            Str.to_utf8(value),
            [],
            |bytes, byte| {
                if byte == 34 {
                    List.concat(bytes, [92, 34])
                } else if byte == 92 {
                    List.concat(bytes, [92, 92])
                } else if byte == 8 {
                    List.concat(bytes, [92, 98])
                } else if byte == 12 {
                    List.concat(bytes, [92, 102])
                } else if byte == 10 {
                    List.concat(bytes, [92, 110])
                } else if byte == 13 {
                    List.concat(bytes, [92, 114])
                } else if byte == 9 {
                    List.concat(bytes, [92, 116])
                } else if byte < 32 {
                    List.concat(bytes, [92, 117, 48, 48, hex_digit(byte / 16), hex_digit(byte % 16)])
                } else {
                    List.append(bytes, byte)
                }
            },
        )

    match Str.from_utf8(escaped_bytes) {
        Ok(str) => str
        Err(_) => ""
    }
}

hex_digit : U8 -> U8
hex_digit = |n|
    if n < 10 {
        n + 48
    } else {
        n + 55
    }
