app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Http
import pf.Cmd
import pf.Utc
import pf.Stdout
import pf.Stderr
import http.Response

# To run this example: check the root README.md

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || {
    result! = || {
        # Simplest way to execute a command (prints to your terminal).
        Cmd.exec!("echo", ["Hello"])?

        # To execute and capture the output (stdout and stderr) without inheriting your terminal.
        cmd_output =
            Cmd.new("echo")
            .args(["Hi"])
            .exec_output!()?

        Stdout.line!("{stderr_utf8_lossy: \"${cmd_output.stderr_utf8_lossy}\", stdout_utf8: \"${cmd_output.stdout_utf8}\"}")?

        # To run a command with environment variables.
        Cmd.new("env")
        .clear_envs() # You probably don't need to clear all other environment variables, this is just an example.
        .env("FOO", "BAR")
        .envs([{ name: "BAZ", value: "DUCK" }, { name: "XYZ", value: "ABC" }]) # Set multiple environment variables at once with `envs`
        .args(["-v"])
        .exec_cmd!()?

        # To execute and just get the exit code (prints to your terminal).
        # Prefer using `exec!` or `exec_cmd!`.
        exit_code =
            Cmd.new("cat")
            .args(["non_existent.txt"])
            .exec_exit_code!()?

        Stdout.line!("Exit code: ${exit_code.to_str()}")?

        # To execute and capture the output (stdout and stderr) in the original form as bytes without inheriting your terminal.
        # Prefer using `exec_output!`.
        cmd_output_bytes =
            Cmd.new("echo")
            .args(["Hi"])
            .exec_output_bytes!()?

        Stdout.line!("{stderr_bytes: ${Str.inspect(cmd_output_bytes.stderr_bytes)}, stdout_bytes: ${Str.inspect(cmd_output_bytes.stdout_bytes)}}")?

        Ok({})
    }

    match result!() {
        Ok(_) => Ok({})
        Err(err) => {
            Stderr.line!("Error running commands: ${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |req, _model| {
    time = Utc.to_iso_8601(Utc.now!())

    # Log request time, method and url using echo
    match Cmd.exec!("echo", ["${time} ${Str.inspect(req.method())} ${req.uri()}"]) {
        Ok(_) => Ok(Response.from_status(200).with_body(Str.to_utf8("Command succeeded.")))
        Err(err) => Err(ServerErr("Command failed: ${Str.inspect(err)}"))
    }
}
