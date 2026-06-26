app [Model, init!, respond!] {
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.13.0/RqendgZw5e1RsQa3kFhgtnMP8efWoqGRsAvubx4-zus.tar.br",
}

import pf.Stdout
import pf.Http exposing [Request, Response]
import json.Json

# Demo of all basic-webserver Http functions

# To run this example: 
# ```
# git clone --depth 1 https://github.com/roc-lang/basic-cli.git
# cd basic-cli
# nix develop
# cd ci/rust_http_server
# cargo run
# ```
# Then in another terminal: follow the steps in the README.md file of this folder.

# Model is produced by `init`.
Model : {}

init! : {} => Result Model _
init! = |{}|
    # # HTTP GET a String
    #   ----------------

    hello_str : Str
    hello_str = Http.get_utf8!("http://localhost:9000/utf8test")?
    # If you want to see an example of the server side, see basic-cli/ci/rust_http_server/src/main.rs

    Stdout.line!("I received '${hello_str}' from the server.\n")?

    # # Getting json
    #   ------------

    # We decode/deserialize the json `{ "foo": "something" }` into a Roc record

    { foo } = Http.get!("http://localhost:9000", Json.utf8)?
    # If you want to see an example of the server side, see basic-cli/ci/rust_http_server/src/main.rs

    Stdout.line!("The json I received was: { foo: \"$(foo)\" }\n")?

    # # Getting a Response record
    #   -------------------------

    response : Http.Response
    response = Http.send!(
        {
            method: GET,
            headers: [],
            uri: "https://www.example.com",
            body: [],
            timeout_ms: TimeoutMilliseconds(5000),
        },
    )?

    body_str = (Str.from_utf8(response.body))?

    Stdout.line!("Response body:\n\t${body_str}.\n")?

    # # Using default_request and providing a header
    #   --------------------------------------------
    
    response_2 =
        Http.default_request
        |> &uri "https://www.example.com"
        |> &headers [Http.header(("Accept", "text/html"))]
        |> Http.send!()?

    body_str_2 = (Str.from_utf8(response_2.body))?

    # Same as above
    Stdout.line!("Response body 2:\n\t${body_str_2}.\n")?

    Ok({})

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |_req, _model|
    Ok(
        {
            status: 200,
            headers: [],
            body: Str.to_utf8("See init! for the example code."),
        },
    )

