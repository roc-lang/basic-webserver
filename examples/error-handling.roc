# This example demonstrates error handling and fetching content from another website.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Http
import pf.Server
import pf.Url
import pf.Env
import pf.Utc
import http.Response

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
	# Log the method and url to stdout
	log_request!(req)?

	# Fetch content of url
	content = fetch_content!(target_url)?

	# Respond with the website content
	Ok(response_with_code(200, content))
}

log_request! : Server.Request => Try({}, [FailedToLogRequest(_), ..])
log_request! = |req| {
	datetime = Utc.to_iso_8601(Utc.now!())

	Stdout.line!("${datetime} ${Str.inspect(req.method())} ${req.target()}")
		? |err| FailedToLogRequest(err)
	Ok({})
}

fetch_content! : Url => Try(Str, [FailedToFetch(_), ..])
fetch_content! = |url| Http.get_utf8!(url).map_err(|err| FailedToFetch(err))

# Respond with the given status code and body
response_with_code : U16, Str -> Response
response_with_code = |code, body|
	Response.from_status(code).with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
