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
		kind : U8,
		file_root_id : Str,
		file_relative : Str,
		file_disposition : U8,
		file_download_name : Str,
		file_cache_override : Bool,
		file_cache_tag : U8,
		file_cache_max_age_seconds : U32,
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
		native_routes : List(
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
		file_max_concurrent : U16,
		file_chunk_bytes : U32,
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
		raw = Server.Outcome.to_host(outcome)
		response_to_host(raw)
	}

	response_to_host : {
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
	} -> OutcomeToHost
	response_to_host = |raw| {
		status: Response.status(raw.response),
		headers: Response.headers(raw.response).map(to_host_header),
		body: Response.body(raw.response),
		stop: raw.stop,
		exit_code: raw.exit_code,
		kind: raw.kind,
		file_root_id: raw.file_root_id,
		file_relative: raw.file_relative,
		file_disposition: raw.file_disposition,
		file_download_name: raw.file_download_name,
		file_cache_override: raw.file_cache_override,
		file_cache_tag: raw.file_cache_tag,
		file_cache_max_age_seconds: raw.file_cache_max_age_seconds,
	}

	to_host_config : Server.Config -> ConfigToHost
	to_host_config = |config| Server.Config.to_host(config)

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
