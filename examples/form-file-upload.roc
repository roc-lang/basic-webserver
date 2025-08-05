app [Model, init!, respond!] {
    pf: platform "../platform/main.roc",
    utils: "https://github.com/lukewilliamboswell/roc-utils/releases/download/0.3.0/w1rWVzjiBSrvc1VHPNX10o0bHI7rmBdT36hFQ0f5R_w.tar.br",
}

import utils.Base64
import pf.Http exposing [Request, Response]
import pf.MultipartFormData

# To run this example: check the README.md in this folder

# Demonstrates how to upload a (image) file.

image_upload_form : Result Response [ServerErr Str]_
image_upload_form =
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
                    <title>Image Upload Form</title>
                </head>
                <body>

                <h2>Upload an Image</h2>

                <form action="/" method="post" enctype="multipart/form-data">
                    <label for="fileToUpload">Select image to upload:</label><br><br>
                    <input type="file" name="fileToUpload" id="fileToUpload" accept="image/*.png"><br><br>
                    <input type="submit" value="Upload .png Image" name="submit">
                </form>

                </body>
                </html>
                """,
            ),
        },
    )

display_uploaded_image! : Request => Result Response [ServerErr Str]_
display_uploaded_image! = |req|
    page = |src|
        Str.to_utf8(
            """
            <!DOCTYPE html>
            <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <title>Embedded Image</title>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        .image-container {
                            height: 200px;
                            background-image: url('data:image/png;base64,${src}');
                            background-repeat: no-repeat;
                            background-size: contain; /*scales the image to fit within the container while maintaining its aspect ratio*/
                            background-position: center;
                        }
                    </style>
                </head>
                <body>
                    <h1>You uploaded:</h1>
                    <div class="image-container"></div>
                </body>
            </html>
            """,
        )

    maybe_image =
        { headers: req.headers, body: req.body }
        |> MultipartFormData.parse_multipart_form_data
        |> Result.try(List.first)
        |> Result.map_ok(.data)
        |> Result.map_ok(Base64.encode)

    when maybe_image is
        Ok(img) ->
            Ok(
                {
                    status: 200,
                    headers: [
                        { name: "Content-Type", value: "text/html" },
                    ],
                    body: page(img),
                },
            )

        Err(err) -> Ok({ status: 500, headers: [], body: Str.to_utf8(Inspect.to_str(err)) })

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |req, _|
    if req.method == GET then
        image_upload_form
    else if req.method == POST then
        display_uploaded_image!(req)
    else
        Ok({ status: 500, headers: [], body: [] })

# Model is produced by `init`.
Model : {}

init! : {} => Result Model []
init! = |{}| Ok({})