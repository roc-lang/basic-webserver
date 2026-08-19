## Lists the entries in the examples directory and serves the listing over HTTP.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	roc: "nightly-2026-08-18-e9be50a",
}

import pf.Stdout
import pf.Server
import pf.Path
import http.Response

Context : Str

program = { init!, respond!, shutdown! }

init! : () => Try(
	{ config : Server.Config, context : Context },
	[Exit(I64), FailedToListExamples(_), FailedToPrintExamples(_), ..],
)
init! = || {

	paths = Path.list!(Path.utf8("examples")) ? |err| FailedToListExamples(err)
	paths_str = Str.join_with(paths.map(Path.display), "\n")

	Stdout.line!("Entries in examples/:\n${paths_str}") ? |err| FailedToPrintExamples(err)

	Ok({ config: Server.default_config, context: paths_str })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, paths_str|
	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(paths_str))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
