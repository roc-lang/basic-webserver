import Host
import InternalHttp
import Url
import http.Request
import http.Response

## Send requests using the shared
## [`roc-lang/http`](https://github.com/roc-lang/http) `Request` and `Response`
## types. This module supplies effects and small JSON/UTF-8 conveniences while
## leaving pure request and response construction to that package.
##
## See the [host runtime behavior](https://github.com/roc-lang/basic-webserver#host-runtime-behavior)
## for HTTP protocol, TLS trust-store, and timeout details.
Http :: [].{

	## Finite defaults for ordinary API calls. The host enforces the response
	## limit before allocating the Roc response body.
	default_timeout_ms : U64
	default_timeout_ms = 30_000

	## Default maximum response body retained in memory: 8 MiB.
	default_max_response_bytes : U64
	default_max_response_bytes = 8 * 1024 * 1024

	## Opaque per-request resource policy.
	Config := [
		Config(
			{
				timeout_ms : U64,
				max_response_bytes : U64,
			},
		),
	]

	## The finite timeout and response-size policy used by [`send!`](#Http.send!).
	default_config : Config
	default_config = Config({
		timeout_ms: default_timeout_ms,
		max_response_bytes: default_max_response_bytes,
	})

	## Set the complete deadline, including bounded admission wait. Zero is
	## normalized to one millisecond so every request remains finite.
	with_timeout_millis : Config, U64 -> Config
	with_timeout_millis = |Config(config), timeout_ms|
		Config({
			..config,
			timeout_ms: if timeout_ms == 0 {
				1
			} else {
				timeout_ms
			},
		})

	## Set the maximum response body retained in memory.
	with_max_response_bytes : Config, U64 -> Config
	with_max_response_bytes = |Config(config), max_response_bytes|
		Config({ ..config, max_response_bytes })

	## Errors raised by the host while sending a request, before a real HTTP
	## response is available.
	TransportErr : InternalHttp.TransportErr

	## Validate and send an HTTP request.
	##
	## The request URI must be an absolute HTTP or HTTPS URL accepted by Url.
	## Invalid URLs return InvalidUrl before any host effect occurs. Fragments
	## are removed because they are client-side identifiers and are not sent.
	##
	## ```roc
	## request = Request.from_method(GET).with_uri("https://www.roc-lang.org")
	## response = Http.send!(request)?
	## ```
	send! : Request => Try(Response, [InvalidUrl(Url.ParseErr), InvalidRequest(Str), HttpErr(TransportErr), ..])
	send! = |request| send_with!(request, default_config)

	## Send using an explicit finite resource policy. A timeout attached to the
	## shared http Request takes precedence; NoTimeout uses this config.
	send_with! : Request, Config => Try(Response, [InvalidUrl(Url.ParseErr), InvalidRequest(Str), HttpErr(TransportErr), ..])
	send_with! = |request, config| {
		url = Url.parse(Request.uri(request)) ? InvalidUrl
		canonical_url = Url.without_fragment(url)
		canonical_request = request.with_uri(Url.to_str(canonical_url))

		send_validated!(canonical_request, config)
	}

	## Encode a value as JSON and set it as the request body.
	##
	## This uses Roc's builtin JSON encoder, so the value's type determines the
	## encoder through static dispatch.
	with_json_body : Request, _ => Try(Request, [JsonErr(_), ..])
	with_json_body = |request, value| {
		body = Json.to_str_try(value) ? JsonErr

		Ok(
			request
				.add_header("Content-Type", "application/json")
				.with_body(Str.to_utf8(body)),
		)
	}

	## Encode a value as JSON, attach it to the request body, and send it.
	send_json! : Request, _ => Try(Response, [JsonErr(_), InvalidUrl(Url.ParseErr), InvalidRequest(Str), HttpErr(TransportErr), ..])
	send_json! = |request, value| {
		json_request = with_json_body(request, value)?

		send!(json_request)
	}

	## Perform an HTTP GET and decode the response body as a UTF-8 `Str`.
	##
	## The argument is a validated Url. Quoted literals work through
	## Url.from_quote; dynamic strings should be passed through Url.parse.
	##
	## ```roc
	## hello_str = Http.get_utf8!("http://localhost:8000")?
	## ```
	get_utf8! : Url.Url => Try(Str, [BadBody(Str), InvalidRequest(Str), HttpErr(TransportErr), ..])
	get_utf8! = |url| {
		response = send_validated!(Request.from_method(GET).with_uri(Url.to_str(url)), default_config)?
		body = Str.from_utf8(Response.body(response)) ? |_| BadBody("get_utf8!: response body was not valid UTF-8")

		Ok(body)
	}

	## Decode a response body as JSON.
	##
	## This uses Roc's builtin JSON parser, so the expected result type
	## determines the parser through static dispatch.
	decode_json_response : Response => Try(_, [BadBody(Str), JsonErr(_), ..])
	decode_json_response = |response| {
		body = Str.from_utf8(Response.body(response)) ? |_| BadBody("decode_json_response: response body was not valid UTF-8")
		decoded = Json.parse(body) ? JsonErr

		Ok(decoded)
	}

	## Perform an HTTP GET and decode the response body as JSON.
	##
	## The argument is a validated Url. JSON parser failures are returned as
	## JsonErr(_).
	##
	## ```roc
	## payload : Try({ foo : Str }, _)
	## payload = Http.get!("http://localhost:8000")
	## ```
	get! : Url.Url => Try(_, [BadBody(Str), InvalidRequest(Str), HttpErr(TransportErr), JsonErr(_), ..])
	get! = |url| {
		response = send_validated!(Request.from_method(GET).with_uri(Url.to_str(url)), default_config)?

		decode_json_response(response)
	}
}

# Send a request whose URI was constructed from a validated Url. Keeping this
# private prevents get!/get_utf8! from exposing an impossible InvalidUrl error.
send_validated! : Request.Request, Http.Config => Try(Response.Response, [InvalidRequest(Str), HttpErr(InternalHttp.TransportErr), ..])
send_validated! = |request, config| {
	host_response = 
		match Host.http_send_request!(
			InternalHttp.to_host_request(
				request,
				config_timeout_millis(config),
				config_max_response_bytes(config),
			),
		) {
			Ok(response) => response
			Err(InvalidRequest(detail)) => return Err(InvalidRequest(detail))
			Err(Transport(err)) => return Err(HttpErr(err))
		}

	Ok(InternalHttp.from_host_response(host_response))
}

config_timeout_millis : Http.Config -> U64
config_timeout_millis = |Config(config)| config.timeout_ms

config_max_response_bytes : Http.Config -> U64
config_max_response_bytes = |Config(config)| config.max_response_bytes
