app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Http
import pf.Env
import http.Response

# To run this example: check the root README.md

## Returns the default temp dir

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model| {
    temp_dir_str = Env.temp_dir!()

    Ok(Response.from_status(200).with_body(Str.to_utf8("The temp dir path is ${temp_dir_str}")))
}
