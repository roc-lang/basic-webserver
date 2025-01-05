app [Model, init!, respond!] {
    pf: platform "../platform/main.roc",
    utils: "https://github.com/quelgar/roc-utils/releases/download/v0.1.0/keYHFjUG1pMAT8ECePEAIS-ncYxEV0DdhTvENUf0USs.tar.br",
}

import utils.Base64
import pf.Http exposing [Request, Response]
import pf.MultipartFormData

# Model is produced by `init`.
Model : {}

init! : {} => Result Model []
init! = \{} -> Ok({})

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = \req, _ ->
    if req.method == GET then
        body =
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
            """
            |> Str.to_utf8

        Ok({
            status: 200,
            headers: [
                { name: "Content-Type", value: "text/html" },
            ],
            body,
        })
    else if req.method == POST then
        page = \src ->
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
                            background-image: url('data:image/png;base64,$(src)');
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
            """
            |> Str.to_utf8

        maybe_image =
            { headers: req.headers, body: req.body }
            |> MultipartFormData.parse_multipart_form_data
            |> Result.try(List.first)
            |> Result.map(.data)
            |> Result.map(Base64.encode)

        when maybe_image is
            Ok(img) ->
                Ok({
                    status: 200,
                    headers: [
                        { name: "Content-Type", value: "text/html" },
                    ],
                    body: page(img),
                })

            Err(err) -> Ok({ status: 500, headers: [], body: err |> Inspect.to_str |> Str.to_utf8 })
    else
        Ok({ status: 500, headers: [], body: [] })
