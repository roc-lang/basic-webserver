app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Server
import pf.OsStr
import pf.Stderr
import pf.Stdout
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            Stdout.line!("Done.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    Cmd.exec!("true", [])?
    Cmd.exec_str!("true", [])?
    Cmd.new("true").exec_cmd!()?

    output = Cmd.new("printf").arg("hello").exec_output!()?
    expect_true(output.stdout_utf8 == "hello", "printf stdout should be captured as UTF-8")?

    bytes = Cmd.new("printf").arg("bytes").exec_output_bytes!()?
    expect_true(bytes.stdout_bytes == Str.to_utf8("bytes"), "printf stdout should be captured as bytes")?

    test_native_strings!()?

    _ = Cmd.new("cat").arg("non_existent.txt").exec_exit_code!()?
    _ = Cmd.new("cat").arg("non_existent.txt").exec_exit_code!()?

    exit_code = Cmd.new("cat").arg("non_existent.txt").exec_exit_code!()?
    expect_true(exit_code == 1, "exec_exit_code! should return the non-zero exit code without failing")?

    Stdout.line!("All tests passed.")?

    Ok({})
}

test_native_strings! : () => Try({}, _)
test_native_strings! = ||
    match (Env.platform!()).os {
        WINDOWS => {
            foreign_result = Cmd.new(OsStr.unix_bytes([255])).exec_exit_code!()
            expect_true(Try.is_err(foreign_result), "Windows must reject UnixBytes command values")
        }
        _ => {
            arg_output = Cmd.new("printf")
                .arg(OsStr.unix_bytes([255]))
                .exec_output_bytes!()?
            expect_true(arg_output.stdout_bytes == [255], "command arguments must preserve non-UTF-8 Unix bytes")?

            env_output = Cmd.new("/usr/bin/env")
                .clear_envs()
                .env(OsStr.unix_bytes([75, 255]), OsStr.unix_bytes([86, 254]))
                .exec_output_bytes!()?
            expect_true(env_output.stdout_bytes == [75, 255, 61, 86, 254, 10], "command environment must preserve non-UTF-8 Unix bytes")?

            foreign_result = Cmd.new(OsStr.windows_u16s([0xD800])).exec_exit_code!()
            expect_true(Try.is_err(foreign_result), "Unix must reject WindowsU16s command values")
        }
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
