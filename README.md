[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

:book: docs: [0.13.1](https://roc-lang.github.io/basic-webserver/0.13.1/), [0.13.0](https://roc-lang.github.io/basic-webserver/0.13.0/), [main branch](https://roc-lang.github.io/basic-webserver/main/)

:eyes: examples: [0.13.1](https://github.com/roc-lang/basic-webserver/tree/0.13.1/examples), [0.13.0](https://github.com/roc-lang/basic-webserver/tree/0.13.0/examples), [main branch](https://github.com/roc-lang/basic-webserver/tree/main/examples)

# Basic Web Server for [Roc](https://www.roc-lang.org/)

A webserver [platform](https://www.roc-lang.org/platforms) with a simple interface.

:racing_car: basic-webserver uses Rust's high-performance [hyper](https://hyper.rs) and [tokio](https://tokio.rs) libraries to execute your Roc function on incoming requests.

## Supported targets

The platform builds and runs on these targets in CI:

| Roc target | Operating system | Architecture |
| --- | --- | --- |
| `x64mac` | macOS | x86-64 |
| `arm64mac` | macOS | ARM64 |
| `x64musl` | Linux (musl) | x86-64 |
| `arm64musl` | Linux (musl) | ARM64 |
| `x64win` | Windows | x86-64 |

Other targets are not currently supported. In particular, Windows support is
x86-64 only.

## Host runtime behavior

These current host-level constraints matter when designing a production
server:

- The server accepts HTTP/1 connections only. It does not terminate TLS; put a
  reverse proxy or load balancer in front when HTTPS is required.
- Request bodies are bounded streams. The defaults allow at most 1 MiB per
  request, deliver chunks no larger than 64 KiB, and buffer one chunk between
  Hyper and Roc. Applications can narrow a request's limit with
  `request.body().with_limit(...)`. Responses are currently complete in-memory
  bodies; response streaming is not yet available.
- Request handlers run concurrently on Tokio's blocking thread pool. Every
  handler receives an owned reference to the same immutable application
  context. Durable mutable state belongs in SQLite or an external service, so
  requests do not pass through a global application-state coordinator.
- `init!` returns the server configuration and immutable context. On SIGINT,
  SIGTERM, or an application `StopAfter` outcome, the host stops accepting new
  connections, drains active work up to the configured timeout, cancels
  outstanding body streams when that timeout expires, and calls `shutdown!`
  once with the context after a successful drain. If the drain deadline or
  shutdown-hook deadline expires, the host forces exit with status 1; a drain
  timeout cannot safely run `shutdown!` while a Roc handler may still be using
  the context. A second OS termination signal also forces exit.
- Outbound requests require validated `Url` values in the convenience APIs and
  report typed DNS, connection, TLS, exchange, response-body, cancellation,
  timeout, and invalid-response failures. A shared client preserves connection
  pooling and HTTP keep-alive across calls. HTTPS uses WebPKI roots; custom trust
  stores are not currently configurable.
- A Roc `crash` exits the entire server process. Ordinary `ServerErr` values are
  logged and converted to an HTTP 500 response.

## Example

Run this example server with `roc examples/hello-web.roc` and go to
`http://localhost:8000` in your browser. Set `Server.Config.listen` in `init!`
to choose another interface or port.

```roc
app [Context, program] {
    pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/<version>/<hash>.tar.zst",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Utc
import pf.Stdout
import http.Response

Context : { greeting : Str }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: { greeting: "Hello from server" } })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, context| {
    millis = Utc.to_millis_since_epoch(Utc.now!())

    Stdout.line!("${millis.to_str()} ${Str.inspect(req.method())} ${req.target()}")
        ? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

    response =
        Response.from_status(200)
        .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
        .with_body(Str.to_utf8("<b>${context.greeting}</b>"))

    Ok(Server.respond(response))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _context| Ok({})
```


## Contributing

If you'd like to contribute, check out our [group chat](https://roc.zulipchat.com) and let us know what you're thinking, we're friendly!

## Running Locally

If you have cloned this repository and want to run the examples without using a packaged release, build the platform first:

```sh
python scripts/build.py
```

Then run examples with `roc examples/hello-web.roc`.

Use `python scripts/build.py --target <target>` to build a specific host library, or
`python scripts/build.py --all` to build all macOS and Linux host libraries. Windows host
inputs must be built on Windows. Release packages use `.tar.zst` assets.

Run the complete local verification suite with:

```sh
python scripts/test.py
```

The suite uses Python's standard library to format, check, test, and build each
active example, then drives its real HTTP listener using the cases in
`scripts/test_spec.json`. The same cases and expected results run on Linux,
macOS, and Windows; it does not require Expect or curl.

CI first builds the host inputs for every supported Roc target. Every supported
compiler host then cross-builds all active examples for every target. Fresh
native runner jobs download and execute every independently produced binary set
for their target. Artifact manifests bind each set to its compiler host, target,
example sources, and test specification, ensuring the runtime suite exercises
all uploaded cross-build outputs rather than silently rebuilding them.

To build a release-format package after assembling all target inputs, run
`python scripts/bundle.py --output-dir dist`. Windows inputs must be built on a
Windows host; the release workflow combines them with the macOS and Linux
inputs automatically.

## Benchmarking

Basic webserver should have decent performance due to being built on top of Rust's [hyper](https://hyper.rs).
That said, it has a few known issues that hurt performance:
1. We do [extra data copying on every request](https://github.com/roc-lang/basic-webserver/issues/23).
2. Until roc has effect interpreters, basic-webserver can only do blocking io for effects. To work around this, every request is spawned in a blocking thread.

That said, running benchmarks and debugging performance is still a great idea. It can help improve both Roc and basic-webserver.

Lots of load generators exist. Generally, it is advised to use one that avoids [coordinated omission](https://www.youtube.com/watch?v=lJ8ydIuPFeU).
A trusted generator that fits this criteria is [wrk2](https://github.com/giltene/wrk2) (sadly doesn't work on Apple Silicon).

If you are benchmarking on a single machine, you can use the `TOKIO_WORKER_THREADS` environment variable to limit parallelism of the webserver.

> Note: When benchmarking, it is best to run the load generator and the webserver on different machines.

When benchmarking on a single 8 core machine with `wrk2`, these commands could be used (simply tune connections `-c` and rate `-R`):
1. Optimized build: `roc build --opt=speed my-webserver.roc`
2. Launch server with 4 cores: `TOKIO_WORKER_THREADS=4 ./my-webserver`
3. Generate load with 4 cores: `wrk -t4 -c100 -d30s -R2000 http://127.0.0.1:8000`
