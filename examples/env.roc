app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Env
import pf.Http
import http.Response

# To run this example: check the root README.md

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    match Env.var!("HOME") {
        Ok(value) => Ok(Response.from_status(200).with_body(Str.to_utf8("HOME=${value}")))
        Err(VarNotFound(name)) => Ok(Response.from_status(200).with_body(Str.to_utf8("env var not found: ${name}")))
    }
