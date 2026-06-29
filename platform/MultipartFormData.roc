## See IETF RFC 7578 Returning Values from Forms: multipart/form-data
## https://datatracker.ietf.org/doc/html/rfc7578
import InternalHttp
import SplitList

MultipartFormData :: [].{
    FormData : {
        ## Content-Disposition response header
        ## Indicates if content expects to be displayed inline or as attachment.
        ##
        ## Example: `inline` or `attachment; filename="filename.jpg"`
        disposition : List(U8),

        ## Content-Type header
        ## Original media type of the resource.
        ##
        ## Example: `multipart/form-data; boundary=ExampleBoundaryString`
        type : List(U8),

        ## Content-Transfer-Encoding
        ## Specifies how the body is encoded.
        ##
        ## Example: `base64` or `binary`
        encoding : List(U8),

        ## Actual data that was entered in the form, in encoded form.
        data : List(U8),
    }

    newline = ['\r', '\n']
    doubledash = ['-', '-']

    ## Produces function that extracts the header value.
    parse_content_f = |{ upper, lower }|
        |bytes| {
            to_search_upper = List.concat(newline, upper)
            to_search_lower = List.concat(newline, lower)
            search_length = List.len(to_search_upper)
            after_search = List.sublist(bytes, { start: search_length, len: List.len(bytes) })

            if List.starts_with(bytes, to_search_upper) or List.starts_with(bytes, to_search_lower) {
                match List.find_first_index(after_search, |b| b == '\r') {
                    Ok(next_line_start) =>
                        Ok({
                            value: List.sublist(after_search, { start: 0, len: next_line_start }),
                            rest: List.sublist(after_search, { start: next_line_start, len: List.len(after_search) }),
                        })

                    Err(_) => Err(ExpectedContent)
                }
            } else {
                Err(ExpectedContent)
            }
        }

    parse_content_disposition_f = parse_content_f({
        upper: Str.to_utf8("Content-Disposition:"),
        lower: Str.to_utf8("content-disposition:"),
    })

    parse_content_type_f = parse_content_f({
        upper: Str.to_utf8("Content-Type:"),
        lower: Str.to_utf8("content-type:"),
    })

    parse_content_transfer_encoding_f = parse_content_f({
        upper: Str.to_utf8("Content-Transfer-Encoding:"),
        lower: Str.to_utf8("content-transfer-encoding:"),
    })

    ## Parses all headers: Content-Disposition, Content-Type and Content-Transfer-Encoding.
    parse_all_headers : List(U8) -> Try(FormData, _)
    parse_all_headers = |bytes| {
        double_newline_length = 4 # \r\n\r\n

        match parse_content_disposition_f(bytes) {
            Err(err) => Err(ExpectedContentDisposition(bytes, err))
            Ok({ value: disposition, rest: first }) =>
                match parse_content_type_f(first) {
                    Err(_) =>
                        Ok({
                            disposition: disposition,
                            type: [],
                            encoding: [],
                            data: List.drop_first(first, double_newline_length),
                        })

                    Ok({ value: type, rest: second }) =>
                        match parse_content_transfer_encoding_f(second) {
                            Err(_) =>
                                Ok({
                                    disposition: disposition,
                                    type: type,
                                    encoding: [],
                                    data: List.drop_first(second, double_newline_length),
                                })

                            Ok({ value: encoding, rest: rest }) =>
                                Ok({
                                    disposition: disposition,
                                    type: type,
                                    encoding: encoding,
                                    data: List.drop_first(rest, double_newline_length),
                                })
                        }
                }
        }
    }

    ## Parses the body of a multipart/form-data request.
    parse_form_data : { body : List(U8), boundary : List(U8) } -> Try(List(FormData), [ExpectedEnclosedByBoundary])
    parse_form_data = |{ body, boundary }| {
        start_marker = List.concat(doubledash, boundary)
        end_marker = List.concat(List.concat(List.concat(List.concat(newline, doubledash), boundary), doubledash), newline)
        boundary_with_prefix = List.concat(List.concat(newline, doubledash), boundary)

        is_enclosed_by_boundary =
            List.starts_with(body, start_marker)
            and List.ends_with(body, end_marker)

        if is_enclosed_by_boundary {
            parts =
                SplitList.split_on_list(List.drop_first(body, List.len(start_marker)), boundary_with_prefix)
                    .drop_if(|part| part == doubledash)

            Ok(keep_oks(parts, parse_all_headers))
        } else {
            Err(ExpectedEnclosedByBoundary)
        }
    }

    ## Helper: apply a fallible function to each element, keeping only the `Ok` results.
    keep_oks = |list, f|
        List.fold(list, [], |acc, elem|
            match f(elem) {
                Ok(v) => List.append(acc, v)
                Err(_) => acc
            })

    ## Parse URL-encoded form values (`todo=foo&status=bar`) into a Dict (`("todo", "foo"), ("status", "bar")`).
    parse_form_url_encoded : List(U8) -> Try(Dict(Str, Str), [BadUtf8])
    parse_form_url_encoded = |bytes|
        url_encoded_help(bytes, ParsingKey, [], [], Dict.empty())

    # If the bytes are valid UTF-8, run `try_fun` on the resulting Str; otherwise BadUtf8.
    chain_utf8 = |bytes_list, try_fun|
        match Str.from_utf8(bytes_list) {
            Ok(s) => try_fun(s)
            Err(_) => Err(BadUtf8)
        }

    url_encoded_help = |bytes_remaining, state, key, chomped, dict| {
        tail = List.drop_first(bytes_remaining, 1)

        match bytes_remaining {
            [] if List.is_empty(chomped) => Ok(dict)
            [] =>
                # chomped last value
                chain_utf8(key, |key_str|
                    chain_utf8(chomped, |value_str|
                        Ok(Dict.insert(dict, key_str, value_str))))

            ['=', ..] => url_encoded_help(tail, ParsingValue, chomped, [], dict) # put chomped into key
            ['&', ..] =>
                chain_utf8(key, |key_str|
                    chain_utf8(chomped, |value_str|
                        url_encoded_help(tail, ParsingKey, [], [], Dict.insert(dict, key_str, value_str))))

            ['+', ..] =>
                # '+' is a space in application/x-www-form-urlencoded payloads
                url_encoded_help(tail, state, key, List.append(chomped, ' '), dict)

            ['%', second_byte, third_byte, ..] => {
                hex = hex_to_dec(second_byte) * 16 + hex_to_dec(third_byte)
                url_encoded_help(List.drop_first(tail, 2), state, key, List.append(chomped, hex), dict)
            }

            [first_byte, ..] => url_encoded_help(tail, state, key, List.append(chomped, first_byte), dict)
        }
    }

    hex_bytes_to_u32 : List(U8) -> U32
    hex_bytes_to_u32 = |bytes|
        List.fold(bytes, 0, |accum, byte| accum * 16 + hex_to_dec(byte).to_u32())

    hex_to_dec : U8 -> U8
    hex_to_dec = |byte|
        match byte {
            '0' => 0
            '1' => 1
            '2' => 2
            '3' => 3
            '4' => 4
            '5' => 5
            '6' => 6
            '7' => 7
            '8' => 8
            '9' => 9
            'A' => 10
            'B' => 11
            'C' => 12
            'D' => 13
            'E' => 14
            'F' => 15
            _ => {
                crash "Impossible error: the `match` block I'm in should have matched before reaching the catch-all `_`."
            }
        }

    ## For HTML forms that include files or large amounts of text.
    ##
    ## See usage in examples/form-file-upload.roc
    parse_multipart_form_data : { headers : List(InternalHttp.Header), body : List(U8) } -> Try(List(FormData), [InvalidMultipartFormData, ExpectedContentTypeHeader, InvalidContentTypeHeader])
    parse_multipart_form_data = |args| {
        boundary = decode_multipart_form_data_boundary(args.headers)?
        parse_form_data({ body: args.body, boundary: boundary }).map_err(|_| InvalidMultipartFormData)
    }

    ## Extracts the boundary value from the list of HTTP headers.
    ## The boundary is a special string used to separate different parts of the form data.
    decode_multipart_form_data_boundary : List((Str, Str)) -> Try(List(U8), _)
    decode_multipart_form_data_boundary = |headers| {
        content_type = List.keep_if(headers, |(name, _)| name == "Content-Type" or name == "content-type")

        match List.first(content_type) {
            Err(ListWasEmpty) => Err(ExpectedContentTypeHeader)
            Ok((_, value)) =>
                match split_last_str(value, "=") {
                    Ok({ before: _, after }) => Ok(Str.to_utf8(after))
                    Err(NotFound) => Err(InvalidContentTypeHeader)
                }
        }
    }

    # Internal helper: like the old `Str.split_last`.
    split_last_str : Str, Str -> Try({ before : Str, after : Str }, [NotFound])
    split_last_str = |s, delim| {
        parts = Str.split_on(s, delim)
        n = List.len(parts)
        if n <= 1 {
            Err(NotFound)
        } else {
            before_parts = List.sublist(parts, { start: 0, len: n - 1 })
            match List.last(parts) {
                Ok(after) => Ok({ before: Str.join_with(before_parts, delim), after: after })
                Err(_) => Err(NotFound)
            }
        }
    }
}

