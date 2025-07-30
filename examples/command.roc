app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Http exposing [Request, Response]
import pf.Cmd
import pf.Utc
import pf.Stdout
import pf.Stderr

# To run this example: check the README.md in this folder

Model : {}

init! : {} => Result Model _
init! = |{}|

    # Simplest way to execute a command (prints to your terminal).
    # See `Cmd.exec!` in `respond!` below.

    # To execute and capture the output (stdout, stderr, and exit code) without inheriting your terminal.
    output_example!({}) ? |err| OutputExampleFailed(err)

    # To run a command with an environment variable.
    env_example!({}) ? |err| EnvExampleFailed(err)

    # To execute and just get the exit code (prints to your terminal).
    status_example!({}) ? |err| StatusExampleFailed(err)

    Ok({})

respond! : Request, Model => Result Response [EchoCmdFailed(_)]
respond! = |req, _|
    datetime = Utc.to_iso_8601(Utc.now!({}))

    # Log request date, method and url using echo
    Cmd.exec!("echo", ["${datetime} ${Inspect.to_str(req.method)} ${req.uri}"]) ? |err| EchoCmdFailed(err)

    Ok(
        {
            status: 200,
            headers: [],
            body: Str.to_utf8("Command succeeded."),
        },
    )

# Execute command and capture the output (stdout, stderr, and exit code)
output_example! : {} => Result {} _
output_example! = |{}|

    cmd_output =
        Cmd.new("echo")
        |> Cmd.args(["Hi"])
        |> Cmd.output!

    print_output!(cmd_output)


print_output! : Cmd.Output => Result {} _
print_output! = |cmd_output|


    when cmd_output.status is
        Ok(0) ->
            stdout_utf8 = Str.from_utf8(cmd_output.stdout)?
            Stdout.line!("Command output: ${stdout_utf8}")

        Ok(exit_code) ->
            stdout_utf8 = Str.from_utf8_lossy(cmd_output.stdout)
            stderr_utf8 = Str.from_utf8_lossy(cmd_output.stderr)
            err_data =
                """
                Command failed:
                - exit code: ${Num.to_str(exit_code)}
                - stdout: ${stdout_utf8}
                - stderr: ${stderr_utf8}
                """

            Stderr.line!(err_data)

        Err(err) ->
            Stderr.line!("Failed to get exit code for command, error: ${Inspect.to_str(err)}")


# Run command with an environment variable
env_example! : {} => Result {} _
env_example! = |{}|

    cmd_output =
        Cmd.new("env")
        |> Cmd.clear_envs # You probably don't need to clear all other environment variables, this is just an example.
        |> Cmd.env("FOO", "BAR")
        |> Cmd.envs([("BAZ", "DUCK"), ("XYZ", "ABC")]) # Set multiple environment variables at once with `envs`
        |> Cmd.args(["-v"])
        |> Cmd.output!

    print_output!(cmd_output)

# Execute command and capture the exit code
status_example! : {} => Result {} _
status_example! = |{}|
    cmd_result =
        Cmd.new("echo")
        |> Cmd.args(["Yo"])
        |> Cmd.status!

    when cmd_result is
        Ok(0) -> Ok({})

        Ok(exit_code) ->
            Stderr.line!("Command failed with exit code: ${Num.to_str(exit_code)}")

        Err(err) ->
            Stderr.line!("Failed to get exit code for command, error: ${Inspect.to_str(err)}")
