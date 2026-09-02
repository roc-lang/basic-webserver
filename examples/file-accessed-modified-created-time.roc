## Reads and serves the accessed, modified, and created timestamps of `LICENSE`.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	gregorian: "https://cdn.jasperwoudenberg.com/roc-gregorian-v1.0.0-rc.3/3R8EMBQy6rYy3vbLY3u4CLcT8qwAPAyxaaGTA18Gknbe.tar.zst",
	roc: "nightly-2026-09-02-d2609e2",
}

import pf.Stdout
import pf.Server
import pf.Path
import pf.UnixTime
import http.Response
import gregorian.Time

Context : Str

program = { init!, respond!, shutdown! }

init! : () => Try(
	{ config : Server.Config, context : Context },
	[
		Exit(I64),
		FailedToPrintFileTimes(_),
		FailedToReadAccessedTime(_),
		FailedToReadCreatedTime(_),
		FailedToReadModifiedTime(_),
		..,
	],
)
init! = || {
	file = Path.utf8("LICENSE")

	time_modified = format_timestamp(Path.time_modified!(file) ? |err| FailedToReadModifiedTime(err))
	time_accessed = format_timestamp(Path.time_accessed!(file) ? |err| FailedToReadAccessedTime(err))
	time_created = format_timestamp(Path.time_created!(file) ? |err| FailedToReadCreatedTime(err))
	summary = "${Path.display(file)} file time metadata:\nModified: ${time_modified}\nAccessed: ${time_accessed}\nCreated: ${time_created}"

	Stdout.line!(summary) ? |err| FailedToPrintFileTimes(err)

	Ok({ config: Server.default_config, context: summary })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, summary|
	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(summary))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})

format_timestamp : UnixTime.Timestamp -> Str
format_timestamp = |timestamp|
	(Time.unix_epoch + timestamp.seconds_since_epoch()).iso8601()
