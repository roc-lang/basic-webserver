app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.File
import pf.Http
import http.Response

# To run this example: check the root README.md

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    match File.read_utf8!("examples/file-read.roc") {
        Ok(contents) => Ok(Response.from_status(200).with_body(Str.to_utf8(contents)))
        Err(err) => Err(ServerErr("Failed to read file: ${Str.inspect(err)}"))
    }
