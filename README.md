:book: docs: [main branch](https://roc-lang.github.io/basic-webserver/)

:eyes: examples: [0.4](https://github.com/roc-lang/basic-webserver/tree/0.4.0/examples), [0.3](https://github.com/roc-lang/basic-webserver/tree/0.3.0/examples), [0.2](https://github.com/roc-lang/basic-webserver/tree/0.2.0/examples), [0.1](https://github.com/roc-lang/basic-webserver/tree/0.1/examples)

:warning: On linux `--linker=legacy` is necessary for this package because of [this Roc issue](https://github.com/roc-lang/roc/issues/3609).

# Basic Web Server for [Roc](https://www.roc-lang.org/)

A webserver [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) with a simple interface.

:racing_car: basic-webserver uses Rust's high-performance [hyper](https://hyper.rs) and [tokio](https://tokio.rs) libraries to execute your Roc function on incoming requests.

## Example

Run this example server with `$ roc helloweb.roc` (on linux, add `--linker=legacy`) and go to `http://localhost:8000` in your browser. You can change the port (8000) and the host (localhost) by setting the environment variables ROC_BASIC_WEBSERVER_PORT and ROC_BASIC_WEBSERVER_HOST.

```roc
app [Model, server] {
     pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.7.0/vUnq0H5KAITUGuzI3av6AHYLS8LnaYI6qzIMsTNHq3M.tar.br"
}

import pf.Stdout
import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Utc

Model : Str

server = { init, respond }

init : Task Model [Exit I32 Str]_
init =
    Stdout.line! "SERVER INFO: Doing stuff before the server starts..."
    Task.ok "This is from init!"

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \req, model ->
    # Log request datetime, method and url
    datetime = Utc.now! |> Utc.toIso8601Str

    Stdout.line! "$(datetime) $(Http.methodToStr req.method) $(req.url)"

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "<b>Hello, world!</b></br>$(model)" }

```


## Contributing

If you'd like to contribute, check out our [group chat](https://roc.zulipchat.com) and let us know what you're thinking, we're friendly!

## Developing / Building Locally

If you have cloned this repository and want to run the examples without using a packaged release (...tar.br), you will need to build the platform first by running `roc build.roc`. Run examples with `roc examples/hello.roc` (on linux, add `--linker=legacy`).
