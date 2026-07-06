app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Http
import pf.MultipartFormData
import http.Response

# To run this example: check the root README.md

program = { init!, respond! }

Model : {}

init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})

upload_form : Http.Response
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
        ),
    )

display_uploaded_image! : Http.Request => Try(Http.Response, [ServerErr(Str), ..])
display_uploaded_image! = |req| {
    parts =
        MultipartFormData.parse_multipart_form_data({
            headers: req.headers(),
            body: req.body(),
        })
        ? |err| ServerErr("Failed to parse multipart form-data: ${Str.inspect(err)}")

    match List.first(parts) {
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
                )

            Ok(
                Response.from_status(200)
                .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
                .with_body(page),
            )
        }

        Err(_) =>
            Ok(Response.from_status(400).with_body(Str.to_utf8("No file part found.")))
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, _|
    match req.method() {
        GET => Ok(upload_form)
        POST => display_uploaded_image!(req)
        _ => Ok(Response.from_status(405))
    }

base64_encode : List(U8) -> Str
base64_encode = |bytes|
    match Str.from_utf8(base64_bytes(bytes, [])) {
        Ok(str) => str
        Err(_) => ""
    }

base64_alphabet : List(U8)
base64_alphabet = Str.to_utf8("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

base64_bytes : List(U8), List(U8) -> List(U8)
base64_bytes = |remaining, out|
    match remaining {
        [] => out

        [a] =>
            List.concat(out, base64_quad(a, 0, 0, 1))

        [a, b] =>
            List.concat(out, base64_quad(a, b, 0, 2))

        [a, b, c, ..] =>
            base64_bytes(List.drop_first(remaining, 3), List.concat(out, base64_quad(a, b, c, 3)))
    }

base64_quad : U8, U8, U8, U64 -> List(U8)
base64_quad = |a, b, c, byte_count| {
    bits = a.to_u64() * 65_536 + b.to_u64() * 256 + c.to_u64()
    first = base64_byte(bits // 262_144)
    second = base64_byte((bits // 4_096) % 64)
    third = base64_byte((bits // 64) % 64)
    fourth = base64_byte(bits % 64)

    if byte_count == 1 {
        [first, second, '=', '=']
    } else if byte_count == 2 {
        [first, second, third, '=']
    } else {
        [first, second, third, fourth]
    }
}

base64_byte : U64 -> U8
base64_byte = |index|
    match base64_alphabet.get(index) {
        Ok(byte) => byte
        Err(_) => 'A'
    }

## `base64_encode` handles padding.
expect {
    base64_encode(Str.to_utf8("")) == ""
        and base64_encode(Str.to_utf8("f")) == "Zg=="
        and base64_encode(Str.to_utf8("fo")) == "Zm8="
        and base64_encode(Str.to_utf8("foo")) == "Zm9v"
}
