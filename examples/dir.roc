app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Env
import pf.Server
import pf.Path
import http.Response

# To run this example: check the root README.md

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, _)
init! = || {
	cwd = Env.cwd!()?
	Stdout.line!("The current working directory is ${Path.display(cwd)}")?

	Env.set_cwd!(Path.utf8("examples/"))?
	Stdout.line!("Set cwd to examples/")?

	paths = Path.list!(Path.utf8("./"))?
	paths_str = Str.join_with(paths.map(Path.display), "\n")
	Stdout.line!("The paths are;\n${paths_str}")?

	Ok({ config: Server.default_config, context: {} })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, _state|
	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("See example in init! function."))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
