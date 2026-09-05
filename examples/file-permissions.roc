## Checks and serves whether `LICENSE` is readable, writable, and executable.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	roc: "nightly-2026-09-04-c125b82",
}

import pf.Stdout
import pf.Server
import pf.Path
import http.Response

Context : Str

program = { init!, respond!, shutdown! }

init! : () => Try(
	{ config : Server.Config, context : Context },
	[
		Exit(I64),
		FailedToCheckExecutable(_),
		FailedToCheckReadable(_),
		FailedToCheckWritable(_),
		FailedToPrintPermissions(_),
		..,
	],
)
init! = || {
	file = Path.utf8("LICENSE")

	is_executable = Path.is_executable!(file) ? |err| FailedToCheckExecutable(err)
	is_readable = Path.is_readable!(file) ? |err| FailedToCheckReadable(err)
	is_writable = Path.is_writable!(file) ? |err| FailedToCheckWritable(err)
	summary = "${Path.display(file)} file permissions:\nExecutable: ${Str.inspect(is_executable)}\nReadable: ${Str.inspect(is_readable)}\nWritable: ${Str.inspect(is_writable)}"

	Stdout.line!(summary) ? |err| FailedToPrintPermissions(err)

	Ok({ config: Server.default_config, context: summary })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, summary|
	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(summary))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
