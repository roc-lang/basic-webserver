## See IETF RFC 7578 Returning Values from Forms: multipart/form-data
## https://datatracker.ietf.org/doc/html/rfc7578
module [
    FormData,
    parse_form_url_encoded,
    parse_multipart_form_data,
    decode_multipart_form_data_boundary,
]

import InternalHttp
import SplitList

FormData : {
    ## Content-Disposition response header
    ## Indicates if content expects to be displayed inline or as attachment.
    ##
    ## Example: `inline` or `attachment; filename="filename.jpg"`
    disposition : List U8,

    ## Content-Type header
    ## Original media type of the resource.
    ##
    ## Example: `multipart/form-data; boundary=ExampleBoundaryString`
    type : List U8,

    ## Content-Transfer-Encoding
    ## Specifies how the body is encoded.
    ##
    ## Example: `base64` or `binary`
    encoding : List U8,

    ## Acutal data that was entered in the form, in encoded form.
    data : List U8,
}

newline = ['\r', '\n']
doubledash = ['-', '-']

## Produces function that extracts the header value.
##
## Example call:
## ```roc
## parse_content_f({
##    upper: Str.to_utf8("Content-Disposition:"),
##    lower: Str.to_utf8("content-disposition:"),
## })
##
## input = Str.to_utf8("\r\nContent-Disposition: form-data; name=\"sometext\"\r\nSome text here...")
## actual = parseContentDispositionF(input)
## expected = Ok({
##    value: Str.to_utf8(" form-data; name=\"sometext\""),
##    rest: Str.to_utf8("\r\nSome text here..."),
## })
## ```
##
parse_content_f : { upper : List U8, lower : List U8 } -> (List U8 -> Result { value : List U8, rest : List U8 } _)
parse_content_f = |{ upper, lower }|
    |bytes|

        to_search_upper = List.concat(newline, upper)
        to_search_lower = List.concat(newline, lower)
        search_length = List.len(to_search_upper)
        after_search = List.sublist(bytes, { start: search_length, len: Num.max_u64 })

        if
            List.starts_with(bytes, to_search_upper)
            or List.starts_with(bytes, to_search_lower)
        then
            next_line_start = after_search |> List.find_first_index?(|b| b == '\r')

            Ok(
                {
                    value: List.sublist(after_search, { start: 0, len: next_line_start }),
                    rest: List.sublist(after_search, { start: next_line_start, len: Num.max_u64 }),
                },
            )
        else
            Err(ExpectedContent)

parse_content_disposition_f = parse_content_f(
    {
        upper: Str.to_utf8("Content-Disposition:"),
        lower: Str.to_utf8("content-disposition:"),
    },
)

expect
    input = Str.to_utf8("\r\nContent-Disposition: form-data; name=\"sometext\"\r\nSome text here...")
    actual = parse_content_disposition_f(input)
    expected = Ok(
        {
            value: Str.to_utf8(" form-data; name=\"sometext\""),
            rest: Str.to_utf8("\r\nSome text here..."),
        },
    )

    actual == expected

parse_content_type_f = parse_content_f(
    {
        upper: Str.to_utf8("Content-Type:"),
        lower: Str.to_utf8("content-type:"),
    },
)

expect
    input = Str.to_utf8("\r\ncontent-type: multipart/mixed; boundary=abcde\r\nSome text here...")
    actual = parse_content_type_f(input)
    expected = Ok(
        {
            value: Str.to_utf8(" multipart/mixed; boundary=abcde"),
            rest: Str.to_utf8("\r\nSome text here..."),
        },
    )

    actual == expected

parse_content_transfer_encoding_f = parse_content_f(
    {
        upper: Str.to_utf8("Content-Transfer-Encoding:"),
        lower: Str.to_utf8("content-transfer-encoding:"),
    },
)

expect
    input = Str.to_utf8("\r\nContent-Transfer-Encoding: binary\r\nSome text here...")
    actual = parse_content_transfer_encoding_f(input)
    expected = Ok(
        {
            value: Str.to_utf8(" binary"),
            rest: Str.to_utf8("\r\nSome text here..."),
        },
    )

    actual == expected

