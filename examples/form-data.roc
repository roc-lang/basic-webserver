app [Model, server] {
    pf: platform "../platform/main.roc",
    utils: "https://github.com/quelgar/roc-utils/releases/download/v0.1.0/keYHFjUG1pMAT8ECePEAIS-ncYxEV0DdhTvENUf0USs.tar.br",
}

import utils.Base64
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]

# Model is produced by `init`.
Model : {}

# With `init` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`,...
# In this case we don't have anything to initialize, so it is just `Task.ok {}`.

server = { init: Task.ok {}, respond }

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, _ ->

    if req.method == Get then
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
            |> Str.toUtf8

        Task.ok {
            status: 200,
            headers: [
                { name: "Content-Type", value: "text/html" },
            ],
            body,
        }
    else if req.method == Post then
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
                            width: 100%;
                            height: 500px;
                            background-image: url('data:image/png;base64,$(src)');
                            background-repeat: repeat;
                            background-size: auto; /* Keeps the original image size */
                        }
                    </style>
                </head>
                <body>
                    <h1>You uploaded</h1>
                    <div class="image-container"></div>
                </body>
            </html>
            """
            |> Str.toUtf8

        maybeImage =
            { headers: req.headers, body: req.body }
            |> Http.parseMultipartFormData
            |> Result.try List.first
            |> Result.map .data
            |> Result.map Base64.encode

        when maybeImage is
            Ok img ->
                Task.ok {
                    status: 200,
                    headers: [
                        { name: "Content-Type", value: "text/html" },
                    ],
                    body: page img,
                }

            Err err -> Task.ok { status: 500, headers: [], body: err |> Inspect.toStr |> Str.toUtf8 }
    else
        Task.ok { status: 500, headers: [], body: [] }
