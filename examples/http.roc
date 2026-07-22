# Demo of the basic-webserver outbound HTTP client (Http.send! / Http.get_utf8! / Http.get!).
app [Model, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Http
import http.Request
import http.Response

Model : {}

program = { init!, respond! }

# Fetch some content at startup to demonstrate the outbound HTTP client. To
# exercise it, run a server on localhost:9000 (see the root README); otherwise the
# requests simply report a failure and the webserver still starts.
init! : () => Try(Model, [Exit(I64), ..])
init! = || {
	demo!() ?? {}
	Ok({})
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
    request =
        Request.from_method(GET)
            .with_uri("http://localhost:9000/htmltest")
            .with_timeout(TimeoutMilliseconds(5000))

    match Http.send!(request) {
        Ok(response) => {
            body_str = Str.from_utf8(response.body())?
            Stdout.line!("Response body:\n\t${body_str}.\n")?
        }
        Err(HttpErr(_)) => {
            Stdout.line!("send! failed")?
        }
    }

    # Same request with a custom Accept header.
    request_2 =
        Request.from_method(GET)
            .with_uri("http://localhost:9000/htmltest")
            .with_headers([{ name: "Accept", value: "text/html" }])
            .with_timeout(TimeoutMilliseconds(5000))

    match Http.send!(request_2) {
        Ok(response_2) => {
            body_str_2 = Str.from_utf8(response_2.body())?
            Stdout.line!("Response body 2:\n\t${body_str_2}.\n")?
            Ok({})
        }
        Err(HttpErr(_)) => {
            Stdout.line!("send! failed")?
            Ok({})
        }
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model| {
	payload : Http.JsonValue
	payload = {
		Http.JsonValue.object([
			Http.JsonValue.field("message", Http.JsonValue.str("See init! for the outbound HTTP example code.")),
			Http.JsonValue.field("status", Http.JsonValue.u64(200)),
			Http.JsonValue.field("ok", Http.JsonValue.bool(Bool.True)),
			Http.JsonValue.field("notes", Http.JsonValue.list([
				Http.JsonValue.str("plain text"),
				Http.JsonValue.i64(-7),
			])),
			Http.JsonValue.field("meta", Http.JsonValue.object([
				Http.JsonValue.field("missing", Http.JsonValue.null),
				Http.JsonValue.field("count", Http.JsonValue.u64(2)),
			])),
		])
	}

	Ok(Http.json_response(payload))
}
