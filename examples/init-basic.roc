## Initializes shared context once and uses it while logging and responding to requests.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.15.0/HcMFsVT26qeMvqWtG5rfNhVMWjceYbKh1An4uYpheBVW.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	gregorian: "https://cdn.jasperwoudenberg.com/roc-gregorian-v1.0.0-rc.2/Ce3xuHN92F5oGRuzjUTmm65jULAEj8pvvrTBmZJzE1M4.tar.zst",
}

import pf.Stdout
import pf.Server
import pf.UnixTime
import http.Response
import gregorian.Time

# `init!` produces this immutable context once, and every request receives it.
Context : Str

program = { init!, respond!, shutdown! }

# `init!` can validate configuration, run migrations, or prepare immutable
# startup data. Here it stores a gift string in the context.
init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: "🎁" })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, gift| {
	datetime = (Time.unix_epoch + UnixTime.now!().seconds_since_epoch()).iso8601()

	Stdout.line!("${datetime} ${Str.inspect(req.method())} ${Str.inspect(req.target())}")
		? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("<b>init gave me ${gift}</b>"))))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
