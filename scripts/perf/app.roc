app [Context, program] {
	pf: platform "../../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Sleep
import http.Response

# This application exists only for local, indicative performance measurements.
# It deliberately avoids logging and exposes both a minimal handler and a
# hosted-effect paths that synchronously wait for finite timers.

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
	Ok({
		config: Server.with_limits(
			Server.default_config,
			{
				max_connections: 512,
				max_handlers: 64,
				max_queued_handlers: 64,
			},
		),
		context: {},
	})

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context| {
	raw_path =
		match request.target() {
			Resource({ raw_path: path, .. }) => path
			_ => ""
		}
	if raw_path == "/effect" {
		Sleep.millis!(1)
		Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("effect"))))
	} else if raw_path == "/effect-10" {
		Sleep.millis!(10)
		Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("effect-10"))))
	} else if raw_path == "/effect-50" {
		Sleep.millis!(50)
		Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("effect-50"))))
	} else {
		Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("fast"))))
	}
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
