## Parses a bounded multipart form upload and previews an uploaded PNG image.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Base64
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
					img = Base64.encode(part.data)
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
