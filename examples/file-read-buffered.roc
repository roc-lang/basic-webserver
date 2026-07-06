app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.File
import pf.Http
import http.Response

# To run this example: check the root README.md

Model : ReadSummary

ReadSummary : {
    lines_read : U64,
    bytes_read : U64,
}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || {
    reader = File.open_reader!("LICENSE") ? |_| Exit(1)
    summary = process_line!(reader, { lines_read: 0, bytes_read: 0 }) ? |_| Exit(1)

    Ok(summary)
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_, model|
    Ok(Response.from_status(200).with_body(Str.to_utf8(Str.inspect(model))))

## Count the number of lines and bytes read.
process_line! : File.Reader, ReadSummary => Try(ReadSummary, _)
process_line! = |reader, { lines_read, bytes_read }|
    match File.read_line!(reader) {
        Ok(bytes) if bytes.len() == 0 =>
            Ok({ lines_read, bytes_read })

        Ok(bytes) =>
            process_line!(
                reader,
                {
                    lines_read: lines_read + 1,
                    bytes_read: bytes_read + bytes.len(),
                },
            )

        Err(err) => Err(err)
    }
