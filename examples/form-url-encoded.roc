app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.MultipartFormData
import http.Response

# To run this example: check the root README.md

# Demonstrates how to handle URL-encoded form data.

form_page : Response.Response
form_page = {
	response = 
		Response.from_status(200)
			.with_headers([{ name: "Content-Type", value: "text/html" }])

	response.with_body(
		Str.to_utf8(
			\\<!DOCTYPE html>
			\\<html>
			\\<head>
			\\    <title>URL-Encoded Form Example</title>
			\\</head>
			\\<body>
			\\
			\\<h2>Submit Form Data</h2>
			\\
			\\<form action="/" method="post" enctype="application/x-www-form-urlencoded">
			\\    <label for="name">Name:</label><br>
			\\    <input type="text" name="name" id="name" required><br><br>
			\\    <label for="email">Email:</label><br>
			\\    <input type="email" name="email" id="email" required><br><br>
			\\    <label for="message">Message:</label><br>
			\\    <textarea name="message" id="message" rows="4" cols="50" required></textarea><br><br>
			\\    <input type="submit" value="Submit">
			\\</form>
			\\
			\\</body>
			\\</html>
			,
		),
	)
}

display_form_data! : Server.Request => Try(Response.Response, [ServerErr(Str), ..])
display_form_data! = |req| {
	page = |form_data| {
		entries = 
			Str.join_with(
				Dict.to_list(form_data).map(|(key, value)| "<li><strong>${key}:</strong> ${value}</li>"),
				"",
			)

		Str.to_utf8(
			\\<!DOCTYPE html>
			\\<html lang="en">
			\\    <head>
			\\        <meta charset="UTF-8">
			\\        <title>Form Data Received</title>
			\\        <meta name="viewport" content="width=device-width, initial-scale=1.0">
			\\    </head>
			\\    <body>
			\\        <h1>Form Data Received:</h1>
			\\        <ul>
			\\            ${entries}
			\\        </ul>
			\\        <a href="/">Go back</a>
			\\    </body>
			\\</html>
			,
		)
	}

	body = req.body().with_limit(64 * 1024).read_all!()
		? |err| ServerErr("Failed to read URL-encoded form: ${Str.inspect(err)}")
	parsed_form = MultipartFormData.parse_form_url_encoded(body)

	match parsed_form {
		Ok(form_data) => {
			response = 
				Response.from_status(200)
					.with_headers([{ name: "Content-Type", value: "text/html" }])
					.with_body(page(form_data))
			Ok(response)
		}

		Err(err) => Ok(Response.from_status(500).with_body(Str.to_utf8(Str.inspect(err))))
	}
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, _state|
	match req.method() {
		GET => Ok(Server.respond(form_page))
		POST => Ok(Server.respond(display_form_data!(req)?))
		_ => Ok(Server.respond(Response.from_status(405)))
	}

# Context is produced by `init!` and shared with every request.
Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
