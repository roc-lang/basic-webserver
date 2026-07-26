## Bridges bounded HTTP request bodies to a local TCP echo service.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.14.0-rc1/GfM5qZLcKYGA9XD4V7u1S4RjWrdfws29Uz2m86C7bmUC.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Tcp
import http.Response

# This example requires a TCP echo service on localhost:8085. POST bytes to the
# HTTP server to receive the bytes returned by that service.

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context| {
	body = request.body().with_limit(64 * 1024).read_all!()
		? |err| ServerErr("Failed to read request body: ${Str.inspect(err)}")
	stream = Tcp.connect!("127.0.0.1", 8085)
		? |err| ServerErr("Failed to connect to TCP service: ${Tcp.connect_err_to_str(err)}")
	stream.write!(body)
		? |TcpWriteErr(err)| ServerErr("Failed to write to TCP service: ${Tcp.stream_err_to_str(err)}")
	echoed = stream.read_exactly!(body.len())
		? |err|
			match err {
				TcpReadErr(stream_err) => ServerErr("Failed to read from TCP service: ${Tcp.stream_err_to_str(stream_err)}")
				TcpUnexpectedEOF => ServerErr("TCP service closed before echoing the complete request")
			}

	Ok(Server.respond(Response.from_status(200).with_body(echoed)))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
