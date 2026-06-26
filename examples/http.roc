# Demo of the basic-webserver outbound HTTP client (Http.send! / Http.get_utf8!).
app [Model, program] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http

Model : {}

program = { init!, respond! }

# Fetch some content at startup to demonstrate the outbound HTTP client. To
# exercise it, run a server on localhost:9000 (see the README); otherwise the
# requests simply report a failure and the webserver still starts.
init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| {
    _ = demo!({})
    Ok({})
}

demo! : {} => Try({}, _)
demo! = |{}| {
    # GET a plain-text body and decode it as UTF-8.
    _ = match Http.get_utf8!("http://localhost:9000/utf8test") {
        Ok(utf8) => Stdout.line!("I received '${utf8}' from the server.")
        Err(_) => Stdout.line!("GET /utf8test failed (is a server running on :9000?)")
    }

    # Use send! with a custom header and inspect the Response record.
    request = {
        ..Http.default_request,
        uri: "http://localhost:9000/utf8test",
        headers: [Http.header(("Accept", "text/plain"))],
        timeout_ms: TimeoutMilliseconds(5000),
    }
    match Http.send!(request) {
        Ok(response) => {
            _ = Stdout.line!("send! returned status ${Str.inspect(response.status)}.")
            Ok({})
        }
        Err(HttpErr(_)) => {
            _ = Stdout.line!("send! failed")
            Ok({})
        }
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok({
        status: 200,
        headers: [],
        body: Str.to_utf8("See init! for the outbound HTTP example code."),
    })
