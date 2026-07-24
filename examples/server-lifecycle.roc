## Demonstrates initialization, request handling with shared context, and graceful shutdown.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Stdout
import http.Response

Context : Str

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: "lifecycle context" })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, context| {
	if context != "lifecycle context" {
		return Err(ServerErr("Request received unexpected context"))
	}

	response = Response.from_status(200).with_body(Str.to_utf8("context=${context}"))
	Ok(Server.stop_after(response))
}

shutdown! : Server.ShutdownReason,
Context => Try(
	{},
	[Exit(I64), FailedToLogShutdown(_), UnexpectedShutdown({ context : Str, reason : Server.ShutdownReason }), ..],
)
shutdown! = |reason, context|
	match reason {
		ApplicationRequested if context == "lifecycle context" => {
			Stdout.line!("shutdown hook: ApplicationRequested, context: lifecycle context") ? |err| FailedToLogShutdown(err)
			Ok({})
		}
		_ => {
			Err(UnexpectedShutdown({ reason, context }))
		}
	}
