app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import http.Response

# To run this example: check the root README.md

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, _state|
	match check_file!("good") {
		Ok(Good) => Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("GOOD"))))
		Ok(Bad) => Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("BAD"))))
		Err(IOError) => Ok(Server.respond(Response.from_status(500).with_body(Str.to_utf8("ERROR: IoError when executing checkFile!."))))
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})

# imagine this function does some IO operation
# and returns a Try, succeeding with a tag either Good or Bad,
# or failing with an IOError
check_file! : Str => Try([Good, Bad], [IOError])
check_file! = |str|
	if str == "good" {
		Ok(Good)
	} else if str == "bad" {
		Ok(Bad)
	} else {
		Err(IOError)
	}
