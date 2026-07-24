import Host
import http.Header
import http.Method
import http.Response

## Configure and run an inbound HTTP server.
##
## Server requests deliberately use a different type from outbound
## `http.Request`: their bodies are request-scoped streams instead of complete
## byte lists.
##
## ```roc
## init! = || Ok({
##     config: Server.default_config.with_listen({ host: "127.0.0.1", port: 8080 }),
##     context: {},
## })
##
## respond! = |request, {}| {
##     body = request.body().with_limit(64 * 1024).read_all!()?
##     response = Response.from_status(200).with_body(body)
##     Ok(Server.respond(response))
## }
##
## shutdown! = |_, {}| Ok({})
## ```
##
## An unhandled semantic error returned by `respond!` is inspected, logged to
## stderr with request context, and converted to a 500 response. Unhandled
## `init!` and `shutdown!` errors are logged and produce process exit code 1.
Server :: [].{

	## Default maximum request-body size: 1 MiB.
	##
	## This is one of the finite production defaults used by
	## [`default_config`](#Server.default_config).
	default_body_limit_bytes : U64
	default_body_limit_bytes = 1024 * 1024

	## Default maximum chunk delivered by [`Body.read!`](#Server.Body.read!):
	## 64 KiB.
	default_body_chunk_bytes : U32
	default_body_chunk_bytes = 64 * 1024

	## Default number of request-body chunks buffered per request.
	default_buffered_body_chunks : U16
	default_buffered_body_chunks = 1

	## Default maximum number of concurrently active connections.
	default_max_connections : U32
	default_max_connections = 256

	## Default maximum number of concurrently executing Roc handlers.
	default_max_handlers : U16
	default_max_handlers = 32

	## Default finite queue capacity for handlers waiting to execute.
	default_max_queued_handlers : U16
	default_max_queued_handlers = 64

	## Opaque runtime configuration returned from the application's `init!`
	## function. Use the builders below so future server settings can be added
	## without invalidating application record construction.
	Config := [
		Config(
			{
				listen : { host : Str, port : U16 },
				limits : {

					## The listener applies TCP accept backpressure while this many
					## connections are active.
					max_connections : U32,

					## At most this many Roc request handlers execute concurrently.
					max_handlers : U16,

					## Requests beyond the active-handler limit may wait in this finite
					## queue. Once it is full, new requests receive 503. Zero disables
					## queueing.
					max_queued_handlers : U16,
				},
				request_bodies : {
					max_bytes : U64,
					chunk_bytes : U32,
					buffered_chunks : U16,
				},
				graceful_shutdown : {
					drain_timeout_ms : U64,
					hook_timeout_ms : U64,
				},
			},
		),
	].{

		## Platform ABI conversion hook; not an application API. Applications
		## should use [`default_config`](#Server.default_config) and the `with_*`
		## builders.
		to_host : Config -> {
			host : Str,
			port : U16,
			body_max_bytes : U64,
			body_chunk_bytes : U32,
			body_buffered_chunks : U16,
			drain_timeout_ms : U64,
			hook_timeout_ms : U64,
			max_connections : U32,
			max_handlers : U16,
			max_queued_handlers : U16,
		}
		to_host = |Config(config)| {
			host: config.listen.host,
			port: config.listen.port,
			body_max_bytes: config.request_bodies.max_bytes,
			body_chunk_bytes: config.request_bodies.chunk_bytes,
			body_buffered_chunks: config.request_bodies.buffered_chunks,
			drain_timeout_ms: config.graceful_shutdown.drain_timeout_ms,
			hook_timeout_ms: config.graceful_shutdown.hook_timeout_ms,
			max_connections: config.limits.max_connections,
			max_handlers: config.limits.max_handlers,
			max_queued_handlers: config.limits.max_queued_handlers,
		}
	}

	## Safe defaults: loopback-only; finite connection, handler, and handler
	## queue limits; a 1 MiB request limit; one buffered 64 KiB chunk; and
	## bounded graceful shutdown. Exceeding the drain deadline forces process
	## exit without running the shutdown hook, because a request handler may
	## still be using the application context.
	default_config : Config
	default_config = Config({
		listen: { host: "127.0.0.1", port: 8000 },
		limits: {
			max_connections: default_max_connections,
			max_handlers: default_max_handlers,
			max_queued_handlers: default_max_queued_handlers,
		},
		request_bodies: {
			max_bytes: default_body_limit_bytes,
			chunk_bytes: default_body_chunk_bytes,
			buffered_chunks: default_buffered_body_chunks,
		},
		graceful_shutdown: {
			drain_timeout_ms: 30_000,
			hook_timeout_ms: 10_000,
		},
	})

	## Set the listener host and port. The default is loopback-only on port 8000.
	with_listen : Config, { host : Str, port : U16 } -> Config
	with_listen = |Config(config), listen| Config({ ..config, listen })

	## Set connection, active-handler, and queued-handler capacity together.
	## Saturated handler queues receive 503 responses.
	with_limits : Config, { max_connections : U32, max_handlers : U16, max_queued_handlers : U16 } -> Config
	with_limits = |Config(config), limits| Config({ ..config, limits })

	## Set all finite inbound request-body limits.
	with_request_body_limits : Config, { max_bytes : U64, chunk_bytes : U32, buffered_chunks : U16 } -> Config
	with_request_body_limits = |Config(config), request_bodies| Config({ ..config, request_bodies })

	## Set only the maximum total bytes accepted for each request body.
	with_request_body_limit : Config, U64 -> Config
	with_request_body_limit = |Config(config), max_bytes|
		Config({ ..config, request_bodies: { ..config.request_bodies, max_bytes } })

	## Set the request-drain deadline and final shutdown-hook deadline.
	with_graceful_shutdown : Config, { drain_timeout_ms : U64, hook_timeout_ms : U64 } -> Config
	with_graceful_shutdown = |Config(config), graceful_shutdown| Config({ ..config, graceful_shutdown })

	## A request-scoped inbound body. The host expires this capability when the
	## request handler returns, and permits only one active reader at a time.
	Body := [
		Body(
			{
				host_id : U64,
				limit_bytes : U64,
				content_length : [Unknown, Known(U64)],
			},
		),
	].{
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

		## Platform ABI conversion hook; not an application API.
		from_host : U64, U64, [Unknown, Known(U64)] -> Body
		from_host = |host_id, limit_bytes, content_length|
			Body({ host_id, limit_bytes, content_length })

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
			next_limit = if requested_limit < raw.limit_bytes {
				requested_limit
			} else {
				raw.limit_bytes
			}
			Body({ ..raw, limit_bytes: next_limit })
		}

		## Read the next bounded chunk. End is stable and may be observed more than
		## once. Concurrent reads of one body return ConcurrentRead.
		read! : Body => Try(Read, [RequestBodyErr(Err)])
		read! = |Body(raw)|
			Host.request_body_read!(raw.host_id, raw.limit_bytes).map_err(|err| RequestBodyErr(body_err_from_host(err)))

		## Read all remaining bytes while enforcing this body's current limit.
		## Prefer read! for large or incrementally processed payloads.
		read_all! : Body => Try(List(U8), [RequestBodyErr(Err)])
		read_all! = |Body(raw)|
			Host.request_body_read_all!(raw.host_id, raw.limit_bytes).map_err(|err| RequestBodyErr(body_err_from_host(err)))
	}

	## An inbound server request. Its body is always streaming; use
	## [`Body.read_all!`](#Server.Body.read_all!) only when a bounded complete
	## body is appropriate.
	Request := {
		method : Method.Method,
		headers : List(Header.Header),
		target : Str,
		body : Body,
	}.{

		## Return the request method.
		method : Request -> Method.Method
		method = |request| request.method

		## Return the request headers in received order.
		headers : Request -> List(Header.Header)
		headers = |request| request.headers

		## Return the request target, including any query string.
		target : Request -> Str
		target = |request| request.target

		## Return the request-scoped streaming body capability.
		body : Request -> Body
		body = |request| request.body

		## Platform ABI conversion hook; not an application API.
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
	Outcome := [
		Respond(Response.Response),
		StopAfter({ response : Response.Response, exit_code : I64 }),
	].{

		## Platform ABI conversion hook; not an application API.
		to_host : Outcome -> { response : Response.Response, stop : Bool, exit_code : I64 }
		to_host = |outcome|
			match outcome {
				Respond(response) => { response, stop: Bool.False, exit_code: 0 }
				StopAfter({ response, exit_code }) => { response, stop: Bool.True, exit_code }
			}
	}

	## Return a response and keep serving requests.
	respond : Response.Response -> Outcome
	respond = |response| Respond(response)

	## Return a final response, then begin graceful shutdown with exit code 0.
	stop_after : Response.Response -> Outcome
	stop_after = |response| StopAfter({ response, exit_code: 0 })

	## Return a final response, then begin graceful shutdown with the given exit
	## code.
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

body_err_from_host : Host.RequestBodyErr -> Server.Body.Err
body_err_from_host = |err|
	match err {
		TooLarge(payload) => TooLarge(payload)
		ClientDisconnected => ClientDisconnected
		InvalidBody(detail) => InvalidBody(detail)
		RequestFinished => RequestFinished
		ConcurrentRead => ConcurrentRead
		Cancelled => Cancelled
	}
