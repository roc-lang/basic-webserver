# Demo of the basic-webserver outbound HTTP client (Http.send! / Http.get_utf8! / Http.get!).
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Http
import pf.Server
import pf.Url
import http.Request
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

# Fetch some content at startup to demonstrate the outbound HTTP client. To
# exercise it, run a server on localhost:9000 (see the root README); otherwise the
# requests simply report a failure and the webserver still starts.
init! : () => Try({ config : Server.Config, context : Context }, _)
init! = || {
	demo!()?
	Ok({ config: Server.default_config, context: {} })
}

demo! : () => Try({}, _)
demo! = || {
	# GET a plain-text body and decode it as UTF-8.
	match Http.get_utf8!("http://localhost:9000/utf8test") {
		Ok(utf8) => Stdout.line!("I received '${utf8}' from the server.")?
		Err(_) => Stdout.line!("GET /utf8test failed (is a server running on :9000?)")?
	}

	# GET a JSON body and decode it into a Roc record.
	{
		json_result : Try({ foo : Str }, _)
		json_result = Http.get!("http://localhost:9000")

		match json_result {
			Ok(decoded) => Stdout.line!("The json I received was: { foo: \"${decoded.foo}\" }")?
			Err(_) => Stdout.line!("GET / failed (is a JSON server running on :9000?)")?
		}
	}

	# Getting a Response record.
	html_url : Url.Url
	html_url = "http://localhost:9000/htmltest"

	request = 
		Request.from_method(GET)
			.with_uri(Url.to_str(html_url))
			.with_timeout(TimeoutMilliseconds(5000))

	match Http.send!(request) {
		Ok(response) => {
			body_str = Str.from_utf8(response.body())?
			Stdout.line!("Response body:\n\t${body_str}.\n")?
		}
		Err(err) => {
			Stdout.line!("send! failed: ${Str.inspect(err)}")?
		}
	}

	# Same request with a custom Accept header.
	request_2 = 
		Request.from_method(GET)
			.with_uri(Url.to_str(html_url))
			.with_headers([{ name: "Accept", value: "text/html" }])
			.with_timeout(TimeoutMilliseconds(5000))

	match Http.send!(request_2) {
		Ok(response_2) => {
			body_str_2 = Str.from_utf8(response_2.body())?
			Stdout.line!("Response body 2:\n\t${body_str_2}.\n")?
			Ok({})
		}
		Err(err) => {
			Stdout.line!("send! failed: ${Str.inspect(err)}")?
			Ok({})
		}
	}
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |server_request, _state| {
	if server_request.target() == "/limit" {
		request = Request.from_method(GET).with_uri("http://localhost:9000/large")
		config = Http.default_config.with_max_response_bytes(8)

		match Http.send_with!(request, config) {
			Err(HttpErr(ResponseTooLarge(_))) => Ok(text_response("Outbound response was limited."))
			other => Err(ServerErr("Expected ResponseTooLarge, got ${Str.inspect(other)}"))
		}
	} else if server_request.target() == "/timeout" {
		request = Request.from_method(GET).with_uri("http://localhost:9000/slow")
		config = Http.default_config.with_timeout_millis(20)

		match Http.send_with!(request, config) {
			Err(HttpErr(Timeout)) => Ok(text_response("Outbound request timed out."))
			other => Err(ServerErr("Expected Timeout, got ${Str.inspect(other)}"))
		}
	} else {
		Ok(text_response("See init! for the outbound HTTP example code."))
	}
}

text_response : Str -> Server.Outcome
text_response = |body|
	Server.respond(
		Response.from_status(200)
			.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
			.with_body(Str.to_utf8(body)),
	)

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
