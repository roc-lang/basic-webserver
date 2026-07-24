import SplitList
import http.Header

## Decode bounded HTML form request bodies.
##
## Read a request body through [`Server.Body`](../Server/#Server.Body) with an
## application-appropriate limit before calling these parsers. Multipart values
## remain byte lists so file contents and non-UTF-8 fields are preserved.
##
## ```roc
## body = request.body().with_limit(2 * 1024 * 1024).read_all!()?
## parts = MultipartFormData.parse_multipart_form_data({
##     headers: request.headers(),
##     body,
## })?
## ```
##
## Multipart parsing implements the conventional subset of
## [RFC 7578](https://datatracker.ietf.org/doc/html/rfc7578).
MultipartFormData :: [].{

	## One decoded multipart body part.
	FormData : {

		## Raw Content-Disposition field value, including optional leading
		## whitespace after the colon.
		disposition : List(U8),

		## Raw Content-Type field value, or an empty list when absent.
		type : List(U8),

		## Raw Content-Transfer-Encoding field value, or an empty list when
		## absent. The parser does not decode transfer encodings.
		encoding : List(U8),

		## Raw bytes belonging to this part.
		data : List(U8),
	}

	## Decode an `application/x-www-form-urlencoded` body.
	##
	## Plus signs become spaces and percent escapes are decoded before UTF-8
	## validation. A later duplicate key replaces an earlier value.
	parse_form_url_encoded : List(U8) -> Try(Dict(Str, Str), [BadUtf8, InvalidPercentEncoding])
	parse_form_url_encoded = |body| parse_form_url_encoded_impl(body)

	## Decode a complete `multipart/form-data` body and its request headers.
	parse_multipart_form_data : { headers : List(Header.Header), body : List(U8) } -> Try(List(FormData), [InvalidMultipartFormData, ExpectedContentTypeHeader, InvalidContentTypeHeader])
	parse_multipart_form_data = |request| parse_multipart_form_data_impl(request)
}

