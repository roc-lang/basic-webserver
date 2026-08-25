## Serves an HTML form and parses bounded URL-encoded form submissions.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	roc: "nightly-2026-08-25-cc03aa8",
}

import pf.Server
import pf.Attribute
import pf.Html
import pf.MultipartFormData
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

form_page : Response
form_page = {
	response =
		Response.from_status(200)
			.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])

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

display_form_data! : Server.Request => Try(Response, [ServerErr(Str), ..])
display_form_data! = |req| {
	body = req.body().with_limit(64 * 1024).read_all!()
		? |err| ServerErr("Failed to read URL-encoded form: ${Str.inspect(err)}")

	match MultipartFormData.parse_form_url_encoded(body) {
		Ok(form_data) => Ok(html_response(200, form_data_page(form_data)))
		Err(_) => Ok(text_response(400, "Malformed URL-encoded form data."))
	}
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, _context|
	match req.method() {
		GET => Ok(Server.respond(form_page))
		POST => Ok(Server.respond(display_form_data!(req)?))
		_ => Ok(Server.respond(Response.from_status(405)))
	}

form_data_page : Dict(Str, Str) -> List(U8)
form_data_page = |form_data| {
	entries =
		Dict.to_list(form_data).map(
			|(key, value)|
				Html.li(
					[],
					[
						Html.element("strong", [], [Html.text("${key}:")]),
						Html.text(" ${value}"),
					],
				),
		)

	page =
		Html.html(
			[],
			[
				Html.head([], [Html.title([], [Html.text("Form Data Received")])]),
				Html.body(
					[],
					[
						Html.h1([], [Html.text("Form Data Received:")]),
						Html.ul([], entries),
						Html.a([Attribute.href("/")], [Html.text("Go back")]),
					],
				),
			],
		)

	Str.to_utf8(Html.render(page))
}

html_response : U16, List(U8) -> Response
html_response = |status, body|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
		.with_body(body)

text_response : U16, Str -> Response
text_response = |status, body|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
		.with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
