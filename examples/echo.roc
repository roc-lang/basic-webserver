## Echo server: logs the request method and target, then replies with the request body.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Stdout
import pf.Utc
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
	Ok({
		config: Server.with_timeouts(
			Server.default_config,
			{
				header_ms: 100,
				body_idle_ms: 100,
				keep_alive_idle_ms: 150,
				handler_queue_ms: Server.default_handler_queue_timeout_ms,
				response_idle_ms: Server.default_response_idle_timeout_ms,
			},
		),
		context: {},
	})

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, _context| {
	time = Utc.to_iso_8601(Utc.now!())

	Stdout.line!("${time} ${Str.inspect(req.method())} ${req.target()}")
		? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")
	body = if req.target() == "/first-chunk" {
		match req.body().with_limit(64 * 1024).read!() {
			Ok(Chunk(chunk)) => chunk
			Ok(End) => []
			Err(err) => return Err(ServerErr("Failed to read request body: ${Str.inspect(err)}"))
		}
	} else {
		match req.body().with_limit(64 * 1024).read_all!() {
			Ok(bytes) => bytes
			Err(RequestBodyErr(Timeout)) =>
				return Ok(Server.respond(Response.from_status(408).with_body(Str.to_utf8("Request body timed out"))))
			Err(RequestBodyErr(err)) =>
				return Err(ServerErr("Failed to read request body: ${Str.inspect(err)}"))
			}
	}
	Ok(Server.respond(Response.from_status(200).with_body(body)))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
