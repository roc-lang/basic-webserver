# Basic Web Server for [Roc](https://www.roc-lang.org/) 

A webserver [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) for Roc with a simple interface.

Write a function which takes a `Http.Request`, perform I/O like fetching content or reading environment variables, and return a `Http.Response`. It's that easy!

Behind the scenes, `basic-webserver` uses Rust's high-performance [hyper](https://hyper.rs) and [tokio](https://tokio.rs) libraries to execute your Roc function on incoming requests.

## Contributing

If you'd like to contribute, check out our [group chat](https://roc.zulipchat.com) and let us know what you're thinking, we're friendly!

## Example

This is a simple example of a Roc function which fetches and responds with the content of the Roc website.

```elixir
app "app"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Task.{ Task, attempt, ok },
        pf.Http.{ Request, Response, defaultRequest, send },
    ]
    provides [main] to pf

main = \_ ->

    # Send an HTTP request to fetch the Roc website
    result <-
        { defaultRequest & url: "https://www.roc-lang.org" }
        |> send
        |> attempt

    # Respond with the website content
    when result is
        Ok str -> respond 200 str
        Err _ -> respond 500 "Error 500 Internal Server Error\n"

respond = \code, body -> 
    ok { 
        status: code, 
        headers: [
            { name : "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" } 
        ], 
        body: Str.toUtf8 body,
    }
```

## Getting Started 

### Packaged Release 

> This platform is a Work In Progress and doesn't have a URL Package Release yet. There are no known issues, it just requires some setup for CI to build the platform for our supported architectures.

Let us know if you'd like to help out with this!

### Building from Source

You will need [Rust](https://www.rust-lang.org) to build the platform source code.

Run an example server with `$ roc run examples/http.roc`

Then visit `http://localhost:8000` with your browser.

