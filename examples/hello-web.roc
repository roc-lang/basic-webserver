app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Http
import http.Response

# To run this example: check the README.md in this folder

# Model is produced by `init!`.
Model : {}

program = { init!, respond! }

# With `init!` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`, etc.
# In this case we don't have anything to initialize, so it is just `Ok({})`.
init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("<b>Hello from server</b></br>")))
