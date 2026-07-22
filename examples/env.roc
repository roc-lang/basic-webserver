app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Http
import http.Response

# To run this example: check the root README.md

Model : [DebugPrintMode, NonDebugMode]

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match Env.var!("DEBUG") {
        Ok("1") => Ok(DebugPrintMode)
        _ => Ok(NonDebugMode)
    }

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, model|
    match model {
        DebugPrintMode => {
            Ok(Response.from_status(200).with_body(Str.to_utf8(Str.inspect(Env.dict!()))))
        }
        NonDebugMode => Ok(Response.from_status(200).with_body(Str.to_utf8("DEBUG var not set")))
    }
