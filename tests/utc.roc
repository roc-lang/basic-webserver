app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Sleep
import pf.Stderr
import pf.Stdout
import pf.Utc
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
    test_time_conversion!()?
    test_time_delta!()
}

test_time_conversion! : () => Try({}, _)
test_time_conversion! = || {
    now = Utc.now!()

    millis_since_epoch = Utc.to_millis_since_epoch(now)
    Stdout.line!("Current time in milliseconds since epoch: ${U128.to_str(millis_since_epoch)}")?

    time_from_millis = Utc.from_millis_since_epoch(millis_since_epoch)
    Stdout.line!("Time reconstructed from milliseconds: ${Utc.to_iso_8601(time_from_millis)}")?
    expect_true(Utc.to_iso_8601(time_from_millis) == Utc.to_iso_8601(now), "millisecond round-trip should preserve ISO seconds")?

    nanos_since_epoch = Utc.to_nanos_since_epoch(now)
    Stdout.line!("Current time in nanoseconds since epoch: ${U128.to_str(nanos_since_epoch)}")?
    expect_true(nanos_since_epoch >= millis_since_epoch * 1_000_000, "nanoseconds should be at least milliseconds * 1_000_000")?

    time_from_nanos = Utc.from_nanos_since_epoch(nanos_since_epoch)
    Stdout.line!("Time reconstructed from nanoseconds: ${Utc.to_iso_8601(time_from_nanos)}")?
    expect_true(Utc.to_iso_8601(time_from_nanos) == Utc.to_iso_8601(now), "nanosecond round-trip should preserve ISO seconds")?

    expect_true(Utc.to_iso_8601(Utc.from_millis_since_epoch(1_700_005_179_053)) == "2023-11-14T23:39:39Z", "known timestamp should format as ISO 8601")?

    Ok({})
}

test_time_delta! : () => Try({}, _)
test_time_delta! = || {
    Stdout.line!("\nTime delta demonstration:")?

    start = Utc.now!()
    Stdout.line!("Starting time: ${Utc.to_iso_8601(start)}")?

    Sleep.millis!(50)

    finish = Utc.now!()
    Stdout.line!("Ending time: ${Utc.to_iso_8601(finish)}")?

    delta_millis = Utc.delta_as_millis(start, finish)
    Stdout.line!("Time elapsed: ${U128.to_str(delta_millis)} milliseconds")?

    delta_nanos = Utc.delta_as_nanos(start, finish)
    Stdout.line!("Time elapsed: ${U128.to_str(delta_nanos)} nanoseconds")?
    converted_millis = delta_nanos // 1_000_000
    converted_millis_remainder = delta_nanos % 1_000_000
    Stdout.line!("Nanoseconds converted to milliseconds: ${U128.to_str(converted_millis)}.${U128.to_str(converted_millis_remainder)}")?

    expect_true(finish > start, "finish should be after start")?
    expect_true(delta_millis > 0, "delta_millis should be positive")?
    expect_true(delta_nanos > 0, "delta_nanos should be positive")?
    expect_true(delta_nanos >= delta_millis * 1_000_000, "delta_nanos should be consistent with delta_millis")?
    expect_true(converted_millis == delta_millis, "delta_nanos converted to milliseconds should match delta_millis")?

    Stdout.line!("Verified: deltaMillis and deltaNanos/1_000_000 match within tolerance")
}

expect_true = |condition, message|
    if condition {
        Ok({})
    } else {
        Err(FailedExpectation(message))
    }


respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, _state|
    Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("I am a test."))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