## Parses all headers: Content-Disposition, Content-Type and Content-Transfer-Encoding.
parse_all_headers : List U8 -> Result FormData _
parse_all_headers = |bytes|

    double_newline_length = 4 # \r\n\r\n

    when parse_content_disposition_f(bytes) is
        Err(err) -> Err(ExpectedContentDisposition(bytes, err))
        Ok({ value: disposition, rest: first }) ->
            when parse_content_type_f(first) is
                Err(_) ->
                    Ok(
                        {
                            disposition,
                            type: [],
                            encoding: [],
                            data: List.drop_first(first, double_newline_length),
                        },
                    )

                Ok({ value: type, rest: second }) ->
                    when parse_content_transfer_encoding_f(second) is
                        Err(_) ->
                            Ok(
                                {
                                    disposition,
                                    type,
                                    encoding: [],
                                    data: List.drop_first(second, double_newline_length),
                                },
                            )

                        Ok({ value: encoding, rest }) ->
                            Ok(
                                {
                                    disposition,
                                    type,
                                    encoding,
                                    data: List.drop_first(rest, double_newline_length),
                                },
                            )

expect
    header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\n\r\n<FILE CONTENTS>"
    actual = parse_all_headers(Str.to_utf8(header))
    expected = Ok(
        {
            disposition: Str.to_utf8(" form-data; name=\"sometext\""),
            type: Str.to_utf8(""),
            encoding: Str.to_utf8(""),
            data: Str.to_utf8("<FILE CONTENTS>"),
        },
    )

    actual == expected

expect
    header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\n\r\n<FILE CONTENTS>"
    actual = parse_all_headers(Str.to_utf8(header))
    expected = Ok(
        {
            disposition: Str.to_utf8(" form-data; name=\"sometext\""),
            type: Str.to_utf8(" multipart/mixed; boundary=abcde"),
            encoding: Str.to_utf8(""),
            data: Str.to_utf8("<FILE CONTENTS>"),
        },
    )

    actual == expected

expect
    header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\nContent-Transfer-Encoding: binary\r\n\r\n<FILE CONTENTS>"
    actual = parse_all_headers(Str.to_utf8(header))
    expected = Ok(
        {
            disposition: Str.to_utf8(" form-data; name=\"sometext\""),
            type: Str.to_utf8(" multipart/mixed; boundary=abcde"),
            encoding: Str.to_utf8(" binary"),
            data: Str.to_utf8("<FILE CONTENTS>"),
        },
    )

    actual == expected

## Parses the body of a multipart/form-data request.
##
## Example body with boundary 12345:
## ```
## --12345
## Content-Disposition: form-data; name="sometext"
##
## some text that you wrote in your html form ...
## --12345--
## ```
parse_form_data :
    {
        body : List U8,
        ## Each part of the form is enclosed between two boundary markers.
        boundary : List U8,
    }
    -> Result (List FormData) [ExpectedEnclosedByBoundary]
parse_form_data = |{ body, boundary }|

    start_marker = List.join([doubledash, boundary])
    end_marker = List.join([newline, doubledash, boundary, doubledash, newline])
    boundary_with_prefix = List.join([newline, doubledash, boundary])

    is_enclosed_by_boundary =
        List.starts_with(body, start_marker)
        and List.ends_with(body, end_marker)

    if is_enclosed_by_boundary then
        body
        |> List.drop_first(List.len(start_marker))
        |> SplitList.split_on_list(boundary_with_prefix)
        |> List.drop_if(|part| part == doubledash)
        |> List.keep_oks(parse_all_headers)
        |> Ok
    else
        Err(ExpectedEnclosedByBoundary)

