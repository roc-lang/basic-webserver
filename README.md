[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

:book: docs: [main branch](https://roc-lang.github.io/basic-webserver/)

:eyes: examples: [0.12](https://github.com/roc-lang/basic-webserver/tree/0.12.0/examples), [0.11](https://github.com/roc-lang/basic-webserver/tree/0.11.0/examples), [0.10](https://github.com/roc-lang/basic-webserver/tree/0.10.0/examples) 

:warning: On linux `--linker=legacy` is necessary for this package because of [this Roc issue](https://github.com/roc-lang/roc/issues/3609).

# Basic Web Server for [Roc](https://www.roc-lang.org/)

A webserver [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) with a simple interface.

:racing_car: basic-webserver uses Rust's high-performance [hyper](https://hyper.rs) and [tokio](https://tokio.rs) libraries to execute your Roc function on incoming requests.

## Example

Run this example server with `$ roc hello-web.roc` (on linux, add `--linker=legacy`) and go to `http://localhost:8000` in your browser. You can change the port (8000) and the host (localhost) by setting the environment variables ROC_BASIC_WEBSERVER_PORT and ROC_BASIC_WEBSERVER_HOST.

```roc
app [Model, init!, respond!] { pf: platform "<latest release URL from https://github.com/roc-lang/basic-webserver/releases/latest>" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Utc

# Model is produced by `init`.
Model : {}

# With `init` you can set up a database connection once at server startup,
# generate css by running `tailwindcss`,...
# In this case we don't have anything to initialize, so it is just `Ok {}`.
init! : {} => Result Model []
init! = \{} -> Ok {}

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = \req, _ ->
    # Log request datetime, method and url
    datetime = Utc.to_iso_8601 (Utc.now! {})

    try Stdout.line! "$(datetime) $(Inspect.toStr req.method) $(req.uri)"

    Ok {
        status: 200,
        headers: [],
        body: Str.toUtf8 "<b>Hello from server</b></br>",
    }
```


## Contributing

If you'd like to contribute, check out our [group chat](https://roc.zulipchat.com) and let us know what you're thinking, we're friendly!

## Developing / Building Locally

If you have cloned this repository and want to run the examples without using a packaged release (...tar.br), you will need to build the platform first by running `roc build.roc`. Run examples with `roc examples/hello.roc` (on linux, add `--linker=legacy`).

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
1. Optimized Build: `roc build --optimize my-webserver.roc --linker=legacy`
2. Launch server with 4 cores: `TOKIO_WORKER_THREADS=4 ./my-webserver`
3. Generate load with 4 cores: `wrk -t4 -c100 -d30s -R2000 http://127.0.0.1:8000`
