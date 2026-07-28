## Echo server: logs the request method and target, then replies with the request body.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	gregorian: "https://cdn.jasperwoudenberg.com/roc-gregorian-v1.0.0-rc.2/Ce3xuHN92F5oGRuzjUTmm65jULAEj8pvvrTBmZJzE1M4.tar.zst",
}

import pf.Server
import pf.Stdout
import pf.UnixTime
import http.Response
import gregorian.Time

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, _context| {
	time = (Time.unix_epoch + UnixTime.now!().seconds_since_epoch()).iso8601()

	Stdout.line!("${time} ${Str.inspect(req.method())} ${req.target()}")
		? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")
	body = if req.target() == "/first-chunk" {
		match req.body().with_limit(64 * 1024).read!() {
			Ok(Chunk(chunk)) => chunk
			Ok(End) => []
			Err(err) => return Err(ServerErr("Failed to read request body: ${Str.inspect(err)}"))
		}
	} else {
		req.body().with_limit(64 * 1024).read_all!()
			? |err| ServerErr("Failed to read request body: ${Str.inspect(err)}")
	}
	Ok(Server.respond(Response.from_status(200).with_body(body)))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
