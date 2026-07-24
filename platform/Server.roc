import Host
import http.Header
import http.Method
import http.Response

## Configure and run an inbound HTTP server.
##
## Server requests deliberately use a different type from outbound
## `http.Request`: their bodies are request-scoped streams instead of complete
## byte lists.
Server :: [].{

	## The finite production defaults used by [`default_config`](#default_config).
	default_body_limit_bytes : U64
	default_body_limit_bytes = 1024 * 1024

	default_body_chunk_bytes : U32
	default_body_chunk_bytes = 64 * 1024

	default_buffered_body_chunks : U16
	default_buffered_body_chunks = 1

	## Runtime configuration returned from the application's `init!` function.
	Config : {
		listen : { host : Str, port : U16 },
		request_bodies : {
			max_bytes : U64,
			chunk_bytes : U32,
			buffered_chunks : U16,
		},
		graceful_shutdown : {
			drain_timeout_ms : U64,
			hook_timeout_ms : U64,
		},
	}

	## Safe defaults: loopback-only, a 1 MiB request limit, one buffered 64 KiB
	## chunk, and bounded graceful shutdown. Exceeding the drain deadline forces
	## process exit without running the shutdown hook, because a request handler
	## may still be using the application context.
	default_config : Config
	default_config = {
		listen: { host: "127.0.0.1", port: 8000 },
		request_bodies: {
			max_bytes: default_body_limit_bytes,
			chunk_bytes: default_body_chunk_bytes,
			buffered_chunks: default_buffered_body_chunks,
		},
		graceful_shutdown: {
			drain_timeout_ms: 30_000,
			hook_timeout_ms: 10_000,
		},
	}

	## A request-scoped inbound body. The host expires this capability when the
	## request handler returns, and permits only one active reader at a time.
	Body := [Body({
		host_id : U64,
		limit_bytes : U64,
		content_length : [Unknown, Known(U64)],
	})].{
		Read : [Chunk(List(U8)), End]

		## A typed failure while consuming an inbound request body.
		Err : [
			TooLarge({ limit_bytes : U64, received_at_least : U64 }),
			ClientDisconnected,
			InvalidBody(Str),
			RequestFinished,
			ConcurrentRead,
			Cancelled,
		]

		## Render a body without exposing its request-scoped host identifier.
		to_inspect : Body -> Str
		to_inspect = |_| "Server.Body(<stream>)"

		## Construct the capability used by the host conversion layer.
		from_host : U64, U64, [Unknown, Known(U64)] -> Body
		from_host = |host_id, limit_bytes, content_length|
			Body({ host_id, limit_bytes, content_length })

		## Expose the identifier to the platform's hosted body effects.
		to_host_id : Body -> U64
		to_host_id = |Body(raw)| raw.host_id

		## The maximum number of bytes this request body may deliver.
		limit : Body -> U64
		limit = |Body(raw)| raw.limit_bytes

		## The declared Content-Length, when the request supplied one. The stream
		## still enforces its byte limit independently of this untrusted value.
		content_length : Body -> [Unknown, Known(U64)]
		content_length = |Body(raw)| raw.content_length

		## Return the same request stream with a stricter total byte limit. Limits
		## may only be narrowed, never widened beyond the server configuration.
		with_limit : Body, U64 -> Body
		with_limit = |Body(raw), requested_limit| {
			next_limit = if requested_limit < raw.limit_bytes { requested_limit } else { raw.limit_bytes }
			Body({ ..raw, limit_bytes: next_limit })
		}

		## Read the next bounded chunk. End is stable and may be observed more than
		## once. Concurrent reads of one body return ConcurrentRead.
		read! : Body => Try(Read, [RequestBodyErr(Err)])
		read! = |Body(raw)|
			Host.request_body_read!(raw.host_id, raw.limit_bytes).map_err(|err| RequestBodyErr(from_host_err(err)))

		## Read all remaining bytes while enforcing this body's current limit.
		## Prefer read! for large or incrementally processed payloads.
		read_all! : Body => Try(List(U8), [RequestBodyErr(Err)])
		read_all! = |Body(raw)|
			Host.request_body_read_all!(raw.host_id, raw.limit_bytes).map_err(|err| RequestBodyErr(from_host_err(err)))

		from_host_err : Host.RequestBodyErr -> Err
		from_host_err = |err|
			match err {
				TooLarge(payload) => TooLarge(payload)
				ClientDisconnected => ClientDisconnected
				InvalidBody(detail) => InvalidBody(detail)
				RequestFinished => RequestFinished
				ConcurrentRead => ConcurrentRead
				Cancelled => Cancelled
			}
	}

	## An inbound server request. Its body is always streaming; use Body's
	## bounded read-all convenience when a complete body is appropriate.
	Request := {
		method : Method.Method,
		headers : List(Header.Header),
		target : Str,
		body : Body,
	}.{

		method : Request -> Method.Method
		method = |request| request.method

		headers : Request -> List(Header.Header)
		headers = |request| request.headers

		target : Request -> Str
		target = |request| request.target

		body : Request -> Body
		body = |request| request.body

		## Construct an inbound request in the platform conversion layer.
		from_host : Method.Method, List(Header.Header), Str, Body -> Request
		from_host = |method_value, header_values, target_value, body_value|
			Request.{
				method: method_value,
				headers: header_values,
				target: target_value,
				body: body_value,
			}
	}

	## A successful request outcome. StopAfter sends its response while beginning
	## graceful shutdown; the first shutdown cause wins.
	Outcome : [
		Respond(Response.Response),
		StopAfter({ response : Response.Response, exit_code : I64 }),
	]

	respond : Response.Response -> Outcome
	respond = |response| Respond(response)

	stop_after : Response.Response -> Outcome
	stop_after = |response| StopAfter({ response, exit_code: 0 })

	stop_after_with_code : Response.Response, I64 -> Outcome
	stop_after_with_code = |response, exit_code| StopAfter({ response, exit_code })

	## Why the server is invoking the application's final shutdown hook.
	ShutdownReason : [
		ApplicationRequested,
		Interrupt,
		Terminate,
		StartupFailed(Str),
		RuntimeFailed(Str),
	]

}
