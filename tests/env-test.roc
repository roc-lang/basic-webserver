app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.Http
import pf.Env
import http.Response

# NOTE: The migrated Env module is a reduced subset. This test covers var!,
# cwd!, exe_path!, and temp_dir!.

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
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
    Stdout.line!("Testing Env module functions...\n\nTesting Env.cwd!:")?
    cwd = Env.cwd!()?
    Stdout.line!("cwd: ${cwd}\n\nTesting Env.exe_path!:")?

    exe_path = Env.exe_path!()?
    Stdout.line!("exe_path: ${exe_path}\n\nTesting Env.temp_dir!:")?

    temp_dir = Env.temp_dir!()
    Stdout.line!("temp_dir: ${temp_dir}\n\nTesting Env.var!:")?

    # A variable that should exist in most environments
    match Env.var!("PATH") {
        Ok(_) => {
            Stdout.line!("PATH variable is set (expected)")?
            {}
        }
        Err(VarNotFound(name)) => {
            Stdout.line!("PATH variable not found: ${name}")?
            {}
        }
    }

    # A variable that should not exist
    match Env.var!("DEFINITELY_NOT_A_REAL_ENV_VAR_123456") {
        Ok(value) => {
            Stdout.line!("Unexpected value: ${value}")?
            {}
        }
        Err(VarNotFound(name)) => {
            Stdout.line!("var not found (expected): ${name}")?
            {}
        }
    }

    Stdout.line!("\nAll tests executed.")
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
