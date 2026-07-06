app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Cmd
import pf.Http
import pf.Stderr
import pf.Stdout
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            Stdout.line!("Ran all Cmd tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    Cmd.exec!("echo", ["hello"])?
    Cmd.new("echo").arg("hello").exec_cmd!()?

    output = Cmd.new("printf").arg("hello").exec_output!()?
    expect_true(output.stdout_utf8 == "hello", "printf stdout should be captured as UTF-8")?

    bytes = Cmd.new("printf").arg("bytes").exec_output_bytes!()?
    expect_true(bytes.stdout_bytes == Str.to_utf8("bytes"), "printf stdout should be captured as bytes")?

    exit_code = Cmd.new("roc").arg("definitely_missing_file.roc").exec_exit_code!()?
    expect_true(exit_code != 0, "exec_exit_code! should return a non-zero exit code without failing")?

    Ok({})
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
