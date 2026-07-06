app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Http
import pf.Sleep
import pf.Stdout
import http.Response

# To run this example: check the root README.md

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_, _| {
    Stdout.line!("Sleeping for 1 second...")
        ? |err| ServerErr("Failed to write to stdout: ${Str.inspect(err)}")
    Sleep.millis!(1000)

    Ok(Response.from_status(200).with_body(Str.to_utf8("Response delayed by 1 second")))
}