expect
    # """
    # ------WebKitFormBoundaryQGx5ri4XFwWbaAX4
    # Content-Disposition: form-data; name="file"; filename="sample2.csv"
    # Content-Type: text/csv
    #
    # First,Last
    # Rachel,Booker
    #
    # ------WebKitFormBoundaryQGx5ri4XFwWbaAX4--
    #
    # """
    actual = parse_form_data(
        {
            body: [45, 45, 45, 45, 45, 45, 87, 101, 98, 75, 105, 116, 70, 111, 114, 109, 66, 111, 117, 110, 100, 97, 114, 121, 70, 71, 54, 83, 65, 109, 121, 106, 112, 49, 108, 118, 102, 57, 80, 55, 13, 10, 67, 111, 110, 116, 101, 110, 116, 45, 68, 105, 115, 112, 111, 115, 105, 116, 105, 111, 110, 58, 32, 102, 111, 114, 109, 45, 100, 97, 116, 97, 59, 32, 110, 97, 109, 101, 61, 34, 102, 105, 108, 101, 34, 59, 32, 102, 105, 108, 101, 110, 97, 109, 101, 61, 34, 115, 97, 109, 112, 108, 101, 50, 46, 99, 115, 118, 34, 13, 10, 67, 111, 110, 116, 101, 110, 116, 45, 84, 121, 112, 101, 58, 32, 116, 101, 120, 116, 47, 99, 115, 118, 13, 10, 13, 10, 70, 105, 114, 115, 116, 44, 76, 97, 115, 116, 13, 10, 82, 97, 99, 104, 101, 108, 44, 66, 111, 111, 107, 101, 114, 13, 10, 13, 10, 45, 45, 45, 45, 45, 45, 87, 101, 98, 75, 105, 116, 70, 111, 114, 109, 66, 111, 117, 110, 100, 97, 114, 121, 70, 71, 54, 83, 65, 109, 121, 106, 112, 49, 108, 118, 102, 57, 80, 55, 45, 45, 13, 10],
            boundary: [45, 45, 45, 45, 87, 101, 98, 75, 105, 116, 70, 111, 114, 109, 66, 111, 117, 110, 100, 97, 114, 121, 70, 71, 54, 83, 65, 109, 121, 106, 112, 49, 108, 118, 102, 57, 80, 55],
        },
    )
    # Result.isErr actual
    expected = Ok(
        [
            {
                data: [70, 105, 114, 115, 116, 44, 76, 97, 115, 116, 13, 10, 82, 97, 99, 104, 101, 108, 44, 66, 111, 111, 107, 101, 114, 13, 10],
                disposition: [32, 102, 111, 114, 109, 45, 100, 97, 116, 97, 59, 32, 110, 97, 109, 101, 61, 34, 102, 105, 108, 101, 34, 59, 32, 102, 105, 108, 101, 110, 97, 109, 101, 61, 34, 115, 97, 109, 112, 108, 101, 50, 46, 99, 115, 118, 34],
                encoding: [],
                type: [32, 116, 101, 120, 116, 47, 99, 115, 118],
            },
        ],
    )

    actual == expected

expect
    input = Str.to_utf8("--12345\r\nContent-Disposition: form-data; name=\"sometext\"\r\n\r\nsome text sent via post...\r\n--12345--\r\n")
    actual = parse_form_data(
        {
            body: input,
            boundary: Str.to_utf8("12345"),
        },
    )
    expected = Ok(
        [
            {
                disposition: Str.to_utf8(" form-data; name=\"sometext\""),
                type: [],
                encoding: [],
                data: Str.to_utf8("some text sent via post..."),
            },
        ],
    )

    actual == expected

expect
    body = Str.to_utf8("--AaB03x\r\nContent-Disposition: form-data; name=\"submit-name\"\r\n\r\nLarry\r\n--AaB03x\r\nContent-Disposition: form-data; name=\"files\"\r\nContent-Type: multipart/mixed; boundary=BbC04y\r\n\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file1.txt\"\r\nContent-Type: text/plain\r\n\r\n... contents of file1.txt ...\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file2.gif\"\r\nContent-Type: image/gif\r\nContent-Transfer-Encoding: binary\r\n\r\n...contents of file2.gif...\r\n--BbC04y--\r\n--AaB03x--\r\n")
    boundary = Str.to_utf8("AaB03x")
    actual = parse_form_data({ body, boundary })
    expected = Ok(
        [
            {
                disposition: Str.to_utf8(" form-data; name=\"submit-name\""),
                type: [],
                encoding: [],
                data: Str.to_utf8("Larry"),
            },
            {
                disposition: Str.to_utf8(" form-data; name=\"files\""),
                type: Str.to_utf8(" multipart/mixed; boundary=BbC04y"),
                encoding: [],
                data: Str.to_utf8("--BbC04y\r\nContent-Disposition: file; filename=\"file1.txt\"\r\nContent-Type: text/plain\r\n\r\n... contents of file1.txt ...\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file2.gif\"\r\nContent-Type: image/gif\r\nContent-Transfer-Encoding: binary\r\n\r\n...contents of file2.gif...\r\n--BbC04y--"),
            },
        ],
    )

    actual == expected

