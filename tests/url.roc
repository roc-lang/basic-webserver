app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Stdout
import pf.Url
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
            Stdout.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

# Pure Url behavior has comprehensive inline expects in platform/Url.roc. This
# executable keeps a small integration check for quoted literals, dynamic
# validation, builders, resolution, and duplicate query parameters.
run_tests! : () => Try({}, _)
run_tests! = || {
    literal : Url.Url
    literal = "https://Example.COM:443/a/../hello%20world?q=roc#frag"
    canonical = Url.to_str(literal)
    expect_equal(canonical, "https://example.com/hello%20world?q=roc#frag")?
    Stdout.line!("Canonical literal: ${canonical}") ?? {}

    base = Url.parse("http://127.0.0.1:8080/base/") ? |err| FailedExpectation(Str.inspect(err))
    built = base
        .append_path_segments(["api", "todo item"])
        .append_query_param("status", "in progress")
    built_str = Url.to_str(built)
    expect_equal(built_str, "http://127.0.0.1:8080/base/api/todo%20item?status=in+progress")?
    Stdout.line!("Built URL: ${built_str}") ?? {}

    resolved = Url.resolve(base, "/todos?task=write+tests&task=ship") ? |err| FailedExpectation(Str.inspect(err))
    expect_true(
        Url.query_pairs(resolved) == [("task", "write tests"), ("task", "ship")],
        "query pairs should decode plus signs and preserve duplicates",
    )?
    Stdout.line!("Resolved URL: ${Url.to_str(resolved)}") ?? {}

    expect_missing_scheme!("/relative-only")?
    Stdout.line!("Rejected relative URL without a base.") ?? {}

    Ok({})
}

expect_missing_scheme! : Str => Try({}, [FailedExpectation(Str)])
expect_missing_scheme! = |input|
    match Url.parse(input) {
        Err(MissingScheme) => Ok({})
        Err(err) => Err(FailedExpectation("Expected MissingScheme, got ${Str.inspect(err)}"))
        Ok(url) => Err(FailedExpectation("Expected rejection, got ${Url.to_str(url)}"))
    }

expect_equal : Str, Str -> Try({}, [FailedExpectation(Str)])
expect_equal = |actual, expected|
    expect_true(actual == expected, "Expected ${expected}, got ${actual}")

expect_true : Bool, Str -> Try({}, [FailedExpectation(Str)])
expect_true = |condition, message|
    if condition { Ok({}) } else { Err(FailedExpectation(message)) }


respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, _state|
    Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("I am a test."))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
