## Demonstrates strict, protocol-independent request metadata budgets.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Server
import pf.Sleep
import pf.Stdout
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	limits =
		match Env.var_str!("INVALID_REQUEST_LIMITS") {
			Ok(_) => { max_target_bytes: 0, max_header_bytes: 256, max_header_fields: 4 }
			Err(_) => { max_target_bytes: 64, max_header_bytes: 256, max_header_fields: 4 }
		}

	Ok({
		config: Server.default_config.with_request_metadata_limits(limits),
		context: {},
	})
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, {}| {
	target =
		match request.target() {
			Resource({ raw_path, .. }) => raw_path
			_ => ""
		}
	if target == "/slow" {
		Sleep.millis!(100)
	}

	Ok(
		Server.respond(
			Response.from_status(200)
				.with_body(Str.to_utf8("accepted ${target}")),
		),
	)
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |reason, {}|
	match reason {
		StartupFailed(detail) => {
			Stdout.line!("startup rejected: ${detail}") ? |_| Exit(1)
			Ok({})
		}
		_ => Ok({})
	}
