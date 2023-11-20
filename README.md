# Basic Web Server for [Roc](https://www.roc-lang.org/) 

A webserver [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) with a simple interface.

Write a function which takes a `Http.Request`, perform I/O like fetching content or reading environment variables, and return a `Http.Response`. It's that easy!

Behind the scenes, `basic-webserver` uses Rust's high-performance [hyper](https://hyper.rs) and [tokio](https://tokio.rs) libraries to execute your Roc function on incoming requests.

## Example

The below example returns the body that was provided in the HTTP request:

```elixir
app "echo"
    packages { pf: "https://github.com/roc-lang/basic-webserver/releases/download/0.1/dCL3KsovvV-8A5D_W_0X_abynkcRcoAngsgF0xtvQsk.tar.br" }
    imports [
        pf.Stdout,
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.Utc,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \req ->

    # Log request date, method and url
    date <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await
    {} <- Stdout.line "\(date) \(Http.methodToStr req.method) \(req.url)" |> Task.await

    # Respond with request body
    when req.body is
        EmptyBody -> Task.ok { status: 200, headers: [], body: [] }
        Body internal -> Task.ok { status: 200, headers: [], body: internal.body }
```

Run this example server with `$ roc run echo.roc`

Then visit `http://localhost:8000` with your browser.

## Contributing

If you'd like to contribute, check out our [group chat](https://roc.zulipchat.com) and let us know what you're thinking, we're friendly!

## Steps to re-generate glue

Run the following from the repository root directory.

1. Run `bash platform/glue-gen.sh`
2. Manually fix any issues with glue generated code in `platform/glue-manual/*.rs`, this is a temporary workaround and should not be needed in future
