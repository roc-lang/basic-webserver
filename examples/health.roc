## Native liveness and readiness routes backed by a typed host readiness gate.
##
## Probe requests never enter `respond!`, so they remain available while the
## bounded Roc handler pool and queue are occupied.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	roc: "nightly-2026-08-22-db56022",
}

import pf.Env
import pf.Server
import pf.Sleep
import pf.Stdout
import http.Response

Context : { readiness : Server.Readiness }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	readiness = Server.Readiness.create!(NotReady)
		? |_| Exit(1)
	mode =
		match Env.var_str!("HEALTH_CONFIG") {
			Ok(value) => value
			_ => "valid"
		}
	native_routes =
		match mode {
			"duplicate" => {
				files: [],
				liveness: [Server.liveness_route("/health")],
				readiness: [Server.readiness_route({ at: "/health", readiness })],
			}
			"invalid" => {
				files: [],
				liveness: [Server.liveness_route("/live?details=true")],
				readiness: [],
			}
			_ => {
				files: [],
				liveness: [Server.liveness_route("/live")],
				readiness: [Server.readiness_route({ at: "/ready", readiness })],
			}
		}
	config =
		Server.default_config
			.with_limits({
				max_connections: 16,
				max_handlers: 1,
				max_queued_handlers: 1,
			})
			.with_native_routes(native_routes)
	Ok({
		config,
		context: {
			readiness: readiness,
		},
	})
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, context|
	match request.target() {
		Resource({ raw_path: "/set-ready", .. }) => {
			context.readiness.set!(Ready)
				? |err| ServerErr("Failed to become ready: ${Str.inspect(err)}")
			Ok(text_response(200, "ready"))
		}
		Resource({ raw_path: "/set-not-ready", .. }) => {
			context.readiness.set!(NotReady)
				? |err| ServerErr("Failed to become not ready: ${Str.inspect(err)}")
			Ok(text_response(200, "not ready"))
		}
		Resource({ raw_path: "/slow", .. }) => {
			Sleep.millis!(750)
			Ok(text_response(200, "slow response"))
		}
		Resource({ raw_path: "/stop", .. }) =>
			Ok(Server.stop_after(Response.from_status(200).with_body(Str.to_utf8("stopping"))))
		_ => Ok(text_response(404, "not found"))
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, context| {
	result = context.readiness.set!(Ready)
	Stdout.line!("shutdown readiness update: ${Str.inspect(result)}") ?? {}
	Ok({})
}

text_response = |status, body|
	Server.respond(
		Response.from_status(status)
			.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
			.with_body(Str.to_utf8(body)),
	)
