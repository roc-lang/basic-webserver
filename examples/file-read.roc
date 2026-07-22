app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Path
import pf.Http
import http.Response

# To run this example: check the root README.md

Model : Str

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match Path.read_utf8!(Path.utf8("examples/file-read.roc")) {
        Ok(contents) => Ok("Source code of current program:\n\n${contents}")
        Err(_) => Err(Exit(1))
    }

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, model|
    Ok(Response.from_status(200).with_body(Str.to_utf8(model)))