## Parse URL-encoded form values (`todo=foo&status=bar`) into a Dict (`("todo", "foo"), ("status", "bar")`).
##
## ```
## expect
##     bytes = Str.to_utf8("todo=foo&status=bar")
##     parsed = parse_form_url_encoded(bytes) |> Result.with_default(Dict.empty({}))
##
##     Dict.to_list(parsed) == [("todo", "foo"), ("status", "bar")]
## ```
parse_form_url_encoded : List U8 -> Result (Dict Str Str) [BadUtf8]
parse_form_url_encoded = |bytes|

    chain_utf8 = |bytes_list, try_fun| Str.from_utf8(bytes_list) |> map_utf8_err |> Result.try(try_fun)

    # simplify `BadUtf8 Utf8ByteProblem ...` error
    map_utf8_err = |err| err |> Result.map_err(|_| BadUtf8)

    help = |bytes_remaining, state, key, chomped, dict|
        tail = List.drop_first(bytes_remaining, 1)

        when bytes_remaining is
            [] if List.is_empty(chomped) -> dict |> Ok
            [] ->
                # chomped last value
                key
                |> chain_utf8(
                    |key_str|
                        chomped
                        |> chain_utf8(
                            |value_str|
                                Dict.insert(dict, key_str, value_str) |> Ok,
                        ),
                )

            ['=', ..] -> help(tail, ParsingValue, chomped, [], dict) # put chomped into key
            ['&', ..] ->
                key
                |> chain_utf8(
                    |key_str|
                        chomped
                        |> chain_utf8(
                            |value_str|
                                help(tail, ParsingKey, [], [], Dict.insert(dict, key_str, value_str)),
                        ),
                )

            ['%', second_byte, third_byte, ..] ->
                hex = Num.to_u8(hex_bytes_to_u32([second_byte, third_byte]))

                help(List.drop_first(tail, 2), state, key, List.append(chomped, hex), dict)

            [first_byte, ..] -> help(tail, state, key, List.append(chomped, first_byte), dict)

    help(bytes, ParsingKey, [], [], Dict.empty({}))

expect hex_bytes_to_u32(['2', '0']) == 32

expect
    bytes = Str.to_utf8("todo=foo&status=bar")
    parsed = parse_form_url_encoded(bytes) |> Result.with_default(Dict.empty({}))

    Dict.to_list(parsed) == [("todo", "foo"), ("status", "bar")]

expect
    Str.to_utf8("task=asdfs%20adf&status=qwerwe")
    |> parse_form_url_encoded
    |> Result.with_default(Dict.empty({}))
    |> Dict.to_list
    |> Bool.is_eq([("task", "asdfs adf"), ("status", "qwerwe")])

hex_bytes_to_u32 : List U8 -> U32
hex_bytes_to_u32 = |bytes|
    bytes
    |> List.reverse
    |> List.walk_with_index(0, |accum, byte, i| accum + (Num.pow_int(16, Num.to_u32(i))) * (hex_to_dec(byte)))
    |> Num.to_u32

expect hex_bytes_to_u32(['0', '0', '0', '0']) == 0
expect hex_bytes_to_u32(['0', '0', '0', '1']) == 1
expect hex_bytes_to_u32(['0', '0', '0', 'F']) == 15
expect hex_bytes_to_u32(['0', '0', '1', '0']) == 16
expect hex_bytes_to_u32(['0', '0', 'F', 'F']) == 255
expect hex_bytes_to_u32(['0', '1', '0', '0']) == 256
expect hex_bytes_to_u32(['0', 'F', 'F', 'F']) == 4095
expect hex_bytes_to_u32(['1', '0', '0', '0']) == 4096
expect hex_bytes_to_u32(['1', '6', 'F', 'F', '1']) == 94193

hex_to_dec : U8 -> U32
hex_to_dec = |byte|
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
        _ -> crash("Impossible error: the `when` block I'm in should have matched before reaching the catch-all `_`.")

expect hex_to_dec('0') == 0
expect hex_to_dec('F') == 15

## For HTML forms that include files or large amounts of text.
##
## See usage in examples/file-upload-form.roc
parse_multipart_form_data :
    {
        headers : List InternalHttp.Header,
        body : List U8,
    }
    -> Result (List MultipartFormData.FormData) [InvalidMultipartFormData, ExpectedContentTypeHeader, InvalidContentTypeHeader]
parse_multipart_form_data = |args|
    decode_multipart_form_data_boundary(args.headers)
    |> Result.try(
        |boundary|
            { body: args.body, boundary }
            |> parse_form_data
            |> Result.map_err(|_| InvalidMultipartFormData),
    )

decode_multipart_form_data_boundary : List { name : Str, value : Str } -> Result (List U8) _
decode_multipart_form_data_boundary = |headers|
    headers
    |> List.keep_if(|{ name }| name == "Content-Type" or name == "content-type")
    |> List.first
    |> Result.map_err(|ListWasEmpty| ExpectedContentTypeHeader)
    |> Result.try(
        |{ value }|
            when Str.split_last(value, "=") is
                Ok({ after }) -> Ok(Str.to_utf8(after))
                Err(NotFound) -> Err(InvalidContentTypeHeader),
    )
