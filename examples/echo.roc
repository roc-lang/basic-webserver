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
	time = (Time.unix_epoch + UnixTime.now!().seconds_since_epoch()).iso8601()

	Stdout.line!("${time} ${Str.inspect(req.method())} ${Str.inspect(req.target())}")
		? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

	match header_value(req.headers(), "x-request-info") {
		Present("describe") => return Ok(request_info_response(req))
		Present("escape-path") =>
			match req.target() {
				Resource({ raw_path, .. }) =>
					return Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(raw_path))))
				_ => {}
			}
		Present("escape-authority") =>
			match req.authority() {
				Present(authority) =>
					return Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(authority.host()))))
				Absent => {}
			}
		_ => {}
	}

	raw_path =
		match req.target() {
			Resource({ raw_path: path, .. }) => path
			_ => ""
		}
	body = if raw_path == "/first-chunk" {
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

request_info_response : Server.Request -> Server.Outcome
request_info_response = |request| {
	target = request.target()
	target_text =
		match target {
			Resource({ raw_path, raw_query }) => {
				query_text =
					match raw_query {
						Absent => "absent"
						Present(query) => "present:${query}"
					}
				"target=resource\npath=${raw_path}\nquery=${query_text}"
			}
			Authority(authority) => "target=authority\n${authority_text(authority)}"
			Asterisk => "target=asterisk"
		}
	effective_text =
		match request.authority() {
			Absent => "authority=absent"
			Present(authority) => authority_text(authority)
		}
	status =
		match target {
			Authority(_) => 400
			_ => 200
		}
	body = "${target_text}\n${effective_text}"
	Server.respond(Response.from_status(status).with_body(Str.to_utf8(body)))
}

authority_text : Server.Authority -> Str
authority_text = |authority| {
	port_text =
		match authority.port() {
			Absent => "absent"
			Present(port) => "present:${port.to_str()}"
		}
	"authority=present\nhost=${authority.host()}\nport=${port_text}"
}

header_value : List({ name : Str, value : Str }), Str -> [Absent, Present(Str)]
header_value = |headers, wanted|
	match headers {
		[] => Absent
		[{ name, value }, .. as rest] =>
			if name == wanted {
				Present(value)
			} else {
				header_value(rest, wanted)
			}
		}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
