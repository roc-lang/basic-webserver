## Demonstrates typed error handling while fetching content from a configured URL.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	gregorian: "https://cdn.jasperwoudenberg.com/roc-gregorian-v1.0.0-rc.3/3R8EMBQy6rYy3vbLY3u4CLcT8qwAPAyxaaGTA18Gknbe.tar.zst",
	roc: "nightly-2026-09-02-d2609e2",
}

import pf.Stdout
import pf.Http
import pf.Server
import pf.Url
import pf.Env
import pf.UnixTime
import http.Response
import gregorian.Time

Context : Url

program = { init!, respond!, shutdown! }

init! : () => Try(
	{ config : Server.Config, context : Context },
	[Exit(I64), InvalidTargetUrl(_), MissingTargetUrl(_), ..],
)
init! = || {
	target = Env.var_str!("TARGET_URL") ? |err| MissingTargetUrl(err)
	target_url = Url.parse(target) ? |err| InvalidTargetUrl(err)
	Ok({ config: Server.default_config, context: target_url })
}

respond! : Server.Request,
Context => Try(
	Server.Outcome,
	[FailedToFetch(_), FailedToLogRequest(_), ServerErr(Str), ..],
)
respond! = |req, target_url| {
	response = handle_req!(req, target_url)?
	Ok(Server.respond(response))
}

## Semantic application errors can flow directly to the platform. The platform
## logs their inspected values and returns a generic HTTP 500 without exposing
## the details to the client.
handle_req! : Server.Request, Url => Try(Response, [FailedToFetch(_), FailedToLogRequest(_), ..])
handle_req! = |req, target_url| {
	# `?` returns early when an effect is `Err`, preserving its typed error tag.
	log_request!(req)?
	content = fetch_content!(target_url)?

	Ok(response_with_code(200, content))
}

log_request! : Server.Request => Try({}, [FailedToLogRequest(_), ..])
log_request! = |req| {
	datetime = (Time.unix_epoch + UnixTime.now!().seconds_since_epoch()).iso8601()

	Stdout.line!("${datetime} ${Str.inspect(req.method())} ${Str.inspect(req.target())}")
		? |err| FailedToLogRequest(err)
	Ok({})
}

fetch_content! : Url => Try(Str, [FailedToFetch(_), ..])
fetch_content! = |url| Http.get_utf8!(url).map_err(|err| FailedToFetch(err))

## Build an in-memory response with the given status and UTF-8 body.
response_with_code : U16, Str -> Response
response_with_code = |code, body|
	Response.from_status(code).with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
