app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Http
import pf.MultipartFormData
import http.Response

# To run this example: check the root README.md

# Demonstrates how to handle URL-encoded form data.

program = { init!, respond! }

form_page : Http.Response
form_page = {
    response =
        Response.from_status(200)
        .with_headers(Http.header_tuples([{ name: "Content-Type", value: "text/html" }]))

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
        ),
    )
}

display_form_data! : Http.Request => Try(Http.Response, [ServerErr(Str), ..])
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
        )
    }

    parsed_form = MultipartFormData.parse_form_url_encoded(req.body())

    match parsed_form {
        Ok(form_data) => {
            response =
                Response.from_status(200)
                .with_headers(Http.header_tuples([{ name: "Content-Type", value: "text/html" }]))
                .with_body(page(form_data))
            Ok(response)
        }

        Err(err) => Ok(Response.from_status(500).with_body(Str.to_utf8(Str.inspect(err))))
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, _model|
    match req.method() {
        GET => Ok(form_page)
        POST => display_form_data!(req)
        _ => Ok(Response.from_status(500))
    }

# Model is produced by `init!`.
Model : {}

init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})