expect {
    input = Str.to_utf8("\r\nContent-Disposition: form-data; name=\"sometext\"\r\nSome text here...")
    actual = MultipartFormData.parse_content_disposition_f(input)
    expected = Ok({
        value: Str.to_utf8(" form-data; name=\"sometext\""),
        rest: Str.to_utf8("\r\nSome text here..."),
    })

    actual == expected
}

expect {
    input = Str.to_utf8("\r\ncontent-type: multipart/mixed; boundary=abcde\r\nSome text here...")
    actual = MultipartFormData.parse_content_type_f(input)
    expected = Ok({
        value: Str.to_utf8(" multipart/mixed; boundary=abcde"),
        rest: Str.to_utf8("\r\nSome text here..."),
    })

    actual == expected
}

expect {
    input = Str.to_utf8("\r\nContent-Transfer-Encoding: binary\r\nSome text here...")
    actual = MultipartFormData.parse_content_transfer_encoding_f(input)
    expected = Ok({
        value: Str.to_utf8(" binary"),
        rest: Str.to_utf8("\r\nSome text here..."),
    })

    actual == expected
}

expect {
    header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\n\r\n<FILE CONTENTS>"
    actual = MultipartFormData.parse_all_headers(Str.to_utf8(header))
    expected = Ok({
        disposition: Str.to_utf8(" form-data; name=\"sometext\""),
        type: Str.to_utf8(""),
        encoding: Str.to_utf8(""),
        data: Str.to_utf8("<FILE CONTENTS>"),
    })

    actual == expected
}

