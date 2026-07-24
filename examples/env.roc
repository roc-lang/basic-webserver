app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Server
import http.Response

# To run this example: check the root README.md

Context : [DebugPrintMode, NonDebugMode]

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
	match Env.var_str!("DEBUG") {
		Ok("1") => Ok({ config: Server.default_config, context: DebugPrintMode })
		_ => Ok({ config: Server.default_config, context: NonDebugMode })
	}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, mode|
	match mode {
		DebugPrintMode => {
			Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(Str.inspect(Env.dict!())))))
		}
		NonDebugMode => Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("DEBUG var not set"))))
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
