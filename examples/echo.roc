app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Http
import pf.Stdout
import http.Response

# To run this example: check the README.md in this folder

## Echo server: logs the request method/uri and replies with the request body.

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, _model| {
    _ = Stdout.line!("${Str.inspect(req.method())} ${req.uri()}")
    Ok(Response.from_status(200).with_body(req.body()))
}
