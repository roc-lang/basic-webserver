app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Http
import pf.Sleep
import pf.Stderr
import pf.Stdout
import pf.Utc
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            Stdout.line!("Ran all Utc tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    test_time_conversion!()?
    test_time_delta!()
}

test_time_conversion! : () => Try({}, _)
test_time_conversion! = || {
    now = Utc.now!()

    millis_since_epoch = Utc.to_millis_since_epoch(now)
    time_from_millis = Utc.from_millis_since_epoch(millis_since_epoch)
    expect_true(Utc.to_iso_8601(time_from_millis) == Utc.to_iso_8601(now), "millisecond round-trip should preserve ISO seconds")?

    nanos_since_epoch = Utc.to_nanos_since_epoch(now)
    expect_true(nanos_since_epoch >= millis_since_epoch * 1_000_000, "nanoseconds should be at least milliseconds * 1_000_000")?

    time_from_nanos = Utc.from_nanos_since_epoch(nanos_since_epoch)
    expect_true(Utc.to_iso_8601(time_from_nanos) == Utc.to_iso_8601(now), "nanosecond round-trip should preserve ISO seconds")?

    expect_true(Utc.to_iso_8601(Utc.from_millis_since_epoch(1_700_005_179_053)) == "2023-11-14T23:39:39Z", "known timestamp should format as ISO 8601")?

    Ok({})
}

test_time_delta! : () => Try({}, _)
test_time_delta! = || {
    start = Utc.now!()
    Sleep.millis!(50)
    finish = Utc.now!()

    delta_millis = Utc.delta_as_millis(start, finish)
    delta_nanos = Utc.delta_as_nanos(start, finish)

    expect_true(finish > start, "finish should be after start")?
    expect_true(delta_millis > 0, "delta_millis should be positive")?
    expect_true(delta_nanos > 0, "delta_nanos should be positive")?
    expect_true(delta_nanos >= delta_millis * 1_000_000, "delta_nanos should be consistent with delta_millis")
}

expect_true = |condition, message|
    if condition {
        Ok({})
    } else {
        Err(FailedExpectation(message))
    }

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_, _|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
