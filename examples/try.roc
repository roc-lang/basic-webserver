## Demonstrates propagating effect failures and handling typed domain errors.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.14.0/9mrSfhWKEXsrPUW2oHdZZGov1oMRryvvACDT8p7E97PY.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context| {
	body = request.body().with_limit(1024).read_all!() ? |err| ServerErr("Failed to read request body: ${Str.inspect(err)}")

	input = Str.from_utf8(body) ? |_| ServerErr("Request body must be valid UTF-8")

	match classify(input) {
		Ok(Good) => Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("GOOD"))))
		Ok(Bad) => Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("BAD"))))
		Err(InvalidRating) => Ok(Server.respond(Response.from_status(400).with_body(Str.to_utf8("Expected \"good\" or \"bad\"."))))
	}
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})

## Return `Ok(Good)` or `Ok(Bad)` for accepted input and a typed
## `Err(InvalidRating)` for any other value.
classify : Str -> Try([Good, Bad], [InvalidRating])
classify = |input| match input {
	"good" => Ok(Good)
	"bad" => Ok(Bad)
	_ => Err(InvalidRating)
}