ParsedFormData : {

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
		search_length = to_search_upper.len()
		after_search = List.sublist(bytes, { start: search_length, len: bytes.len() })

		if List.starts_with(bytes, to_search_upper) or List.starts_with(bytes, to_search_lower) {
			match List.find_first_index(after_search, |b| b == '\r') {
				Ok(next_line_start) =>
					Ok({
						value: List.sublist(after_search, { start: 0, len: next_line_start }),
						rest: List.sublist(after_search, { start: next_line_start, len: after_search.len() }),
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
parse_all_headers : List(U8) -> Try(ParsedFormData, _)
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
parse_form_data : { body : List(U8), boundary : List(U8) } -> Try(List(ParsedFormData), [ExpectedEnclosedByBoundary, InvalidPart, ..])
parse_form_data = |{ body, boundary }| {
	start_marker = List.concat(doubledash, boundary)
	end_marker = List.concat(List.concat(List.concat(List.concat(newline, doubledash), boundary), doubledash), newline)
	boundary_with_prefix = List.concat(List.concat(newline, doubledash), boundary)

	is_enclosed_by_boundary = List.starts_with(body, start_marker) and List.ends_with(body, end_marker)

	if is_enclosed_by_boundary {
		without_start_marker = List.drop_first(body, start_marker.len())
		parts = SplitList.split_on_list(without_start_marker, boundary_with_prefix).drop_last(1)

		parse_parts(parts, [])
	} else {
		multipart_data_error(Boundary)
	}
}

parse_parts : List(List(U8)), List(ParsedFormData) -> Try(List(ParsedFormData), [ExpectedEnclosedByBoundary, InvalidPart, ..])
parse_parts = |parts, parsed|
	match parts {
		[] => Ok(parsed)
		[first, .. as rest] =>
			match parse_all_headers(first) {
				Ok(part) => parse_parts(rest, List.append(parsed, part))
				Err(_) => multipart_data_error(Part)
			}
		}

multipart_data_error : [Boundary, Part] -> Try(List(ParsedFormData), [ExpectedEnclosedByBoundary, InvalidPart, ..])
multipart_data_error = |kind|
	match kind {
		Boundary => Err(ExpectedEnclosedByBoundary)
		Part => Err(InvalidPart)
	}

## Parse URL-encoded form values (`todo=foo&status=bar`) into a Dict (`("todo", "foo"), ("status", "bar")`).
#
# TODO: Replace the validation pass plus single-error recursive decoder with
# one recursive decoder returning `[BadUtf8, InvalidPercentEncoding]` once the
# optimized backend correctly compiles that recursive error union.
parse_form_url_encoded_impl : List(U8) -> Try(Dict(Str, Str), [BadUtf8, InvalidPercentEncoding])
parse_form_url_encoded_impl = |bytes| {
	if percent_encoding_is_valid(bytes) {
		match url_encoded_help(bytes, ParsingKey, [], [], Dict.empty()) {
			Ok(dict) => Ok(dict)
			Err(BadUtf8) => Err(BadUtf8)
		}
	} else {
		Err(InvalidPercentEncoding)
	}
}

# If the bytes are valid UTF-8, run `try_fun` on the resulting Str; otherwise BadUtf8.
chain_utf8 = |bytes_list, try_fun|
	match Str.from_utf8(bytes_list) {
		Ok(s) => try_fun(s)
		Err(_) => Err(BadUtf8)
	}

insert_form_field = |state, key, value, dict|
	match state {
		ParsingKey =>
			chain_utf8(value, |key_str| Ok(Dict.insert(dict, key_str, "")))
		ParsingValue =>
			chain_utf8(key, |key_str|
				chain_utf8(value, |value_str|
					Ok(Dict.insert(dict, key_str, value_str))))
		}

url_encoded_help = |bytes_remaining, state, key, chomped, dict| {
	tail = List.drop_first(bytes_remaining, 1)

	match bytes_remaining {
		[] if List.is_empty(key) and List.is_empty(chomped) => Ok(dict)
		[] => insert_form_field(state, key, chomped, dict)

		['=', ..] =>
			match state {
				ParsingKey => url_encoded_help(tail, ParsingValue, chomped, [], dict)
				ParsingValue => url_encoded_help(tail, state, key, chomped.append('='), dict)
			}

		['&', ..] => {
			match insert_form_field(state, key, chomped, dict) {
				Ok(next_dict) => url_encoded_help(tail, ParsingKey, [], [], next_dict)
				Err(BadUtf8) => Err(BadUtf8)
			}
		}

		['+', ..] =>
			url_encoded_help(tail, state, key, chomped.append(' '), dict)

		['%', second_byte, third_byte, ..] => {
			hex = hex_to_dec_unchecked(second_byte) * 16 + hex_to_dec_unchecked(third_byte)
			url_encoded_help(List.drop_first(tail, 2), state, key, chomped.append(hex), dict)
		}

		[first_byte, ..] => url_encoded_help(tail, state, key, chomped.append(first_byte), dict)
	}
}

percent_encoding_is_valid : List(U8) -> Bool
percent_encoding_is_valid = |bytes|
	match bytes {
		[] => Bool.True
		['%', second, third, .. as rest] =>
			is_hex_digit(second) and is_hex_digit(third) and percent_encoding_is_valid(rest)
		['%', ..] => Bool.False
		[_, .. as rest] => percent_encoding_is_valid(rest)
	}

is_hex_digit : U8 -> Bool
is_hex_digit = |byte|
	match byte {
		'0'
		| '1'
		| '2'
		| '3'
		| '4'
		| '5'
		| '6'
		| '7'
		| '8'
		| '9'
		| 'A'
		| 'B'
		| 'C'
		| 'D'
		| 'E'
		| 'F'
		| 'a'
		| 'b'
		| 'c'
		| 'd'
		| 'e'
		| 'f' => Bool.True
		_ => Bool.False
	}

hex_bytes_to_u32 : List(U8) -> Try(U32, [InvalidPercentEncoding])
hex_bytes_to_u32 = |bytes| {
	if bytes.all(is_hex_digit) {
		Ok(List.fold(bytes, 0, |accum, byte| accum * 16 + hex_to_dec_unchecked(byte).to_u32()))
	} else {
		Err(InvalidPercentEncoding)
	}
}

hex_to_dec : U8 -> Try(U8, [InvalidPercentEncoding])
hex_to_dec = |byte|
	if is_hex_digit(byte) {
		Ok(hex_to_dec_unchecked(byte))
	} else {
		Err(InvalidPercentEncoding)
	}

hex_to_dec_unchecked : U8 -> U8
hex_to_dec_unchecked = |byte|
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
		'A' | 'a' => 10
		'B' | 'b' => 11
		'C' | 'c' => 12
		'D' | 'd' => 13
		'E' | 'e' => 14
		'F' | 'f' => 15
		_ => 0
	}

## For HTML forms that include files or large amounts of text.
##
## See usage in examples/form-file-upload.roc
parse_multipart_form_data_impl : { headers : List(Header.Header), body : List(U8) } -> Try(List(ParsedFormData), [InvalidMultipartFormData, ExpectedContentTypeHeader, InvalidContentTypeHeader])
parse_multipart_form_data_impl = |args| {
	boundary = decode_multipart_form_data_boundary(args.headers)?
	parse_form_data({ body: args.body, boundary: boundary }).map_err(|_| InvalidMultipartFormData)
}

## Extracts the boundary value from the list of HTTP headers.
## The boundary is a special string used to separate different parts of the form data.
decode_multipart_form_data_boundary : List(Header.Header) -> Try(List(U8), _)
decode_multipart_form_data_boundary = |headers| {
	content_type = headers.keep_if(|{ name, value: _ }| name == "Content-Type" or name == "content-type")

	match List.first(content_type) {
		Err(ListWasEmpty) => Err(ExpectedContentTypeHeader)
		Ok({ name: _, value }) =>
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
	n = parts.len()
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

## `parse_content_disposition_f` extracts a content-disposition header.
expect {
	input = Str.to_utf8("\r\nContent-Disposition: form-data; name=\"sometext\"\r\nSome text here...")
	actual = parse_content_disposition_f(input)
	expected = Ok({
		value: Str.to_utf8(" form-data; name=\"sometext\""),
		rest: Str.to_utf8("\r\nSome text here..."),
	})

	actual == expected
}

## `parse_content_type_f` extracts a content-type header.
expect {
	input = Str.to_utf8("\r\ncontent-type: multipart/mixed; boundary=abcde\r\nSome text here...")
	actual = parse_content_type_f(input)
	expected = Ok({
		value: Str.to_utf8(" multipart/mixed; boundary=abcde"),
		rest: Str.to_utf8("\r\nSome text here..."),
	})

	actual == expected
}

## `parse_content_transfer_encoding_f` extracts a transfer-encoding header.
expect {
	input = Str.to_utf8("\r\nContent-Transfer-Encoding: binary\r\nSome text here...")
	actual = parse_content_transfer_encoding_f(input)
	expected = Ok({
		value: Str.to_utf8(" binary"),
		rest: Str.to_utf8("\r\nSome text here..."),
	})

	actual == expected
}

## `parse_all_headers` handles a part with only content-disposition.
expect {
	header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\n\r\n<FILE CONTENTS>"
	actual = parse_all_headers(Str.to_utf8(header))
	expected = Ok({
		disposition: Str.to_utf8(" form-data; name=\"sometext\""),
		type: Str.to_utf8(""),
		encoding: Str.to_utf8(""),
		data: Str.to_utf8("<FILE CONTENTS>"),
	})

	actual == expected
}

## `parse_all_headers` handles a part with content-disposition and content-type.
expect {
	header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\n\r\n<FILE CONTENTS>"
	actual = parse_all_headers(Str.to_utf8(header))
	expected = Ok({
		disposition: Str.to_utf8(" form-data; name=\"sometext\""),
		type: Str.to_utf8(" multipart/mixed; boundary=abcde"),
		encoding: Str.to_utf8(""),
		data: Str.to_utf8("<FILE CONTENTS>"),
	})

	actual == expected
}

## `parse_all_headers` handles a part with all supported multipart headers.
expect {
	header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\nContent-Transfer-Encoding: binary\r\n\r\n<FILE CONTENTS>"
	actual = parse_all_headers(Str.to_utf8(header))
	expected = Ok({
		disposition: Str.to_utf8(" form-data; name=\"sometext\""),
		type: Str.to_utf8(" multipart/mixed; boundary=abcde"),
		encoding: Str.to_utf8(" binary"),
		data: Str.to_utf8("<FILE CONTENTS>"),
	})

	actual == expected
}

## `parse_form_data` parses a single form-data part.
expect {
	input = Str.to_utf8("--12345\r\nContent-Disposition: form-data; name=\"sometext\"\r\n\r\nsome text sent via post...\r\n--12345--\r\n")
	actual = parse_form_data({
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

## `parse_form_data` preserves nested multipart body content.
expect {
	body = Str.to_utf8("--AaB03x\r\nContent-Disposition: form-data; name=\"submit-name\"\r\n\r\nLarry\r\n--AaB03x\r\nContent-Disposition: form-data; name=\"files\"\r\nContent-Type: multipart/mixed; boundary=BbC04y\r\n\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file1.txt\"\r\nContent-Type: text/plain\r\n\r\n... contents of file1.txt ...\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file2.gif\"\r\nContent-Type: image/gif\r\nContent-Transfer-Encoding: binary\r\n\r\n...contents of file2.gif...\r\n--BbC04y--\r\n--AaB03x--\r\n")
	boundary = Str.to_utf8("AaB03x")
	actual = parse_form_data({ body: body, boundary: boundary })
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

## `parse_form_data` rejects a malformed part instead of silently dropping it.
expect {
	input = Str.to_utf8("--12345\r\nContent-Type: text/plain\r\n\r\nmissing disposition\r\n--12345--\r\n")

	parse_form_data({
		body: input,
		boundary: Str.to_utf8("12345"),
	}) == Err(InvalidPart)
}

## `hex_bytes_to_u32` decodes a two-digit hexadecimal byte.
expect hex_bytes_to_u32(['2', '0']) == Ok(32)

## `parse_form_url_encoded` decodes simple key-value pairs.
expect {
	bytes = Str.to_utf8("todo=foo&status=bar")
	expected = Dict.from_list([("todo", "foo"), ("status", "bar")])

	MultipartFormData.parse_form_url_encoded(bytes) == Ok(expected)
}

## `parse_form_url_encoded` decodes percent-encoded spaces.
expect {
	bytes = Str.to_utf8("task=asdfs%20adf&status=qwerwe")
	expected = Dict.from_list([("task", "asdfs adf"), ("status", "qwerwe")])

	MultipartFormData.parse_form_url_encoded(bytes) == Ok(expected)
}

## `parse_form_url_encoded` keeps percent-encoded literal plus signs.
expect {
	bytes = Str.to_utf8("message=This+%2B+is+a+plus")
	expected = Dict.from_list([("message", "This + is a plus")])

	MultipartFormData.parse_form_url_encoded(bytes) == Ok(expected)
}

## `parse_form_url_encoded` accepts fields without an equals sign.
expect {
	expected = Dict.from_list([("flag", ""), ("empty", "")])

	MultipartFormData.parse_form_url_encoded(Str.to_utf8("flag&empty=")) == Ok(expected)
}

## `parse_form_url_encoded` accepts lowercase percent escapes.
expect {
	expected = Dict.from_list([("operator", "+")])

	MultipartFormData.parse_form_url_encoded(Str.to_utf8("operator=%2b")) == Ok(expected)
}

## `parse_form_url_encoded` reports malformed percent escapes.
expect {
	MultipartFormData.parse_form_url_encoded(Str.to_utf8("value=%GG")) == Err(InvalidPercentEncoding)
		and MultipartFormData.parse_form_url_encoded(Str.to_utf8("value=%2")) == Err(InvalidPercentEncoding)
}

## `hex_bytes_to_u32` decodes zero.
expect hex_bytes_to_u32(['0', '0', '0', '0']) == Ok(0)

## `hex_bytes_to_u32` decodes one.
expect hex_bytes_to_u32(['0', '0', '0', '1']) == Ok(1)

## `hex_bytes_to_u32` decodes fifteen.
expect hex_bytes_to_u32(['0', '0', '0', 'F']) == Ok(15)

## `hex_bytes_to_u32` decodes sixteen.
expect hex_bytes_to_u32(['0', '0', '1', '0']) == Ok(16)

## `hex_bytes_to_u32` decodes 255.
expect hex_bytes_to_u32(['0', '0', 'F', 'F']) == Ok(255)

## `hex_bytes_to_u32` decodes 256.
expect hex_bytes_to_u32(['0', '1', '0', '0']) == Ok(256)

## `hex_bytes_to_u32` decodes 4095.
expect hex_bytes_to_u32(['0', 'F', 'F', 'F']) == Ok(4095)

## `hex_bytes_to_u32` decodes 4096.
expect hex_bytes_to_u32(['1', '0', '0', '0']) == Ok(4096)

## `hex_bytes_to_u32` decodes a five-digit hexadecimal value.
expect hex_bytes_to_u32(['1', '6', 'F', 'F', '1']) == Ok(94193)

## `hex_to_dec` decodes zero.
expect hex_to_dec('0') == Ok(0)

## `hex_to_dec` decodes uppercase hexadecimal F.
expect hex_to_dec('F') == Ok(15)
