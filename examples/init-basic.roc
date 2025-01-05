app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Utc

# Model is produced by `init`.
Model : Str

# With `init` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`,...
# In this example it is just `Ok "🎁"`.
init! : {} => Result Model []
init! = \{} -> Ok("🎁")

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = \req, model ->
    # Log request datetime, method and url
    datetime = Utc.to_iso_8601(Utc.now!({}))

    Stdout.line!("$(datetime) $(Inspect.to_str(req.method)) $(req.uri)")?

    Ok({ status: 200, headers: [], body: Str.to_utf8("<b>init gave me $(model)</b>") })