expect {
    header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\n\r\n<FILE CONTENTS>"
    actual = MultipartFormData.parse_all_headers(Str.to_utf8(header))
    expected = Ok({
        disposition: Str.to_utf8(" form-data; name=\"sometext\""),
        type: Str.to_utf8(" multipart/mixed; boundary=abcde"),
        encoding: Str.to_utf8(""),
        data: Str.to_utf8("<FILE CONTENTS>"),
    })

    actual == expected
}

expect {
    header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\nContent-Transfer-Encoding: binary\r\n\r\n<FILE CONTENTS>"
    actual = MultipartFormData.parse_all_headers(Str.to_utf8(header))
    expected = Ok({
        disposition: Str.to_utf8(" form-data; name=\"sometext\""),
        type: Str.to_utf8(" multipart/mixed; boundary=abcde"),
        encoding: Str.to_utf8(" binary"),
        data: Str.to_utf8("<FILE CONTENTS>"),
    })

    actual == expected
}

expect {
    input = Str.to_utf8("--12345\r\nContent-Disposition: form-data; name=\"sometext\"\r\n\r\nsome text sent via post...\r\n--12345--\r\n")
    actual = MultipartFormData.parse_form_data({
        body: input,
        boundary: Str.to_utf8("12345"),
    })
    expected = Ok([
        {
            disposition: Str.to_utf8(" form-data; name=\"sometext\""),
            type: [],
            encoding: [],
            data: Str.to_utf8("some text sent via post..."),
        },
    ])

    actual == expected
}

expect {
    body = Str.to_utf8("--AaB03x\r\nContent-Disposition: form-data; name=\"submit-name\"\r\n\r\nLarry\r\n--AaB03x\r\nContent-Disposition: form-data; name=\"files\"\r\nContent-Type: multipart/mixed; boundary=BbC04y\r\n\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file1.txt\"\r\nContent-Type: text/plain\r\n\r\n... contents of file1.txt ...\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file2.gif\"\r\nContent-Type: image/gif\r\nContent-Transfer-Encoding: binary\r\n\r\n...contents of file2.gif...\r\n--BbC04y--\r\n--AaB03x--\r\n")
    boundary = Str.to_utf8("AaB03x")
    actual = MultipartFormData.parse_form_data({ body: body, boundary: boundary })
    expected = Ok([
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
    ])

    actual == expected
}

expect MultipartFormData.hex_bytes_to_u32(['2', '0']) == 32

expect {
    bytes = Str.to_utf8("todo=foo&status=bar")
    expected = Dict.from_list([("todo", "foo"), ("status", "bar")])

    MultipartFormData.parse_form_url_encoded(bytes) == Ok(expected)
}

expect {
    bytes = Str.to_utf8("task=asdfs%20adf&status=qwerwe")
    expected = Dict.from_list([("task", "asdfs adf"), ("status", "qwerwe")])

    MultipartFormData.parse_form_url_encoded(bytes) == Ok(expected)
}

expect MultipartFormData.hex_bytes_to_u32(['0', '0', '0', '0']) == 0
expect MultipartFormData.hex_bytes_to_u32(['0', '0', '0', '1']) == 1
expect MultipartFormData.hex_bytes_to_u32(['0', '0', '0', 'F']) == 15
expect MultipartFormData.hex_bytes_to_u32(['0', '0', '1', '0']) == 16
expect MultipartFormData.hex_bytes_to_u32(['0', '0', 'F', 'F']) == 255
expect MultipartFormData.hex_bytes_to_u32(['0', '1', '0', '0']) == 256
expect MultipartFormData.hex_bytes_to_u32(['0', 'F', 'F', 'F']) == 4095
expect MultipartFormData.hex_bytes_to_u32(['1', '0', '0', '0']) == 4096
expect MultipartFormData.hex_bytes_to_u32(['1', '6', 'F', 'F', '1']) == 94193

expect MultipartFormData.hex_to_dec('0') == 0
expect MultipartFormData.hex_to_dec('F') == 15
