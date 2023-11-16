# Basic Web Server for [Roc](https://www.roc-lang.org/) 

A webserver [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) for Roc with a simple interface.

Write a function which takes a `Http.Request`, perform I/O like fetching content or reading environment variables, and return a `Http.Response`. It's that easy!

Behind the scenes, `basic-webserver` uses Rust's high-performance [hyper](https://hyper.rs) and [tokio](https://tokio.rs) libraries to execute your Roc function on incoming requests.

## Contributing

If you'd like to contribute, check out our [group chat](https://roc.zulipchat.com) and let us know what you're thinking, we're friendly!

## Example

The below [example](https://github.com/roc-lang/basic-webserver/blob/main/examples/http.roc) responds with the content of the latest Roc website.

```elixir
app "Fetch Roc website and return content"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout.{ line },
        pf.Task.{ Task, map, attempt, ok, await },
        pf.Http.{ Request, Response, methodToStr, defaultRequest, send },
        pf.Utc.{ now, toIso8601Str },
    ]
    provides [main] to pf

main = \req ->

    # Log the date, time, method, and url to stdout
    dateTime <- now |> map toIso8601Str |> await
    {} <- line "\(dateTime) \(methodToStr req.method) \(req.url)" |> await

    # Fetch the Roc website
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
            { name: "Content-Type", value: Str.toUtf8 "text/html; charset=utf-8" },
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

