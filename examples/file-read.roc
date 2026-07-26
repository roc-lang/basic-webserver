## Reads this example's UTF-8 source during initialization and serves it over HTTP.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.14.0-rc1/GfM5qZLcKYGA9XD4V7u1S4RjWrdfws29Uz2m86C7bmUC.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Path
import pf.Server
import http.Response

Context : Str

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), FailedToReadSource(_), ..])
init! = || {
	contents = Path.read_utf8!(Path.utf8("examples/file-read.roc")) ? |err| FailedToReadSource(err)
	Ok({ config: Server.default_config, context: "Source code of current program:\n\n${contents}" })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, contents|
	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(contents))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
