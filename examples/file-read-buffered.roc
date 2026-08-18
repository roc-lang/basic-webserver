## Reads `LICENSE` incrementally and serves its line and byte counts.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	roc: "nightly-2026-08-13-2fdd90e",
}

import pf.File
import pf.Path
import pf.Server
import http.Response

Context : ReadSummary

ReadSummary : {
	lines_read : U64,
	bytes_read : U64,
}

program = { init!, respond!, shutdown! }

init! : () => Try(
	{ config : Server.Config, context : Context },
	[Exit(I64), FailedToOpenLicense(_), FailedToReadLicense(_), ..],
)
init! = || {
	reader = File.open_reader!(Path.utf8("LICENSE")) ? |err| FailedToOpenLicense(err)
	summary = process_line!(reader, { lines_read: 0, bytes_read: 0 }) ? |err| FailedToReadLicense(err)

	Ok({ config: Server.default_config, context: summary })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, summary|
	Ok(
		Server.respond(
			Response.from_status(200).with_body(
				Str.to_utf8("{bytes_read: ${summary.bytes_read.to_str()}, lines_read: ${summary.lines_read.to_str()}}"),
			),
		),
	)

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})

## Recursively read one bounded line at a time, accumulating line and byte counts.
process_line! : File.Reader, ReadSummary => Try(ReadSummary, _)
process_line! = |reader, { lines_read, bytes_read }|
	match reader.read_line!() {
		Ok(bytes) if bytes.len() == 0 =>
			Ok({ lines_read, bytes_read })

		Ok(bytes) =>
			process_line!(
				reader,
				{
					lines_read: lines_read + 1,
					bytes_read: bytes_read + bytes.len(),
				},
			)

		Err(err) => Err(err)
	}
