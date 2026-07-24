app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.MultipartFormData
import pf.Stderr
import pf.Stdout
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            Stdout.line!("Ran all tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    Stdout.line!("Testing parse_form_url_encoded preserves literal plus signs.")?

    encoded = "message=This+%2B+is+a+plus"
    Stdout.line!("Encoded input: ${encoded}")?

    dict =
        MultipartFormData.parse_form_url_encoded(Str.to_utf8(encoded))
            ? |_| FailedExpectation("Failed to parse URL-encoded form data.")

    message = Dict.get(dict, "message") ? |_| FailedExpectation("Missing message field.")

    Stdout.line!("Decoded message: ${message}")?

    expected = "This + is a plus"
    Stdout.line!("Expected message: ${expected}")?

    if message == expected {
        Stdout.line!("Message decoded as expected.")?
        Ok({})
    } else {
        Stdout.line!("Message decoded incorrectly.")?
        Err(FailedExpectation("Decoded message mismatch: expected '${expected}' but got '${message}'."))
    }
}


respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, _state|
    Ok(Server.respond(Response.from_status(404)))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
