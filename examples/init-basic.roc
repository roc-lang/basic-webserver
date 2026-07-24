## Initializes shared context once and uses it while logging and responding to requests.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.14.0-rc1/GfM5qZLcKYGA9XD4V7u1S4RjWrdfws29Uz2m86C7bmUC.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Server
import pf.Utc
import http.Response

# `init!` produces this immutable context once, and every request receives it.
Context : Str

program = { init!, respond!, shutdown! }

# `init!` can validate configuration, run migrations, or prepare immutable
# startup data. Here it stores a gift string in the context.
init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: "🎁" })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, gift| {
	datetime = Utc.to_iso_8601(Utc.now!())

	Stdout.line!("${datetime} ${Str.inspect(req.method())} ${req.target()}")
		? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("<b>init gave me ${gift}</b>"))))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
