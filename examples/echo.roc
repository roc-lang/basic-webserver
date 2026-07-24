app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Stdout
import pf.Utc
import http.Response

# To run this example: check the root README.md

## Echo server: logs the request method/uri and replies with the request body.

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })


respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, _state| {
    time = Utc.to_iso_8601(Utc.now!())

    Stdout.line!("${time} ${Str.inspect(req.method())} ${req.target()}")
        ? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")
    body = req.body().with_limit(64 * 1024).read_all!()
        ? |err| ServerErr("Failed to read request body: ${Str.inspect(err)}")
    Ok(Server.respond(Response.from_status(200).with_body(body)))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
