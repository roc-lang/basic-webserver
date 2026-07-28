[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

Documentation: [0.14.0-rc1](https://roc-lang.github.io/basic-webserver/0.14.0-rc1/), [main](https://roc-lang.github.io/basic-webserver/main/)

Examples: [0.14.0-rc1](https://github.com/roc-lang/basic-webserver/tree/0.14.0-rc1/examples), [main](https://github.com/roc-lang/basic-webserver/tree/main/examples)

# Basic Web Server for Roc

`basic-webserver` is a cross-platform [Roc platform](https://www.roc-lang.org/platforms)
for conventional HTTP request/response applications. It is designed for JSON
and HTML APIs, SQLite-backed applications, server-rendered forms, webhooks,
bounded uploads, and small services deployed behind a reverse proxy.

The Rust host uses [Hyper](https://hyper.rs) and [Tokio](https://tokio.rs).
Applications provide three functions:

- `init!` validates startup configuration and returns `Server.Config` plus an
  immutable application context;
- `respond!` handles each request, potentially concurrently with other
  handlers; and
- `shutdown!` runs once after the server has stopped accepting and draining
  work.

Durable mutable state belongs in SQLite or an external service. The platform
does not route requests through a global mutable application model.

> `main` and the 0.14 release candidates target Roc's new Zig-based compiler.
> The old Rust-based compiler is not supported.

## Quick start

Save the following as `hello.roc`, then run `roc hello.roc` and open
<http://127.0.0.1:8000>.

```roc
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.14.0-rc1/GfM5qZLcKYGA9XD4V7u1S4RjWrdfws29Uz2m86C7bmUC.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, _context|
	Ok(
		Server.respond(
			Response.from_status(200)
				.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
				.with_body(Str.to_utf8("<b>Hello from Roc!</b>")),
		),
	)

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
```

`Server.default_config` listens only on `127.0.0.1:8000`. Use
`Server.Config.with_listen` to choose another address. See
[`examples/`](https://github.com/roc-lang/basic-webserver/tree/main/examples)
for request bodies, forms, SQLite, outbound HTTP, commands, files, TCP, and
error handling.

## Runtime contract

The defaults are finite so overload has deliberate behavior:

| Resource | Default |
| --- | ---: |
| Active connections | 256 |
| Concurrent Roc handlers | 32 |
| Queued handlers | 64 |
| Request target | 8 KiB |
| Decoded request headers | 32 KiB |
| Request header fields | 100 |
| Request body | 1 MiB |
| Request body chunk | 64 KiB |
| Buffered body chunks per request | 1 |
| Graceful request drain | 30 seconds |
| Shutdown hook | 10 seconds |

When every handler and queue slot is occupied, new requests receive HTTP 503.
Applications can change these limits with the `Server.Config` builders and can
narrow an individual body limit with `request.body().with_limit(...)`.
Request-target and header limits are checked before host-native routing or Roc.
Decoded header bytes use `name + value + 32` bytes per ordinary field for both
HTTP versions, so HTTP/2 HPACK compression does not weaken the resource bound.

The listener accepts HTTP/1.1 and cleartext prior-knowledge HTTP/2. It does not
terminate TLS or perform public protocol negotiation; production deployments
normally put a reverse proxy or load balancer in front. Ordinary responses are
complete in-memory values, while request bodies can be consumed as bounded
streams. The host validates response fields and owns framing for both protocol
versions; see the [response design](design.md#response-validation-and-framing).

Eligible responses of at least 1 KiB are compressed automatically when the
client accepts Zstandard, Brotli, or gzip. The host negotiates quality weights,
emits `Vary: Accept-Encoding`, leaves range and already encoded responses
unchanged, and streams compressed native files without buffering them in
memory. At equal quality weights, it prefers Zstandard, then Brotli, then gzip.
In-memory responses larger than 8 MiB are left as identity to bound the
temporary compressed copy. Applications can set `Cache-Control: no-transform`
to opt a response out. Compressed request bodies are not decoded automatically.

Every handler receives an owned reference to the immutable context produced by
`init!`. `StopAfter` outcomes and OS termination signals begin graceful
shutdown. The host stops accepting work, drains active handlers within the
configured deadline, and then invokes `shutdown!`. A drain or hook timeout
forces exit because it is unsafe to destroy context still used by Roc code.

An error returned by `respond!` is inspected and logged with request context,
then converted to a generic HTTP 500 response. Errors from `init!` and
`shutdown!` are logged before the process exits. A Roc `crash` exits the whole
server process.

## Platform facilities

The platform exposes typed modules for:

- bounded inbound request bodies and server lifecycle;
- pooled outbound HTTP and HTTPS requests;
- pooled SQLite connections, transactions, and prepared statements;
- finite command execution with time and output limits;
- filesystem, environment, path, stdout/stderr, TCP, time, and sleep effects;
- HTML construction, URL handling, and multipart form parsing.

`UnixTime` provides the POSIX wall-clock effect and normalized timestamps,
including nanosecond precision and instants before the Unix epoch. Calendar
systems, time zones, and text formatting are deliberately left to the Roc
package ecosystem. The time-using examples demonstrate converting
`UnixTime.Timestamp` values with
[`roc-gregorian`](https://git.sr.ht/~jwoudenberg/roc/tree/main/item/gregorian).

Outbound HTTP calls default to a 30-second total deadline and an 8 MiB response
body. At most 64 calls run and 256 wait for admission. The shared client pools
connections, performs no hidden retries, and uses WebPKI roots for HTTPS.

Commands execute an exact program and argument list without shell expansion.
They default to a 30-second deadline and 1 MiB each of captured stdout and
stderr. At most eight commands run and 32 wait for admission.

The generated [API documentation](https://roc-lang.github.io/basic-webserver/main/)
contains the complete types, builders, limits, and error tags.

## Supported targets

The platform builds and runs these targets in CI:

| Roc target | Operating system | Architecture |
| --- | --- | --- |
| `x64mac` | macOS | x86-64 |
| `arm64mac` | macOS | ARM64 |
| `x64musl` | Linux (musl) | x86-64 |
| `arm64musl` | Linux (musl) | ARM64 |
| `x64win` | Windows | x86-64 |

Other targets are not currently supported.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, verification, testing,
documentation, benchmarking, generated glue, and release workflows. Questions
and early design discussions are welcome in the [Roc Zulip
chat](https://roc.zulipchat.com).
