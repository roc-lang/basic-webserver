## Authorizes bounded raw PUT uploads into a declared writable root.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	roc: "nightly-2026-08-18-e9be50a",
}

import pf.Path
import pf.Server
import http.Response

Context : {
	uploads : Server.WritableRoot,
	readback : Server.FileRoot,
	alpha : Server.RelativeFile,
	exact_limit : Server.RelativeFile,
	existing : Server.RelativeFile,
	streamed_limit : Server.RelativeFile,
	timeout : Server.RelativeFile,
}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	uploads = Server.writable_root({
		id: "uploads-write",
		path: Path.utf8("uploads"),
	})
	readback = Server.file_root({
		id: "uploads-read",
		path: Path.utf8("uploads"),
	})
	alpha = Server.relative_file("alpha.bin").map_err(|_| Exit(1))?
	exact_limit = Server.relative_file("exact-limit.bin").map_err(|_| Exit(1))?
	existing = Server.relative_file("existing.bin").map_err(|_| Exit(1))?
	streamed_limit = Server.relative_file("streamed-limit.bin").map_err(|_| Exit(1))?
	timeout = Server.relative_file("timeout.bin").map_err(|_| Exit(1))?

	config = upload_config(uploads, readback)

	Ok({
		config,
		context: {
			uploads,
			readback,
			alpha,
			exact_limit,
			existing,
			streamed_limit,
			timeout,
		},
	})
}

upload_config : Server.WritableRoot, Server.FileRoot -> Server.Config
upload_config = |uploads, readback|
	Server.default_config
		.with_request_body_limits({
			max_bytes: 1024 * 1024,
			chunk_bytes: 4,
			buffered_chunks: 1,
		})
		.with_writable_roots([uploads])
		.with_file_roots([readback])
		.with_body_sink_limits({
			max_concurrent: 2,
			timeout_ms: 100,
		})

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, context|
	match (request.method(), request.target()) {
		(PUT, Resource({ raw_path: "/upload/alpha", .. })) =>
			Ok(
				Server.respond(
					upload!(
						request.body(),
						context.uploads,
						context.alpha,
						1024,
						Sha256,
					),
				),
			)
		(PUT, Resource({ raw_path: "/upload/exact-limit", .. })) =>
			Ok(
				Server.respond(
					upload!(
						request.body(),
						context.uploads,
						context.exact_limit,
						11,
						NoDigest,
					),
				),
			)
		(PUT, Resource({ raw_path: "/upload/existing", .. })) =>
			Ok(
				Server.respond(
					upload!(
						request.body(),
						context.uploads,
						context.existing,
						1024,
						NoDigest,
					),
				),
			)
		(PUT, Resource({ raw_path: "/upload/streamed-limit", .. })) =>
			Ok(
				Server.respond(
					upload!(
						request.body(),
						context.uploads,
						context.streamed_limit,
						5,
						NoDigest,
					),
				),
			)
		(PUT, Resource({ raw_path: "/upload/timeout", .. })) =>
			Ok(
				Server.respond(
					upload!(
						request.body(),
						context.uploads,
						context.timeout,
						1024,
						NoDigest,
					),
				),
			)
		(GET, Resource({ raw_path: "/files/alpha", .. })) =>
			Ok(Server.file_response({ files: context.readback, relative: context.alpha }))
		(GET, Resource({ raw_path: "/files/exact-limit", .. })) =>
			Ok(Server.file_response({ files: context.readback, relative: context.exact_limit }))
		(GET, Resource({ raw_path: "/files/existing", .. })) =>
			Ok(Server.file_response({ files: context.readback, relative: context.existing }))
		(GET, Resource({ raw_path: "/files/streamed-limit", .. })) =>
			Ok(Server.file_response({ files: context.readback, relative: context.streamed_limit }))
		(GET, Resource({ raw_path: "/files/timeout", .. })) =>
			Ok(Server.file_response({ files: context.readback, relative: context.timeout }))
		_ => Ok(Server.respond(text_response(404, "Not Found")))
	}

upload! : Server.Body, Server.WritableRoot, Server.RelativeFile, U64, Server.Body.Digest => Response
upload! = |body, root, relative, limit, digest|
	match body.with_limit(limit).write_file!({ root, relative, digest }) {
		Ok(result) =>
			text_response(
				201,
				"bytes=${result.bytes_written.to_str()} digest=${Str.inspect(result.digest)}",
			)
		Err(BodySinkErr(DestinationExists)) => text_response(409, "DestinationExists")
		Err(BodySinkErr(TooLarge(details))) =>
			text_response(
				413,
				"TooLarge limit=${details.limit_bytes.to_str()} received=${details.received_at_least.to_str()}",
			)
		Err(BodySinkErr(Timeout)) => text_response(408, "Timeout")
		Err(BodySinkErr(Saturated)) => text_response(503, "Saturated")
		Err(BodySinkErr(Stopping)) => text_response(503, "Stopping")
		Err(BodySinkErr(err)) => text_response(500, Str.inspect(err))
	}

text_response : U16, Str -> Response
text_response = |status, body|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
		.with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
