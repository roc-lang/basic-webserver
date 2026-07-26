## Demonstrates bounded concurrent handlers with immediate and delayed responses.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.14.0-rc1/GfM5qZLcKYGA9XD4V7u1S4RjWrdfws29Uz2m86C7bmUC.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Sleep
import pf.Stdout
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
	Ok({
		config: Server.with_limits(
			Server.default_config,
			{
				max_connections: 4,
				max_handlers: 2,
				max_queued_handlers: 1,
			},
		),
		context: {},
	})

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context|
	if request.target() == "/fast" {
		Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("Immediate response"))))
	} else {
		Stdout.line!("Sleeping for 1 second...")
			? |err| ServerErr("Failed to write to stdout: ${Str.inspect(err)}")
		Sleep.millis!(1000)

		Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("Response delayed by 1 second"))))
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
