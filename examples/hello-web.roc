app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Http
import pf.Stdout
import pf.Utc
import http.Response

# To run this example: check the root README.md

# Model is produced by `init!`.
Model : {}

program = { init!, respond! }

# With `init!` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`, etc.
# In this case we don't have anything to initialize, so it is just `Ok({})`.
init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |request, _model| {
    datetime = Utc.to_iso_8601(Utc.now!())

    Stdout.line!("${datetime} ${Str.inspect(request.method())} ${request.uri()}")
        ? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

    Ok(Response.from_status(200).with_body(Str.to_utf8("<b>Hello from server</b></br>")))
}
