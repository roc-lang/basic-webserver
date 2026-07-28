import Host
import Path
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

	## Default maximum idle time for completing each request head: 10 seconds.
	default_header_timeout_ms : U64
	default_header_timeout_ms = 10_000

	## Default maximum idle time between non-empty request-body chunks: 30 seconds.
	default_body_idle_timeout_ms : U64
	default_body_idle_timeout_ms = 30_000

	## Default maximum idle time between requests on a persistent connection:
	## 60 seconds.
	default_keep_alive_idle_timeout_ms : U64
	default_keep_alive_idle_timeout_ms = 60_000

	## Default maximum time an admitted request may wait for a Roc handler:
	## 5 seconds.
	default_handler_queue_timeout_ms : U64
	default_handler_queue_timeout_ms = 5_000

	## Default maximum time without outbound transport progress: 30 seconds.
	default_response_idle_timeout_ms : U64
	default_response_idle_timeout_ms = 30_000

	## Default maximum number of host-managed file responses that may be active
	## concurrently. File transfers do not consume Roc handler capacity.
	default_max_file_transfers : U16
	default_max_file_transfers = 32

	## Default chunk size used while streaming files: 64 KiB. A transfer owns
	## at most one queued chunk and one active read buffer, so memory use does
	## not scale with file size.
	default_file_chunk_bytes : U32
	default_file_chunk_bytes = 64 * 1024

	## Host-managed file responses use one cross-platform contract. Roots and
	## routes are validated and activated as one immutable configuration before
	## the listener is bound. Paths are root-relative regular files; dotfiles,
	## dot components, symlinks/reparse points, directories, NULs, drive/UNC
	## paths, backslashes, and encoded separators are denied without revealing
	## filesystem layout. There is no directory listing, index lookup, or SPA
	## fallback.
	##
	## Public routes own their exact path or prefix for all methods: GET and HEAD
	## use the native file engine, while other methods return 405 and never fall
	## through to Roc. Query strings do not participate in route matching.
	##
	## Responses include a deterministic extension-based Content-Type (or
	## application/octet-stream), Last-Modified when available, a weak ETag,
	## Content-Disposition, and the selected cache policy. Identity responses
	## include Content-Length and Accept-Ranges. Eligible full responses may
	## instead stream Zstandard, Brotli, or gzip according to Accept-Encoding
	## and include Vary: Accept-Encoding. Preconditions are evaluated before
	## ranges. One byte range, including suffix and open-ended forms, is
	## supported as identity; malformed and multi-range requests are safely
	## ignored, and valid unsatisfiable ranges return 416.

	## A small, typed cache policy for host-managed file responses.
	CachePolicy := [NoStore, Revalidate, PrivateFor(U32), PublicFor(U32)].{

		## Platform ABI conversion hook; not an application API.
		to_host : CachePolicy -> { tag : U8, max_age_seconds : U32 }
		to_host = |policy|
			match policy {
				NoStore => { tag: 0, max_age_seconds: 0 }
				Revalidate => { tag: 1, max_age_seconds: 0 }
				PrivateFor(seconds) => { tag: 2, max_age_seconds: seconds }
				PublicFor(seconds) => { tag: 3, max_age_seconds: seconds }
			}
	}

	## Do not allow caches to store the response.
	no_store : CachePolicy
	no_store = NoStore

	## Allow storage but require revalidation before reuse. This is the
	## conservative default for declared roots.
	revalidate : CachePolicy
	revalidate = Revalidate

	## Permit private caches to reuse a response for the given number of seconds.
	private_for : U32 -> CachePolicy
	private_for = |seconds| PrivateFor(seconds)

	## Permit shared and private caches to reuse a response for the given number
	## of seconds.
	public_for : U32 -> CachePolicy
	public_for = |seconds| PublicFor(seconds)

	## An immutable descriptor for one startup-declared filesystem root. Its
	## identifier is the only value sent in a response plan; the host rejects
	## plans whose identifier was not activated by the returned Config.
	FileRoot := [
		FileRoot({ id : Str, path : Path.Path, cache : CachePolicy }),
	].{

		## Platform ABI conversion hook; not an application API.
		to_host : FileRoot -> {
			id : Str,
			path_tag : U8,
			path_utf8 : Str,
			path_unix_bytes : List(U8),
			path_windows_u16s : List(U16),
			cache_tag : U8,
			cache_max_age_seconds : U32,
		}
		to_host = |FileRoot(root)| {
			(path_tag, path_utf8, path_unix_bytes, path_windows_u16s) = 
				match Path.to_raw(root.path) {
					Utf8(str) => (0, str, [], [])
					UnixBytes(bytes) => (1, "", bytes, [])
					WindowsU16s(u16s) => (2, "", [], u16s)
				}
			cache = CachePolicy.to_host(root.cache)
			{
				id: root.id,
				path_tag,
				path_utf8,
				path_unix_bytes,
				path_windows_u16s,
				cache_tag: cache.tag,
				cache_max_age_seconds: cache.max_age_seconds,
			}
		}
	}

	## Declare a root with the conservative revalidation cache policy. Root
	## identifiers contain 1-64 ASCII letters, digits, '-' or '_'; the complete
	## configuration is validated before listening.
	file_root : { id : Str, path : Path.Path } -> FileRoot
	file_root = |{ id, path }| FileRoot({ id, path, cache: Revalidate })

	## Declare a root with an explicit cache policy.
	file_root_with_cache : { id : Str, path : Path.Path, cache : CachePolicy } -> FileRoot
	file_root_with_cache = |root| FileRoot(root)

	## A validated relative child path used by exact routes and authorized file
	## plans. The host repeats this validation at the ABI boundary.
	RelativeFile := [RelativeFile(Str)].{

		## Platform ABI conversion hook; not an application API.
		to_host : RelativeFile -> Str
		to_host = |RelativeFile(relative)| relative
	}

	## Construct a safe relative child path of at most 4 KiB. Empty components,
	## dot components, dotfiles, separators other than '/', NULs, and Windows
	## drive syntax are rejected so the value has one cross-platform meaning.
	relative_file : Str -> Try(RelativeFile, [InvalidRelativeFile])
	relative_file = |relative| {
		relative_bytes = Str.to_utf8(relative)
		segments = Str.split_on(relative, "/")
		valid = 
			Bool.not(relative.is_empty())
				and relative_bytes.len() <= 4 * 1024
					and segments.all(
						|segment| {
							bytes = Str.to_utf8(segment)
							Bool.not(bytes.is_empty())
								and segment != "."
									and segment != ".."
										and match bytes {
											[46, ..] => Bool.False
											_ => bytes.all(|byte| byte != 0 and byte != 58 and byte != 92)
										}
						},
					)
		if valid {
			Ok(RelativeFile(relative))
		} else {
			Err(InvalidRelativeFile)
		}
	}

	## Override a root's cache policy for one native route or response plan, or
	## inherit the root policy.
	CacheChoice := [Inherit, Override(CachePolicy)].{

		## Platform ABI conversion hook; not an application API.
		to_host : CacheChoice -> { override : Bool, tag : U8, max_age_seconds : U32 }
		to_host = |choice|
			match choice {
				Inherit => { override: Bool.False, tag: 0, max_age_seconds: 0 }
				Override(policy) => {
					raw = CachePolicy.to_host(policy)
					{ override: Bool.True, tag: raw.tag, max_age_seconds: raw.max_age_seconds }
				}
			}
	}

	## Inherit the cache policy declared by a file root.
	inherit_cache : CacheChoice
	inherit_cache = Inherit

	## Override a root cache policy for one route or response plan.
	override_cache : CachePolicy -> CacheChoice
	override_cache = |policy| Override(policy)

	## One startup-declared host-native file route. Static mounts own an exact
	## prefix on segment boundaries. Static files own one exact URI path.
	FileRoute := [
		FileRoute(
			{
				at : Str,
				files : FileRoot,
				kind : U8,
				relative : Str,
				cache : CacheChoice,
			},
		),
	].{

		## Platform ABI conversion hook; not an application API.
		to_host : FileRoute -> {
			at : Str,
			root_id : Str,
			kind : U8,
			relative : Str,
			cache_override : Bool,
			cache_tag : U8,
			cache_max_age_seconds : U32,
		}
		to_host = |FileRoute(route)| {
			FileRoot(root) = route.files
			cache = CacheChoice.to_host(route.cache)
			{
				at: route.at,
				root_id: root.id,
				kind: route.kind,
				relative: route.relative,
				cache_override: cache.override,
				cache_tag: cache.tag,
				cache_max_age_seconds: cache.max_age_seconds,
			}
		}
	}

	## Declare a public static mount that inherits its root cache policy. Route
	## paths are ASCII absolute URI paths of at most 4 KiB and are validated at
	## startup.
	static_mount : { at : Str, files : FileRoot } -> FileRoute
	static_mount = |{ at, files }|
		FileRoute({ at, files, kind: 0, relative: "", cache: Inherit })

	## Declare a public static mount with an explicit cache policy.
	static_mount_with_cache : { at : Str, files : FileRoot, cache : CachePolicy } -> FileRoute
	static_mount_with_cache = |{ at, files, cache }|
		FileRoute({ at, files, kind: 0, relative: "", cache: Override(cache) })

	## Declare one exact public file route that inherits its root cache policy.
	static_file : { at : Str, files : FileRoot, relative : RelativeFile } -> FileRoute
	static_file = |{ at, files, relative }|
		FileRoute({
			at,
			files,
			kind: 1,
			relative: RelativeFile.to_host(relative),
			cache: Inherit,
		})

	## Declare one exact public file route with an explicit cache policy.
	static_file_with_cache : { at : Str, files : FileRoot, relative : RelativeFile, cache : CachePolicy } -> FileRoute
	static_file_with_cache = |{ at, files, relative, cache }|
		FileRoute({
			at,
			files,
			kind: 1,
			relative: RelativeFile.to_host(relative),
			cache: Override(cache),
		})

	## The complete readiness state. There are deliberately no names, reasons,
	## dependency callbacks, or intermediate states.
	ReadinessState : [NotReady, Ready]

	## A bounded host-owned readiness gate. It is safe to retain in immutable
	## context and update from concurrent handlers. Final Roc ARC release closes
	## the capability; graceful drain permanently changes it to NotReady before
	## `shutdown!` runs.
	Readiness := { host : Host.Readiness }.{

		## Create one readiness gate with an explicit initial state. The host has
		## finite capacity and reports exhaustion instead of growing a registry.
		create! : ReadinessState => Try(Readiness, [ReadinessCapacityExhausted])
		create! = |state| {
			host = Host.readiness_create!(state == Ready)?
			Ok(Readiness.{ host })
		}

		## Atomically replace the readiness state. Once graceful drain begins,
		## every update returns ServerStopping and the state remains NotReady.
		set! : Readiness, ReadinessState => Try({}, [InvalidReadiness, StaleReadiness, ServerStopping])
		set! = |readiness, state|
			Host.readiness_set!(to_host(readiness), state == Ready)

		## Render without exposing the host lifecycle token.
		to_inspect : Readiness -> Str
		to_inspect = |_| "Server.Readiness(<opaque>)"

		## Platform ABI conversion hook; not an application API.
		to_host : Readiness -> Host.Readiness
		to_host = |Readiness.{ host }| host
	}

	## One native exact route whose response proves only that the listener and
	## HTTP machinery can serve it. `init!` and complete route validation finish
	## before the listener is bound, so this route also serves as a deployment
	## startup probe once it becomes reachable; there is no separate mutable
	## startup state.
	LivenessRoute := [LivenessRoute(Str)].{

		## Platform ABI conversion hook; not an application API.
		to_host : LivenessRoute -> Str
		to_host = |LivenessRoute(at)| at
	}

	## One native exact route backed by a typed readiness gate.
	ReadinessRoute := [ReadinessRoute({ at : Str, readiness : Readiness })].{

		## Platform ABI conversion hook; not an application API.
		to_host : ReadinessRoute -> { at : Str, readiness : Host.Readiness }
		to_host = |ReadinessRoute({ at, readiness })| {
			at,
			readiness: Readiness.to_host(readiness),
		}
	}

	## Declare a native liveness route. Paths are validated with all other native
	## routes atomically before the listener is bound.
	liveness_route : Str -> LivenessRoute
	liveness_route = |at| LivenessRoute(at)

	## Declare a native readiness route backed by the supplied gate.
	readiness_route : { at : Str, readiness : Readiness } -> ReadinessRoute
	readiness_route = |route| ReadinessRoute(route)

	## The immutable startup route topology. Exact route duplicates are rejected;
	## exact routes take precedence over more general file prefixes.
	NativeRoutes : {
		files : List(FileRoute),
		liveness : List(LivenessRoute),
		readiness : List(ReadinessRoute),
	}

	## No host-native routes.
	no_native_routes : NativeRoutes
	no_native_routes = { files: [], liveness: [], readiness: [] }

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
				timeouts : {
					header_ms : U64,
					body_idle_ms : U64,
					keep_alive_idle_ms : U64,
					handler_queue_ms : U64,
					response_idle_ms : U64,
				},
				graceful_shutdown : {
					drain_timeout_ms : U64,
					hook_timeout_ms : U64,
				},
				file_roots : List(FileRoot),
				native_routes : NativeRoutes,
				file_transfers : {
					max_concurrent : U16,
					chunk_bytes : U32,
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
			header_timeout_ms : U64,
			body_idle_timeout_ms : U64,
			keep_alive_idle_timeout_ms : U64,
			handler_queue_timeout_ms : U64,
			response_idle_timeout_ms : U64,
			drain_timeout_ms : U64,
			hook_timeout_ms : U64,
			max_connections : U32,
			max_handlers : U16,
			max_queued_handlers : U16,
			file_roots : List(
				{
					id : Str,
					path_tag : U8,
					path_utf8 : Str,
					path_unix_bytes : List(U8),
					path_windows_u16s : List(U16),
					cache_tag : U8,
					cache_max_age_seconds : U32,
				},
			),
			native_file_routes : List(
				{
					at : Str,
					root_id : Str,
					kind : U8,
					relative : Str,
					cache_override : Bool,
					cache_tag : U8,
					cache_max_age_seconds : U32,
				},
			),
			liveness_routes : List(Str),
			readiness_routes : List({ at : Str, readiness : Host.Readiness }),
			file_max_concurrent : U16,
			file_chunk_bytes : U32,
		}
		to_host = |Config(config)| {
			host: config.listen.host,
			port: config.listen.port,
			body_max_bytes: config.request_bodies.max_bytes,
			body_chunk_bytes: config.request_bodies.chunk_bytes,
			body_buffered_chunks: config.request_bodies.buffered_chunks,
			header_timeout_ms: config.timeouts.header_ms,
			body_idle_timeout_ms: config.timeouts.body_idle_ms,
			keep_alive_idle_timeout_ms: config.timeouts.keep_alive_idle_ms,
			handler_queue_timeout_ms: config.timeouts.handler_queue_ms,
			response_idle_timeout_ms: config.timeouts.response_idle_ms,
			drain_timeout_ms: config.graceful_shutdown.drain_timeout_ms,
			hook_timeout_ms: config.graceful_shutdown.hook_timeout_ms,
			max_connections: config.limits.max_connections,
			max_handlers: config.limits.max_handlers,
			max_queued_handlers: config.limits.max_queued_handlers,
			file_roots: config.file_roots.map(FileRoot.to_host),
			native_file_routes: config.native_routes.files.map(FileRoute.to_host),
			liveness_routes: config.native_routes.liveness.map(LivenessRoute.to_host),
			readiness_routes: config.native_routes.readiness.map(ReadinessRoute.to_host),
			file_max_concurrent: config.file_transfers.max_concurrent,
			file_chunk_bytes: config.file_transfers.chunk_bytes,
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
		timeouts: {
			header_ms: default_header_timeout_ms,
			body_idle_ms: default_body_idle_timeout_ms,
			keep_alive_idle_ms: default_keep_alive_idle_timeout_ms,
			handler_queue_ms: default_handler_queue_timeout_ms,
			response_idle_ms: default_response_idle_timeout_ms,
		},
		graceful_shutdown: {
			drain_timeout_ms: 30_000,
			hook_timeout_ms: 10_000,
		},
		file_roots: [],
		native_routes: no_native_routes,
		file_transfers: {
			max_concurrent: default_max_file_transfers,
			chunk_bytes: default_file_chunk_bytes,
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

	## Set the complete inbound and outbound transport timeout policy. Every
	## value is milliseconds in the inclusive range 1 through 86_400_000; zero
	## is invalid and startup fails before listening.
	##
	## `header_ms` is an idle deadline while completing a request head and
	## resets whenever head bytes arrive. `body_idle_ms` begins when the host
	## waits for the next body frame and resets only after non-empty body data
	## arrives. `keep_alive_idle_ms` begins after a response has completed and
	## bounds the gap before the next request. `handler_queue_ms` begins after a
	## request takes a queue slot and ends before Roc execution begins.
	## `response_idle_ms` begins when response transmission starts and resets
	## whenever the socket or HTTP/2 stream flow-control window makes progress.
	with_timeouts : Config, { header_ms : U64, body_idle_ms : U64, keep_alive_idle_ms : U64, handler_queue_ms : U64, response_idle_ms : U64 } -> Config
	with_timeouts = |Config(config), timeouts| Config({ ..config, timeouts })

	## Set the request-drain deadline and final shutdown-hook deadline.
	with_graceful_shutdown : Config, { drain_timeout_ms : U64, hook_timeout_ms : U64 } -> Config
	with_graceful_shutdown = |Config(config), graceful_shutdown| Config({ ..config, graceful_shutdown })

	## Replace the complete set of startup-declared file roots.
	with_file_roots : Config, List(FileRoot) -> Config
	with_file_roots = |Config(config), file_roots| Config({ ..config, file_roots })

	## Replace the complete immutable host-native route table.
	with_native_routes : Config, NativeRoutes -> Config
	with_native_routes = |Config(config), native_routes| Config({ ..config, native_routes })

	## Set the active-transfer bound and streaming chunk size for host-managed
	## file responses. Saturation returns 503 without queueing. Each transfer
	## owns at most one queued chunk and one active read buffer.
	with_file_transfer_limits : Config, { max_concurrent : U16, chunk_bytes : U32 } -> Config
	with_file_transfer_limits = |Config(config), file_transfers| Config({ ..config, file_transfers })

	## A request-scoped inbound body. The host expires this capability when the
	## request handler returns, and permits only one active reader at a time.
	Body := [
		Body(
			{
				host : Host.RequestBody,
				limit_bytes : U64,
				content_length : [Unknown, Known(U64)],
			},
		),
	].{
		Read : [Chunk(List(U8)), End]

		## A typed failure while consuming an inbound request body.
		Err : [
			TooLarge({ limit_bytes : U64, received_at_least : U64 }),
			Timeout,
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
		from_host : Host.RequestBody, U64, [Unknown, Known(U64)] -> Body
		from_host = |host, limit_bytes, content_length|
			Body({ host, limit_bytes, content_length })

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
			Host.request_body_read!(raw.host, raw.limit_bytes).map_err(|err| RequestBodyErr(body_err_from_host(err)))

		## Read every remaining chunk sequentially and thread request-local state
		## through an effectful step function. The first step error stops reading;
		## returning from the handler then cancels any unread request bytes.
		fold_chunks! : Body, state, (state, List(U8) => Try(state, err)) => Try(state, [ChunkReadErr({ err : Err, state : state }), ChunkStepErr(err)])
		fold_chunks! = |body, state, step!|
			match read!(body) {
				Ok(Chunk(chunk)) =>
					match step!(state, chunk) {
						Ok(next) => fold_chunks!(body, next, step!)
						Err(err) => Err(ChunkStepErr(err))
					}
				Ok(End) => Ok(state)
				Err(RequestBodyErr(err)) => Err(ChunkReadErr({ err, state }))
			}

		## Read all remaining bytes while enforcing this body's current limit.
		## Prefer read! for large or incrementally processed payloads.
		read_all! : Body => Try(List(U8), [RequestBodyErr(Err)])
		read_all! = |Body(raw)|
			Host.request_body_read_all!(raw.host, raw.limit_bytes).map_err(|err| RequestBodyErr(body_err_from_host(err)))
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
		ServeFile(
			{
				files : FileRoot,
				relative : RelativeFile,
				disposition : [Inline, Attachment(Str)],
				cache : CacheChoice,
			},
		),
		StopAfter({ response : Response.Response, exit_code : I64 }),
	].{

		## Platform ABI conversion hook; not an application API.
		to_host : Outcome -> {
			kind : U8,
			response : Response.Response,
			stop : Bool,
			exit_code : I64,
			file_root_id : Str,
			file_relative : Str,
			file_disposition : U8,
			file_download_name : Str,
			file_cache_override : Bool,
			file_cache_tag : U8,
			file_cache_max_age_seconds : U32,
		}
		to_host = |outcome|
			match outcome {
				Respond(response) => {
					kind: 0,
					response,
					stop: Bool.False,
					exit_code: 0,
					file_root_id: "",
					file_relative: "",
					file_disposition: 0,
					file_download_name: "",
					file_cache_override: Bool.False,
					file_cache_tag: 0,
					file_cache_max_age_seconds: 0,
				}
				ServeFile({ files, relative, disposition, cache }) => {
					FileRoot(root) = files
					raw_cache = CacheChoice.to_host(cache)
					(disposition_tag, download_name) = 
						match disposition {
							Inline => (0, "")
							Attachment(name) => (1, name)
						}
					{
						kind: 1,
						response: Response.from_status(500),
						stop: Bool.False,
						exit_code: 0,
						file_root_id: root.id,
						file_relative: RelativeFile.to_host(relative),
						file_disposition: disposition_tag,
						file_download_name: download_name,
						file_cache_override: raw_cache.override,
						file_cache_tag: raw_cache.tag,
						file_cache_max_age_seconds: raw_cache.max_age_seconds,
					}
				}
				StopAfter({ response, exit_code }) => {
					kind: 0,
					response,
					stop: Bool.True,
					exit_code,
					file_root_id: "",
					file_relative: "",
					file_disposition: 0,
					file_download_name: "",
					file_cache_override: Bool.False,
					file_cache_tag: 0,
					file_cache_max_age_seconds: 0,
				}
			}
	}

	## Return a response and keep serving requests.
	respond : Response.Response -> Outcome
	respond = |response| Respond(response)

	## Ask the host to stream one authorized file inline, inheriting the root's
	## cache policy. The plan can only name a startup-declared root and a
	## validated relative child path.
	file_response : { files : FileRoot, relative : RelativeFile } -> Outcome
	file_response = |{ files, relative }|
		ServeFile({ files, relative, disposition: Inline, cache: Inherit })

	## Ask the host to stream one authorized file with explicit
	## disposition/cache options.
	file_response_with : {
		files : FileRoot,
		relative : RelativeFile,
		disposition : [Inline, Attachment(Str)],
		cache : CacheChoice,
	} -> Outcome
	file_response_with = |plan| ServeFile(plan)

	## Render a host-managed file inline.
	inline : [Inline, Attachment(Str)]
	inline = Inline

	## Render a host-managed file as an attachment. The host safely encodes the
	## supplied filename and prevents response-header injection.
	attachment : Str -> [Inline, Attachment(Str)]
	attachment = |name| Attachment(name)

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
		Timeout => Timeout
		ClientDisconnected => ClientDisconnected
		InvalidBody(detail) => InvalidBody(detail)
		RequestFinished => RequestFinished
		ConcurrentRead => ConcurrentRead
		Cancelled => Cancelled
	}
