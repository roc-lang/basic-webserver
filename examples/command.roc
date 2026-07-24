app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Cmd
import pf.Env
import pf.Utc
import pf.Stdout
import pf.Stderr
import http.Response

# To run this example: check the root README.md

Context : { helper : Str, python : Str }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	result! = || {
		python = Env.var_str!("PYTHON")?
		helper = Env.var_str!("COMMAND_HELPER")?

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
			.clear_envs() # You probably don't need to clear all other environment variables, this is just an example.
			.env("FOO", "BAR")
			.envs_str([{ name: "BAZ", value: "DUCK" }, { name: "XYZ", value: "ABC" }]) # Set multiple UTF-8 environment variables at once.
			.args_str([helper, "env"])
			.exec_cmd!()?

		# To execute and just get the exit code (prints to your terminal).
		# Prefer using `exec!` or `exec_cmd!`.
		exit_code = 
			Cmd.new_str(python)
				.args_str([helper, "fail"])
				.exec_exit_code!()?

		Stdout.line!("Exit code: ${exit_code.to_str()}")?

		# To execute and capture the output (stdout and stderr) in the original form as bytes without inheriting your terminal.
		# Prefer using `exec_output!`.
		cmd_output_bytes = 
			Cmd.new_str(python)
				.args_str([helper, "echo", "Hi"])
				.exec_output_bytes!()?

		Stdout.line!("{stderr_bytes: ${Str.inspect(cmd_output_bytes.stderr_bytes)}, stdout_bytes: ${Str.inspect(cmd_output_bytes.stdout_bytes)}}")?

		Ok({})
	}

	match result!() {
		Ok(_) => {
			python = Env.var_str!("PYTHON") ? |_| Exit(1)
			helper = Env.var_str!("COMMAND_HELPER") ? |_| Exit(1)
			Ok({ config: Server.default_config, context: { python, helper } })
		}
		Err(err) => {
			Stderr.line!("Error running commands: ${Str.inspect(err)}") ?? {}
			Err(Exit(1))
		}
	}
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |req, { python, helper }| {
	time = Utc.to_iso_8601(Utc.now!())

	# Log request time, method and URL through the helper process.
	match Cmd.exec_str!(python, [helper, "echo", "${time} ${Str.inspect(req.method())} ${req.target()}"]) {
		Ok(_) => Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("Command succeeded."))))
		Err(err) => Err(ServerErr("Command failed: ${Str.inspect(err)}"))
	}
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
