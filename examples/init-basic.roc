app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Http
import pf.Utc
import http.Response

# To run this example: check the root README.md

# Model is produced by `init!`.
Model : Str

program = { init!, respond! }

# With `init!` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`,...
# In this example it is just `Ok("🎁")`.
init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok("🎁")

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, model| {
    # Log request time (millis since epoch), method and url
    millis = Utc.to_millis_since_epoch(Utc.now!())

    Stdout.line!("${millis.to_str()} ${Str.inspect(req.method())} ${req.uri()}")
        ? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

    Ok(Response.from_status(200).with_body(Str.to_utf8("<b>init gave me ${model}</b>")))
}
