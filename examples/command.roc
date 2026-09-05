## Demonstrates command execution, captured output, environment variables, timeouts, and output limits.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	gregorian: "https://cdn.jasperwoudenberg.com/roc-gregorian-v1.0.0-rc.3/3R8EMBQy6rYy3vbLY3u4CLcT8qwAPAyxaaGTA18Gknbe.tar.zst",
	roc: "nightly-2026-09-04-c125b82",
}

import pf.Server
import pf.Cmd
import pf.Env
import pf.Path
import pf.UnixTime
import pf.Stdout
import http.Response
import gregorian.Time

Context : { helper : Str, python : Str, examples_dir : Path.Path, scripts_dir : Path.Path }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, _)
init! = || {
	python = Env.var_str!("PYTHON")?
	helper = Env.var_str!("COMMAND_HELPER")?
	examples_dir = Path.utf8(Env.var_str!("COMMAND_EXAMPLES_DIR")?)
	scripts_dir = Path.utf8(Env.var_str!("COMMAND_SCRIPTS_DIR")?)

	# Simplest way to execute a command (prints to your terminal).
	Cmd.exec_str!(python, [helper, "echo", "Hello"])?

	# To execute and capture the output (stdout and stderr) without inheriting your terminal.
	cmd_output =
		Cmd.new_str(python)
			.args_str([helper, "echo", "Hi"])
			.exec_output!()?

	Stdout.line!("{stderr_utf8_lossy: \"${cmd_output.stderr_utf8_lossy}\", stdout_utf8: \"${cmd_output.stdout_utf8}\"}")?

	# To run a command with environment variables.
	Cmd.new_str(python)
		.clear_envs() # Start the child with an empty environment.
		.env("FOO", "BAR")
		.envs_str([{ name: "BAZ", value: "DUCK" }, { name: "XYZ", value: "ABC" }]) # Set multiple UTF-8 environment variables at once.
		.args_str([helper, "env"])
		.exec_cmd!()?

	# `exec_exit_code!` returns nonzero exit codes as values. Most callers should
	# use `exec!` or `exec_cmd!`, which turn nonzero codes into typed errors.
	exit_code =
		Cmd.new_str(python)
			.args_str([helper, "fail"])
			.exec_exit_code!()?

	Stdout.line!("Exit code: ${exit_code.to_str()}")?

	# Capture exact stdout and stderr bytes when output may not be valid UTF-8.
	# Prefer `exec_output!` when textual output is expected.
	cmd_output_bytes =
		Cmd.new_str(python)
			.args_str([helper, "echo", "Hi"])
			.exec_output_bytes!()?

	Stdout.line!("{stderr_bytes: ${Str.inspect(cmd_output_bytes.stderr_bytes)}, stdout_bytes: ${Str.inspect(cmd_output_bytes.stdout_bytes)}}")?

	Ok({ config: Server.default_config, context: { python, helper, examples_dir, scripts_dir } })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, { python, helper, examples_dir, scripts_dir }|
	match req.target() {
		Resource({ raw_path: "/cwd-examples", .. }) =>
			command_cwd_response!(python, helper, examples_dir)
		Resource({ raw_path: "/cwd-scripts", .. }) =>
			command_cwd_response!(python, helper, scripts_dir)
		Resource({ raw_path: "/timeout", .. }) => {
			cmd = Cmd.new_str(python)
				.args_str([helper, "sleep", "5"])
				.with_timeout_millis(20)

			match cmd.exec_cmd!() {
				Err(CommandTimedOut(_)) => Ok(text_response("Command timed out."))
				other => Err(ServerErr("Expected CommandTimedOut, got ${Str.inspect(other)}"))
			}
		}
		Resource({ raw_path: "/output-limit", .. }) => {
			cmd = Cmd.new_str(python)
				.args_str([helper, "bytes", "64"])
				.with_stdout_limit(8)

			match cmd.exec_output!() {
				Err(StdoutLimitExceeded(_)) => Ok(text_response("Command output was limited."))
				other => Err(ServerErr("Expected StdoutLimitExceeded, got ${Str.inspect(other)}"))
			}
		}
		_ => {
			time = (Time.unix_epoch + UnixTime.now!().seconds_since_epoch()).iso8601()

			# Log request time, method and URL through the helper process.
			match Cmd.exec_str!(python, [helper, "echo", "${time} ${Str.inspect(req.method())} ${Str.inspect(req.target())}"]) {
				Ok(_) => Ok(text_response("Command succeeded."))
				Err(err) => Err(ServerErr("Command failed: ${Str.inspect(err)}"))
			}
		}
	}

command_cwd_response! : Str, Str, Path.Path => Try(Server.Outcome, [ServerErr(Str), ..])
command_cwd_response! = |python, helper, working_dir| {
	output = Cmd.new_str(python)
		.args_str([helper, "cwd", "0.2"])
		.with_working_dir(working_dir)
		.exec_output!()

	match output {
		Ok({ stdout_utf8, .. }) => Ok(text_response(stdout_utf8))
		Err(err) => Err(ServerErr("Working-directory command failed: ${Str.inspect(err)}"))
	}
}

text_response : Str -> Server.Outcome
text_response = |body| Server.respond(Response.from_status(200).with_body(Str.to_utf8(body)))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
