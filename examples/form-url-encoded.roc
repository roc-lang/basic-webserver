app [Model, init!, respond!] {
    pf: platform "../platform/main.roc",
}

import pf.Http exposing [Request, Response]
import pf.MultipartFormData

# To run this example: check the README.md in this folder

# Demonstrates how to handle URL-encoded form data.

form_page : Result Response [ServerErr Str]_
form_page =
    Ok(
        {
            status: 200,
            headers: [
                { name: "Content-Type", value: "text/html" },
            ],
            body: Str.to_utf8(
                """
                <!DOCTYPE html>
                <html>
                <head>
                    <title>URL-Encoded Form Example</title>
                </head>
                <body>

                <h2>Submit Form Data</h2>

                <form action="/" method="post" enctype="application/x-www-form-urlencoded">
                    <label for="name">Name:</label><br>
                    <input type="text" name="name" id="name" required><br><br>
                    
                    <label for="email">Email:</label><br>
                    <input type="email" name="email" id="email" required><br><br>
                    
                    <label for="message">Message:</label><br>
                    <textarea name="message" id="message" rows="4" cols="50" required></textarea><br><br>
                    
                    <input type="submit" value="Submit">
                </form>

                </body>
                </html>
                """,
            ),
        },
    )

display_form_data! : Request => Result Response [ServerErr Str]_
display_form_data! = |req|
    page = |form_data|
        entries = 
            form_data
            |> Dict.to_list
            |> List.map(|(key, value)| "<li><strong>$(key):</strong> $(value)</li>")
            |> Str.join_with("")
        
        Str.to_utf8(
            """
            <!DOCTYPE html>
            <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <title>Form Data Received</title>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                </head>
                <body>
                    <h1>Form Data Received:</h1>
                    <ul>
                        $(entries)
                    </ul>
                    <a href="/">Go back</a>
                </body>
            </html>
            """,
        )

    parsed_form =
        MultipartFormData.parse_form_url_encoded(req.body)

    when parsed_form is
        Ok(form_data) ->
            Ok(
                {
                    status: 200,
                    headers: [
                        { name: "Content-Type", value: "text/html" },
                    ],
                    body: page(form_data),
                },
            )

        Err(err) -> Ok({ status: 500, headers: [], body: Str.to_utf8(Inspect.to_str(err)) })

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |req, _|
    if req.method == GET then
        form_page
    else if req.method == POST then
        display_form_data!(req)
    else
        Ok({ status: 500, headers: [], body: [] })

        
# Model is produced by `init`.
Model : {}

init! : {} => Result Model []
init! = |{}| Ok({})