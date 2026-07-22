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
- Each complete request body is buffered in memory before Roc is called, with
  no configurable body-size limit. Responses are also returned as complete
  in-memory bodies; request or response streaming is not yet available.
- Each Roc request handler runs on Tokio's blocking thread pool. There is no
  graceful-shutdown API, so deployments should treat process termination as an
  abrupt stop and drain traffic externally.
- `init!` runs once. Its model is shared read-only by all request handlers for
  the lifetime of the process; request handlers cannot return an updated model.
- A Roc `crash` exits the entire server process. Ordinary `ServerErr` values are
  logged and converted to an HTTP 500 response.

## Example

Run this example server with `roc examples/hello-web.roc` and go to `http://localhost:8000` in your browser. You can change the port and host with `ROC_BASIC_WEBSERVER_PORT` and `ROC_BASIC_WEBSERVER_HOST`.

```roc
app [Model, program] {
    pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/<version>/<hash>.tar.zst",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Http
import pf.Utc
import pf.Stdout
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || Ok({})

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, _model| {
    millis = Utc.to_millis_since_epoch(Utc.now!())

    Stdout.line!("${millis.to_str()} ${Str.inspect(req.method())} ${req.uri()}")
        ? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

    response =
        Response.from_status(200)
        .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
        .with_body(Str.to_utf8("<b>Hello from server</b></br>"))

    Ok(response)
}
```


## Contributing

If you'd like to contribute, check out our [group chat](https://roc.zulipchat.com) and let us know what you're thinking, we're friendly!

## Running Locally

If you have cloned this repository and want to run the examples without using a packaged release, build the platform first:

```bash
./build.sh
```

Then run examples with `roc examples/hello-web.roc`.

Use `./build.sh --target <target>` to build a specific host library, or
`./build.sh --all` to build all macOS and Linux host libraries. Windows host
inputs must be built on Windows. Release packages use `.tar.zst` assets.

Run the complete local verification suite with:

```bash
./ci/all_tests.sh
```

To build a release-format package after assembling all target inputs, run
`./scripts/bundle.py --output-dir dist`. Windows inputs must be built on a
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
