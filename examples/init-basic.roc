app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Stdout
import pf.Http
import pf.Utc
import http.Response

# To run this example: check the README.md in this folder

# Model is produced by `init!`.
Model : Str

program = { init!, respond! }

# With `init!` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`,...
# In this example it is just `Ok("🎁")`.
init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok("🎁")

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, model| {
    # Log request time (millis since epoch), method and url
    millis = Utc.to_millis_since_epoch(Utc.now!({}))

    _ = Stdout.line!("${millis.to_str()} ${Str.inspect(req.method())} ${req.uri()}")

    Ok(Response.from_status(200).with_body(Str.to_utf8("<b>init gave me ${model}</b>")))
}
