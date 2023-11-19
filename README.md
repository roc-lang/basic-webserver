# Basic Web Server for [Roc](https://www.roc-lang.org/) 

A webserver [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) for Roc with a simple interface.

Write a function which takes a `Http.Request`, perform I/O like fetching content or reading environment variables, and return a `Http.Response`. It's that easy!

Behind the scenes, `basic-webserver` uses Rust's high-performance [hyper](https://hyper.rs) and [tokio](https://tokio.rs) libraries to execute your Roc function on incoming requests.

## Contributing

If you'd like to contribute, check out our [group chat](https://roc.zulipchat.com) and let us know what you're thinking, we're friendly!

## Example

The below [example](https://github.com/roc-lang/basic-webserver/blob/main/examples/http.roc) responds with the content of the latest Roc website.

```elixir
main : Request -> Task Response []
main = \req ->

    # Log the date, time, method, and url to stdout
    dateTime <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await
    {} <- Stdout.line "\(dateTime) \(Http.methodToStr req.method) \(req.url)" |> Task.await

    # Fetch the Roc website
    result <-
        { Http.defaultRequest & url: "https://www.roc-lang.org" }
        |> Http.send
        |> Task.attempt

    # Respond with the website content
    when result is
        Ok str -> respond 200 str
        Err _ -> respond 500 "Error 500 Internal Server Error\n"

respond : U16, Str -> Task Response []
respond = \code, body ->
    Task.ok {
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

## Steps to re-generate glue

Run the following from the repository root directory.

1. In `platform/main.roc` comment out the lines as indicated
2. Run `bash platform/glue-gen.sh`
4. Restore commented lines in `platform/main.roc`
