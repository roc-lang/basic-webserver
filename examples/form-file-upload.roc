## Parses a bounded multipart form upload and previews an uploaded PNG image.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	roc: "nightly-2026-08-19-edec830",
}

import pf.Server
import pf.MultipartFormData
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	config = Server.with_request_body_limit(Server.default_config, 10 * 1024 * 1024)
	Ok({ config, context: {} })
}

upload_form : Response
upload_form =
	Response.from_status(200)
		.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
		.with_body(
			Str.to_utf8(
				\\<!DOCTYPE html>
				\\<html>
				\\<head>
				\\    <title>Image Upload Form</title>
				\\</head>
				\\<body>
				\\    <h2>Upload an Image</h2>
				\\    <form action="/" method="post" enctype="multipart/form-data">
				\\        <label for="fileToUpload">Select image to upload:</label><br><br>
				\\        <input type="file" name="fileToUpload" id="fileToUpload" accept="image/png"><br><br>
				\\        <input type="submit" value="Upload .png Image" name="submit">
				\\    </form>
				\\</body>
				\\</html>
				,
			),
		)

display_uploaded_image! : Server.Request => Try(Response, [ServerErr(Str), ..])
display_uploaded_image! = |req| {
	body = req.body().with_limit(10 * 1024 * 1024).read_all!()
		? |err| ServerErr("Failed to read multipart form-data: ${Str.inspect(err)}")

	match MultipartFormData.parse_multipart_form_data({
		headers: req.headers(),
		body,
	}) {
		Err(_) => Ok(text_response(400, "Malformed multipart form data."))
		Ok(parts) =>
			match parts.find_first(is_png_upload) {
				Ok(part) => {
					img = base64_encode(part.data)
					page =
						Str.to_utf8(
							\\<!DOCTYPE html>
							\\<html lang="en">
							\\    <head>
							\\        <meta charset="UTF-8">
							\\        <title>Embedded Image</title>
							\\        <meta name="viewport" content="width=device-width, initial-scale=1.0">
							\\        <style>
							\\            .image-container {
							\\                height: 200px;
							\\                background-image: url('data:image/png;base64,${img}');
							\\                background-repeat: no-repeat;
							\\                background-size: contain;
							\\                background-position: center;
							\\            }
							\\        </style>
							\\    </head>
							\\    <body>
							\\        <h1>You uploaded:</h1>
							\\        <div class="image-container"></div>
							\\    </body>
							\\</html>
							,
						)

					Ok(
						Response.from_status(200)
							.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
							.with_body(page),
					)
				}

				Err(_) => Ok(text_response(400, "Expected a PNG in the fileToUpload field."))
			}
		}
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, _context|
	match req.method() {
		GET => Ok(Server.respond(upload_form))
		POST => Ok(Server.respond(display_uploaded_image!(req)?))
		_ => Ok(Server.respond(Response.from_status(405)))
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})

png_signature : List(U8)
png_signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

is_png_upload : MultipartFormData.FormData -> Bool
is_png_upload = |part| {
	disposition = Str.from_utf8(part.disposition) ?? ""
	media_type = Str.from_utf8(part.type) ?? ""

	Str.contains(disposition, "name=\"fileToUpload\"")
		and media_type == " image/png"
			and List.starts_with(part.data, png_signature)
}

text_response : U16, Str -> Response
text_response = |status, body|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
		.with_body(Str.to_utf8(body))

base64_encode : List(U8) -> Str
base64_encode = |bytes| Str.from_utf8(base64_bytes(bytes, [])) ?? ""

base64_alphabet : List(U8)
base64_alphabet = Str.to_utf8("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

base64_bytes : List(U8), List(U8) -> List(U8)
base64_bytes = |remaining, out|
	match remaining {
		[] => out

		[a] =>
			out.concat(base64_quad(a, 0, 0, 1))

		[a, b] =>
			out.concat(base64_quad(a, b, 0, 2))

		[a, b, c, ..] =>
			base64_bytes(remaining.drop_first(3), out.concat(base64_quad(a, b, c, 3)))
		}

base64_quad : U8, U8, U8, U64 -> List(U8)
base64_quad = |a, b, c, byte_count| {
	bits = a.to_u64() * 65_536 + b.to_u64() * 256 + c.to_u64()
	first = base64_byte(bits // 262_144)
	second = base64_byte((bits // 4_096) % 64)
	third = base64_byte((bits // 64) % 64)
	fourth = base64_byte(bits % 64)

	match byte_count {
		1 => [first, second, '=', '=']
		2 => [first, second, third, '=']
		_ => [first, second, third, fourth]
	}
}

base64_byte : U64 -> U8
base64_byte = |index| base64_alphabet.get(index) ?? 'A'

# These expectations cover empty input and the one- and two-byte tails that
# require Base64 padding.
expect {
	base64_encode(Str.to_utf8("")) == ""
		and base64_encode(Str.to_utf8("f")) == "Zg=="
			and base64_encode(Str.to_utf8("fo")) == "Zm8="
				and base64_encode(Str.to_utf8("foo")) == "Zm9v"
}
