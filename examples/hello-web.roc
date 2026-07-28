## Logs each request and responds with a simple HTML greeting.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Stdout
import pf.Utc
import http.Response

# `init!` produces this immutable context once, and every request receives it.
Context : {}

program = { init!, respond!, shutdown! }

# `init!` can validate configuration, run migrations, or prepare immutable
# startup data. This example has no startup data, so its context is `{}`.
init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context| {
	datetime = Utc.to_iso_8601(Utc.now!())

	Stdout.line!("${datetime} ${Str.inspect(request.method())} ${request.target()}")
		? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("<b>Hello from server</b><br>"))))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
