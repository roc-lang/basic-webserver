:book: docs: [main branch](https://roc-lang.github.io/basic-webserver/)

:eyes: examples: [0.4](https://github.com/roc-lang/basic-webserver/tree/0.4.0/examples), [0.3](https://github.com/roc-lang/basic-webserver/tree/0.3.0/examples), [0.2](https://github.com/roc-lang/basic-webserver/tree/0.2.0/examples), [0.1](https://github.com/roc-lang/basic-webserver/tree/0.1/examples)

:warning: On linux `--linker=legacy` is necessary for this package because of [this Roc issue](https://github.com/roc-lang/roc/issues/3609).

# Basic Web Server for [Roc](https://www.roc-lang.org/)

A webserver [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) with a simple interface.

Write a function which takes a `Http.Request`, perform I/O like fetching content or reading environment variables, and return a `Http.Response`. It's that easy!

Behind the scenes, `basic-webserver` uses Rust's high-performance [hyper](https://hyper.rs) and [tokio](https://tokio.rs) libraries to execute your Roc function on incoming requests.

## Example

To run any of the examples, you will need to get [the latest release URL](https://github.com/roc-lang/basic-webserver/releases) which is named using a hash of the file contents, e.g. "Vq-iXfrRf-aHxhJpAh71uoVUlC-rsWvmjzTYOJKhu4M.tar.br". You can usually right-click in your browser to copy the link URL.

Then you need to replace the local path to the platform `"../platform/main.roc"` with the URL you copied in the `app` block of the Roc file.

```roc
app [main] {
    # replaced the pf: "../platform/main.roc" with the following
     pf: platform "https://github.com/roc-lang/basic-webserver/releases/<latest release hash>.tar.br"
}

import pf.Stdout
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Utc

main : Request -> Task Response []
main = \req ->

    # Log request date, method and url
    date = Utc.now! |> Utc.toIso8601Str
    Stdout.line! "$(date) $(Http.methodToStr req.method) $(req.url)"

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "<b>Hello, world!</b>\n" }

```

Run this example server with `$ roc helloweb.roc` (note for linux you will need `--linker=legacy`) and go to `http://localhost:8000` in your browser.

## Contributing

If you'd like to contribute, check out our [group chat](https://roc.zulipchat.com) and let us know what you're thinking, we're friendly!

## Developing / Building Locally

If you have cloned this repository and want to run the examples without using a packaged release, you will need to build the platform first as the roc cli is not aware of the host toolchain.

First run `roc build.roc`, which will generate the pre-built binaries for your native target.

Then you will be able to run an example that is using the platform from a local path. For example `roc run examples/hello.roc` will run the echo example, and in this file the header is referencing the platform locally `app [main] { pf: platform "../platform/main.roc" }`.
