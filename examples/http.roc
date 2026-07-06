# Demo of the basic-webserver outbound HTTP client (Http.send! / Http.get_utf8! / Http.get!).
app [Model, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Stdout
import pf.Http
import http.Request
import http.Response

Model : {}

program = { init!, respond! }

# Fetch some content at startup to demonstrate the outbound HTTP client. To
# exercise it, run a server on localhost:9000 (see the README); otherwise the
# requests simply report a failure and the webserver still starts.
init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| {
	_ = demo!({})
	Ok({})
}

demo! : {} => Try({}, _)
demo! = |{}| {
	# GET a plain-text body and decode it as UTF-8.
	_ = match Http.get_utf8!("http://localhost:9000/utf8test") {
		Ok(utf8) => Stdout.line!("I received '${utf8}' from the server.")
		Err(_) => Stdout.line!("GET /utf8test failed (is a server running on :9000?)")
	}

	# GET a JSON body and decode it into a Roc record.
	_ = {
		json_result : Try({ foo : Str }, _)
		json_result = Http.get!("http://localhost:9000")

        match json_result {
            Ok(decoded) => Stdout.line!("The json I received was: { foo: \"${decoded.foo}\" }")
            Err(_) => Stdout.line!("GET / failed (is a JSON server running on :9000?)")
        }
    }

    # Use send! with a custom header and inspect the Response.
    request =
        Request.from_method(GET)
            .with_uri("http://localhost:9000/utf8test")
            .with_headers(Http.header_tuples([{ name: "Accept", value: "text/plain" }]))
            .with_timeout(TimeoutMilliseconds(5000))

    match Http.send!(request) {
        Ok(response) => {
            _ = Stdout.line!("send! returned status ${Str.inspect(response.status())}.")
            Ok({})
        }
        Err(HttpErr(_)) => {
            _ = Stdout.line!("send! failed")
            Ok({})
        }
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model| {
	payload : {
		message : Str,
		status : U64,
		ok : Http.JsonValue,
		notes : Http.JsonValue,
		meta : Http.JsonValue,
	}
	payload = {
		message: "See init! for the outbound HTTP example code.",
		status: 200,
		ok: Http.JsonValue.bool(Bool.True),
		notes: Http.JsonValue.list(
			[
				Http.JsonValue.str("plain text"),
				Http.JsonValue.i64(-7),
			],
		),
		meta: Http.JsonValue.object(
			[
				{ name: "missing", value: Http.JsonValue.null },
				{ name: "count", value: Http.JsonValue.u64(2) },
			],
		),
	}

	Ok(Http.json_response(payload))
}
