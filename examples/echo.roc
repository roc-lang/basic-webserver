app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Http
import pf.Stdout
import http.Response

# To run this example: check the root README.md

## Echo server: logs the request method/uri and replies with the request body.

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, _model| {
    Stdout.line!("${Str.inspect(req.method())} ${req.uri()}")
        ? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")
    Ok(Response.from_status(200).with_body(req.body()))
}
