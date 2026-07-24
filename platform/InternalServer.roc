import Server
import http.Header
import http.Method
import http.Response

## Host-ABI records and conversions for inbound server lifecycle operations.
## Outbound HTTP remains entirely in InternalHttp.
InternalServer :: [].{
	HostHeader : { name : Str, value : Str }

	RequestFromHost : {
		method : U8,
		method_ext : Str,
		headers : List(HostHeader),
		target : Str,
		body_id : U64,
		body_limit_bytes : U64,
		content_length_known : Bool,
		content_length : U64,
	}

	OutcomeToHost : {
		status : U16,
		headers : List(HostHeader),
		body : List(U8),
		stop : Bool,
		exit_code : I64,
	}

	ConfigToHost : {
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

	ShutdownReasonFromHost : {
		tag : U8,
		detail : Str,
	}

	from_host_request : RequestFromHost -> Server.Request
	from_host_request = |{ method, method_ext, headers, target, body_id, body_limit_bytes, content_length_known, content_length }|
		Server.Request.from_host(
			from_host_method(method, method_ext),
			headers.map(from_host_header),
			target,
			Server.Body.from_host(
				body_id,
				body_limit_bytes,
				if content_length_known {
					Known(content_length)
				} else {
					Unknown
				},
			),
		)

	to_host_outcome : Server.Outcome -> OutcomeToHost
	to_host_outcome = |outcome| {
		{ response, stop, exit_code } = Server.Outcome.to_host(outcome)
		response_to_host(response, stop, exit_code)
	}

	response_to_host : Response.Response, Bool, I64 -> OutcomeToHost
	response_to_host = |response, stop, exit_code| {
		status: Response.status(response),
		headers: Response.headers(response).map(to_host_header),
		body: Response.body(response),
		stop,
		exit_code,
	}

	to_host_config : Server.Config -> ConfigToHost
	to_host_config = |config| {
		listen = Server.Config.get_listen(config)
		request_bodies = Server.Config.request_body_limits(config)
		graceful_shutdown = Server.Config.get_graceful_shutdown(config)
		limits = Server.Config.get_limits(config)

		{
			host: listen.host,
			port: listen.port,
			body_max_bytes: request_bodies.max_bytes,
			body_chunk_bytes: request_bodies.chunk_bytes,
			body_buffered_chunks: request_bodies.buffered_chunks,
			drain_timeout_ms: graceful_shutdown.drain_timeout_ms,
			hook_timeout_ms: graceful_shutdown.hook_timeout_ms,
			max_connections: limits.max_connections,
			max_handlers: limits.max_handlers,
			max_queued_handlers: limits.max_queued_handlers,
		}
	}

	from_host_shutdown_reason : ShutdownReasonFromHost -> Server.ShutdownReason
	from_host_shutdown_reason = |{ tag, detail }|
		match tag {
			0 => ApplicationRequested
			1 => Interrupt
			2 => Terminate
			3 => StartupFailed(detail)
			4 => RuntimeFailed(detail)
			_ => RuntimeFailed("host supplied an invalid shutdown reason")
		}

	from_host_method : U8, Str -> Method.Method
	from_host_method = |tag, ext|
		match tag {
			0 => CONNECT
			1 => DELETE
			2 => Unknown(ext)
			3 => GET
			4 => HEAD
			5 => OPTIONS
			6 => PATCH
			7 => POST
			8 => PUT
			9 => TRACE
			10 => QUERY
			_ => Unknown(ext)
		}

	to_host_header : Header.Header -> HostHeader
	to_host_header = |header| { name: header.name, value: header.value }

	from_host_header : HostHeader -> Header.Header
	from_host_header = |{ name, value }| { name, value }
}
