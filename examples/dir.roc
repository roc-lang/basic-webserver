app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Server
import pf.Path
import http.Response

# To run this example: check the root README.md

Context : Str

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	paths = Path.list!(Path.utf8("examples")) ? |_| Exit(1)
	paths_str = Str.join_with(paths.map(Path.display), "\n")
	Stdout.line!("Entries in examples/:\n${paths_str}") ? |_| Exit(1)

	Ok({ config: Server.default_config, context: paths_str })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, paths_str|
	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(paths_str))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
