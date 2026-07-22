import IOErr exposing [IOErr]
import Host
import OsStr exposing [OsStr]

## Build and run child processes with native-safe programs, arguments, and
## environment values.
Cmd :: {
	args : List(OsStr),
	clear_envs : Bool,
	envs : List({ name : OsStr, value : OsStr }),
	program : OsStr,
}.{
	## Execute a program with native arguments, inheriting standard streams.
	exec! : OsStr, List(OsStr) => Try({}, [ExecFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), ..])
	exec! = |program, arguments| {
		command = "${OsStr.display(program)} ${Str.join_with(arguments.map(OsStr.display), " ")}"
		exit_code = new(program).args(arguments).exec_exit_code!()?

		if exit_code == 0 {
			Ok({})
		} else {
			Err(ExecFailed({ command, exit_code }))
		}
	}

	## Execute a UTF-8 program with UTF-8 arguments.
	exec_str! : Str, List(Str) => Try({}, [ExecFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), ..])
	exec_str! = |program, arguments|
		exec!(OsStr.from_str(program), arguments.map(OsStr.from_str))

	## Execute a configured command, inheriting standard streams.
	exec_cmd! : Cmd => Try({}, [ExecCmdFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), ..])
	exec_cmd! = |cmd| {
		command = to_str(cmd)
		exit_code = exec_exit_code!(cmd)?

		if exit_code == 0 {
			Ok({})
		} else {
			Err(ExecCmdFailed({ command, exit_code }))
		}
	}

	## Execute a command and capture stdout as UTF-8 and stderr lossily.
	## Use [exec_output_bytes!] when either stream must be preserved exactly.
	exec_output! : Cmd => Try({ stdout_utf8 : Str, stderr_utf8_lossy : Str }, [StdoutContainsInvalidUtf8({ cmd_str : Str, err : [BadUtf8({ problem : _, index : U64 })] }), NonZeroExitCode({ command : Str, exit_code : I32, stdout_utf8_lossy : Str, stderr_utf8_lossy : Str }), FailedToGetExitCode({ command : Str, err : IOErr }), ..])
	exec_output! = |cmd| {
		cmd_str = to_str(cmd)

		match Host.cmd_exec_output!(to_host_cmd(cmd)) {
			Ok({ stderr_bytes, stdout_bytes }) => {
				stdout_utf8 = Str.from_utf8(stdout_bytes)
					.map_err(|err| StdoutContainsInvalidUtf8({ cmd_str, err }))?

				Ok({ stdout_utf8, stderr_utf8_lossy: Str.from_utf8_lossy(stderr_bytes) })
			}
			Err(NonZeroExitCode({ exit_code, stderr_bytes, stdout_bytes })) =>
				Err(
					NonZeroExitCode({
						command: cmd_str,
						exit_code,
						stdout_utf8_lossy: Str.from_utf8_lossy(stdout_bytes),
						stderr_utf8_lossy: Str.from_utf8_lossy(stderr_bytes),
					}),
				)
			Err(FailedToGetExitCode(err)) => Err(FailedToGetExitCode({ command: cmd_str, err }))
		}
	}

	## Execute a command and capture stdout and stderr without text conversion.
	exec_output_bytes! : Cmd => Try({ stderr_bytes : List(U8), stdout_bytes : List(U8) }, [NonZeroExitCodeB({ exit_code : I32, stdout_bytes : List(U8), stderr_bytes : List(U8) }), FailedToGetExitCodeB(IOErr), ..])
	exec_output_bytes! = |cmd|
		match Host.cmd_exec_output!(to_host_cmd(cmd)) {
			Ok({ stderr_bytes, stdout_bytes }) => Ok({ stdout_bytes, stderr_bytes })
			Err(NonZeroExitCode({ exit_code, stderr_bytes, stdout_bytes })) =>
				Err(NonZeroExitCodeB({ exit_code, stdout_bytes, stderr_bytes }))
			Err(FailedToGetExitCode(err)) => Err(FailedToGetExitCodeB(err))
		}

	## Execute a command and return its exit code.
	exec_exit_code! : Cmd => Try(I32, [FailedToGetExitCode({ command : Str, err : IOErr }), ..])
	exec_exit_code! = |cmd| {
		command = to_str(cmd)

		match Host.cmd_exec_exit_code!(to_host_cmd(cmd)) {
			Ok(num) => Ok(num)
			Err(io_err) => Err(FailedToGetExitCode({ command, err: io_err }))
		}
	}

	## Create a command whose program is an exact native OS string.
	new : OsStr -> Cmd
	new = |program| {
		args: [],
		clear_envs: Bool.False,
		envs: [],
		program,
	}

	## Create a command whose program is UTF-8 text.
	new_str : Str -> Cmd
	new_str = |program| new(OsStr.from_str(program))

	## Add an exact native argument. Shell expansion is not performed.
	arg : Cmd, OsStr -> Cmd
	arg = |cmd, argument| { ..cmd, args: cmd.args.append(argument) }

	## Add a UTF-8 argument. Shell expansion is not performed.
	arg_str : Cmd, Str -> Cmd
	arg_str = |cmd, argument| arg(cmd, OsStr.from_str(argument))

	## Add exact native arguments. Shell expansion is not performed.
	args : Cmd, List(OsStr) -> Cmd
	args = |cmd, arguments| { ..cmd, args: cmd.args.concat(arguments) }

	## Add UTF-8 arguments. Shell expansion is not performed.
	args_str : Cmd, List(Str) -> Cmd
	args_str = |cmd, arguments| args(cmd, arguments.map(OsStr.from_str))

	## Add an exact native environment name and value.
	env : Cmd, OsStr, OsStr -> Cmd
	env = |cmd, name, value| { ..cmd, envs: cmd.envs.append({ name, value }) }

	## Add a UTF-8 environment name and value.
	env_str : Cmd, Str, Str -> Cmd
	env_str = |cmd, key, value| env(cmd, OsStr.from_str(key), OsStr.from_str(value))

	## Add exact native environment variables. Named fields keep same-typed names
	## and values unambiguous at call sites.
	envs : Cmd, List({ name : OsStr, value : OsStr }) -> Cmd
	envs = |cmd, variables| { ..cmd, envs: cmd.envs.concat(variables) }

	## Add UTF-8 environment variables using `{ name, value }` records.
	envs_str : Cmd, List({ name : Str, value : Str }) -> Cmd
	envs_str = |cmd, variables|
		envs(cmd, variables.map(|variable| {
			name: OsStr.from_str(variable.name),
			value: OsStr.from_str(variable.value),
		}))

	## Remove the inherited environment before applying configured pairs.
	clear_envs : Cmd -> Cmd
	clear_envs = |cmd| { ..cmd, clear_envs: Bool.True }

	## Render an escaped, diagnostic representation of this command.
	## Native values are never round-tripped through this lossy string.
	to_str : Cmd -> Str
	to_str = |cmd|
		"Cmd({ program: ${Str.inspect(cmd.program)}, args: ${Str.inspect(cmd.args)}, envs: ${Str.inspect(cmd.envs)}, clear_envs: ${Str.inspect(cmd.clear_envs)} })"

	to_inspect : Cmd -> Str
	to_inspect = |cmd| to_str(cmd)
}

to_host_cmd : Cmd -> Host.Cmd
to_host_cmd = |cmd| {
	args: cmd.args.map(OsStr.to_raw),
	clear_envs: cmd.clear_envs,
	envs: cmd.envs.map(|variable| {
		name: OsStr.to_raw(variable.name),
		value: OsStr.to_raw(variable.value),
	}),
	program: OsStr.to_raw(cmd.program),
}

expect {
	cmd = Cmd.new_str("echo\nnext")
		.arg_str("hello world")
		.env_str("NAME", "Roc")
		.clear_envs()

	Str.inspect(cmd) == "Cmd({ program: OsStr.utf8(\"echo\\nnext\"), args: [OsStr.utf8(\"hello world\")], envs: [{ name: OsStr.utf8(\"NAME\"), value: OsStr.utf8(\"Roc\") }], clear_envs: True })"
}

expect {
	cmd = Cmd.new(OsStr.unix_bytes([112, 255]))
		.arg(OsStr.windows_u16s([97, 0xD800]))
		.env(OsStr.unix_bytes([75, 255]), OsStr.windows_u16s([86, 0xD800]))
	host_cmd = to_host_cmd(cmd)

	cmd.program == OsStr.unix_bytes([112, 255]) and
		cmd.args == [OsStr.windows_u16s([97, 0xD800])] and
		cmd.envs == [{ name: OsStr.unix_bytes([75, 255]), value: OsStr.windows_u16s([86, 0xD800]) }] and
			host_cmd.envs == [{ name: UnixBytes([75, 255]), value: WindowsU16s([86, 0xD800]) }]
}
