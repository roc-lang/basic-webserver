import IOErr
import Host
import OsStr
import Path exposing [Path]

## Build and run finite child processes with native-safe programs, arguments,
## and environment values. Programs execute directly without a shell. Commands
## inherit the platform's fixed launch directory unless `with_working_dir` is
## used and, unless clear_envs is used, the host environment. Relative working
## directories and relative program paths are resolved against the fixed launch
## directory, never against another command's configured directory. This
## includes a bare program name, so use an absolute program to combine PATH
## lookup with an explicit working directory.
## exec!/exec_cmd! inherit standard streams; exec_output! captures both streams
## with finite limits.
##
## ```roc
## output = Cmd.new_str("git")
##     .args_str(["status", "--short"])
##     .with_timeout_millis(5_000)
##     .with_output_limits({ stdout_bytes: 256 * 1024, stderr_bytes: 64 * 1024 })
##     .exec_output!()?
## ```
Cmd := [
	Cmd(
		{
			args : List(OsStr),
			clear_envs : Bool,
			envs : List({ name : OsStr, value : OsStr }),
			program : OsStr,
			working_dir : [Inherit, Set(Path)],
			timeout_ms : U64,
			stdout_limit_bytes : U64,
			stderr_limit_bytes : U64,
		},
	),
].{

	## Default deadline for command execution, including admission wait.
	default_timeout_ms : U64
	default_timeout_ms = 30_000

	## Default finite limit applied independently to captured stdout and stderr.
	default_output_limit_bytes : U64
	default_output_limit_bytes = 1024 * 1024

	## Execute a program with native arguments, inheriting standard streams.
	exec! : OsStr, List(OsStr) => Try({}, [ExecFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), CommandTimedOut({ command : Str, timeout_ms : U64 }), CommandSaturated({ command : Str }), ..])
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
	exec_str! : Str, List(Str) => Try({}, [ExecFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), CommandTimedOut({ command : Str, timeout_ms : U64 }), CommandSaturated({ command : Str }), ..])
	exec_str! = |program, arguments|
		exec!(OsStr.from_str(program), arguments.map(OsStr.from_str))

	## Execute a configured command, inheriting standard streams.
	exec_cmd! : Cmd => Try({}, [ExecCmdFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), CommandTimedOut({ command : Str, timeout_ms : U64 }), CommandSaturated({ command : Str }), ..])
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
	exec_output! : Cmd => Try({ stdout_utf8 : Str, stderr_utf8_lossy : Str }, [StdoutContainsInvalidUtf8({ cmd_str : Str, err : [BadUtf8({ problem : _, index : U64 })] }), NonZeroExitCode({ command : Str, exit_code : I32, stdout_utf8_lossy : Str, stderr_utf8_lossy : Str }), FailedToGetExitCode({ command : Str, err : IOErr }), CommandTimedOut({ command : Str, timeout_ms : U64 }), CommandSaturated({ command : Str }), StdoutLimitExceeded({ command : Str, limit_bytes : U64, received_at_least : U64 }), StderrLimitExceeded({ command : Str, limit_bytes : U64, received_at_least : U64 }), ..])
	exec_output! = |Cmd(cmd)| {
		command = Cmd(cmd)
		cmd_str = to_str(command)

		match Host.cmd_exec_output!(to_host_cmd(command), to_host_working_dir(command)) {
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
			Err(Timeout) => Err(CommandTimedOut({ command: cmd_str, timeout_ms: cmd.timeout_ms }))
			Err(Saturated) => Err(CommandSaturated({ command: cmd_str }))
			Err(StdoutTooLarge({ limit_bytes, received_at_least })) => Err(StdoutLimitExceeded({ command: cmd_str, limit_bytes, received_at_least }))
			Err(StderrTooLarge({ limit_bytes, received_at_least })) => Err(StderrLimitExceeded({ command: cmd_str, limit_bytes, received_at_least }))
		}
	}

	## Execute a command and capture stdout and stderr without text conversion.
	exec_output_bytes! : Cmd => Try({ stderr_bytes : List(U8), stdout_bytes : List(U8) }, [NonZeroExitCodeB({ exit_code : I32, stdout_bytes : List(U8), stderr_bytes : List(U8) }), FailedToGetExitCodeB(IOErr), CommandTimedOutB(U64), CommandSaturatedB, StdoutLimitExceededB({ limit_bytes : U64, received_at_least : U64 }), StderrLimitExceededB({ limit_bytes : U64, received_at_least : U64 }), ..])
	exec_output_bytes! = |Cmd(cmd)|
		match Host.cmd_exec_output!(to_host_cmd(Cmd(cmd)), to_host_working_dir(Cmd(cmd))) {
			Ok({ stderr_bytes, stdout_bytes }) => Ok({ stdout_bytes, stderr_bytes })
			Err(NonZeroExitCode({ exit_code, stderr_bytes, stdout_bytes })) =>
				Err(NonZeroExitCodeB({ exit_code, stdout_bytes, stderr_bytes }))
			Err(FailedToGetExitCode(err)) => Err(FailedToGetExitCodeB(err))
			Err(Timeout) => Err(CommandTimedOutB(cmd.timeout_ms))
			Err(Saturated) => Err(CommandSaturatedB)
			Err(StdoutTooLarge(payload)) => Err(StdoutLimitExceededB(payload))
			Err(StderrTooLarge(payload)) => Err(StderrLimitExceededB(payload))
		}

	## Execute a command and return its exit code.
	exec_exit_code! : Cmd => Try(I32, [FailedToGetExitCode({ command : Str, err : IOErr }), CommandTimedOut({ command : Str, timeout_ms : U64 }), CommandSaturated({ command : Str }), ..])
	exec_exit_code! = |Cmd(cmd)| {
		command = to_str(Cmd(cmd))

		match Host.cmd_exec_exit_code!(to_host_cmd(Cmd(cmd)), to_host_working_dir(Cmd(cmd))) {
			Ok(num) => Ok(num)
			Err(FailedToGetExitCode(io_err)) => Err(FailedToGetExitCode({ command, err: io_err }))
			Err(Timeout) => Err(CommandTimedOut({ command, timeout_ms: cmd.timeout_ms }))
			Err(Saturated) => Err(CommandSaturated({ command: command }))
		}
	}

	## Create a command whose program is an exact native OS string.
	new : OsStr -> Cmd
	new = |program| Cmd({
		args: [],
		clear_envs: Bool.False,
		envs: [],
		program,
		working_dir: Inherit,
		timeout_ms: default_timeout_ms,
		stdout_limit_bytes: default_output_limit_bytes,
		stderr_limit_bytes: default_output_limit_bytes,
	})

	## Set this child's working directory without changing process-global state.
	## A relative path is resolved against the platform's fixed launch directory.
	## When this option is set, a relative program path is independently resolved
	## against that same launch directory before the child directory is applied;
	## this includes a bare program name that would otherwise use PATH lookup.
	## Missing, inaccessible, or invalid directories are reported through the
	## corresponding `FailedToGetExitCode` or `FailedToGetExitCodeB` error.
	with_working_dir : Cmd, Path -> Cmd
	with_working_dir = |Cmd(cmd), path| Cmd({ ..cmd, working_dir: Set(path) })

	## Set the total deadline, including bounded admission wait. Zero is
	## normalized to one millisecond.
	with_timeout_millis : Cmd, U64 -> Cmd
	with_timeout_millis = |Cmd(cmd), timeout_ms|
		Cmd({
			..cmd,
			timeout_ms: if timeout_ms == 0 {
				1
			} else {
				timeout_ms
			},
		})

	## Set the maximum captured stdout size in bytes.
	with_stdout_limit : Cmd, U64 -> Cmd
	with_stdout_limit = |Cmd(cmd), limit_bytes| Cmd({ ..cmd, stdout_limit_bytes: limit_bytes })

	## Set the maximum captured stderr size in bytes.
	with_stderr_limit : Cmd, U64 -> Cmd
	with_stderr_limit = |Cmd(cmd), limit_bytes| Cmd({ ..cmd, stderr_limit_bytes: limit_bytes })

	## Set independent finite limits for captured stdout and stderr.
	with_output_limits : Cmd, { stdout_bytes : U64, stderr_bytes : U64 } -> Cmd
	with_output_limits = |Cmd(cmd), limits| Cmd({
		..cmd,
		stdout_limit_bytes: limits.stdout_bytes,
		stderr_limit_bytes: limits.stderr_bytes,
	})

	## Create a command whose program is UTF-8 text.
	new_str : Str -> Cmd
	new_str = |program| new(OsStr.from_str(program))

	## Add an exact native argument. Shell expansion is not performed.
	arg : Cmd, OsStr -> Cmd
	arg = |Cmd(cmd), argument| Cmd({ ..cmd, args: cmd.args.append(argument) })

	## Add a UTF-8 argument. Shell expansion is not performed.
	arg_str : Cmd, Str -> Cmd
	arg_str = |cmd, argument| arg(cmd, OsStr.from_str(argument))

	## Add exact native arguments. Shell expansion is not performed.
	args : Cmd, List(OsStr) -> Cmd
	args = |Cmd(cmd), arguments| Cmd({ ..cmd, args: cmd.args.concat(arguments) })

	## Add UTF-8 arguments. Shell expansion is not performed.
	args_str : Cmd, List(Str) -> Cmd
	args_str = |cmd, arguments| args(cmd, arguments.map(OsStr.from_str))

	## Add an exact native environment name and value.
	env : Cmd, OsStr, OsStr -> Cmd
	env = |Cmd(cmd), name, value| Cmd({ ..cmd, envs: cmd.envs.append({ name, value }) })

	## Add a UTF-8 environment name and value.
	env_str : Cmd, Str, Str -> Cmd
	env_str = |cmd, key, value| env(cmd, OsStr.from_str(key), OsStr.from_str(value))

	## Add exact native environment variables. Named fields keep same-typed names
	## and values unambiguous at call sites.
	envs : Cmd, List({ name : OsStr, value : OsStr }) -> Cmd
	envs = |Cmd(cmd), variables| Cmd({ ..cmd, envs: cmd.envs.concat(variables) })

	## Add UTF-8 environment variables using `{ name, value }` records.
	envs_str : Cmd, List({ name : Str, value : Str }) -> Cmd
	envs_str = |cmd, variables|
		envs(
			cmd,
			variables.map(
				|variable| {
					name: OsStr.from_str(variable.name),
					value: OsStr.from_str(variable.value),
				},
			),
		)

	## Remove the inherited environment before applying configured pairs.
	clear_envs : Cmd -> Cmd
	clear_envs = |Cmd(cmd)| Cmd({ ..cmd, clear_envs: Bool.True })

	## Render an escaped, diagnostic representation of this command.
	## Native values are never round-tripped through this lossy string.
	to_str : Cmd -> Str
	to_str = |Cmd(cmd)|
		"Cmd({ program: ${Str.inspect(cmd.program)}, args: ${Str.inspect(cmd.args)}, envs: ${Str.inspect(cmd.envs)}, clear_envs: ${Str.inspect(cmd.clear_envs)}, working_dir: ${Str.inspect(cmd.working_dir)} })"

	## Use [`to_str`](#Cmd.to_str) when this command is inspected.
	to_inspect : Cmd -> Str
	to_inspect = |cmd| to_str(cmd)
}

to_host_cmd : Cmd -> Host.Cmd
to_host_cmd = |Cmd(cmd)| {
	args: cmd.args.map(OsStr.to_raw),
	clear_envs: cmd.clear_envs,
	envs: cmd.envs.map(
		|variable| {
			name: OsStr.to_raw(variable.name),
			value: OsStr.to_raw(variable.value),
		},
	),
	program: OsStr.to_raw(cmd.program),
	timeout_ms: cmd.timeout_ms,
	stdout_limit_bytes: cmd.stdout_limit_bytes,
	stderr_limit_bytes: cmd.stderr_limit_bytes,
}

to_host_working_dir : Cmd -> [Inherit, Set(OsStr.Raw)]
to_host_working_dir = |Cmd(cmd)|
	match cmd.working_dir {
		Inherit => Inherit
		Set(path) => Set(Path.to_raw(path))
	}

## Command inspection preserves escaped arguments and environment variables.
expect {
	cmd = Cmd.new_str("echo\nnext")
		.arg_str("hello world")
		.env_str("NAME", "Roc")
		.clear_envs()
		.with_working_dir(Path.unix_bytes([119, 255]))

	Str.inspect(cmd) == "Cmd({ program: OsStr.utf8(\"echo\\nnext\"), args: [OsStr.utf8(\"hello world\")], envs: [{ name: OsStr.utf8(\"NAME\"), value: OsStr.utf8(\"Roc\") }], clear_envs: True, working_dir: Set(Path.unix_bytes([119, 255])) })"
}

## Host conversion preserves non-UTF-8 command arguments, environment variables, and paths.
expect {
	cmd = Cmd.new(OsStr.unix_bytes([112, 255]))
		.arg(OsStr.windows_u16s([97, 0xD800]))
		.env(OsStr.unix_bytes([75, 255]), OsStr.windows_u16s([86, 0xD800]))
		.with_working_dir(Path.windows_u16s([67, 58, 92, 0xD800]))
	host_cmd = to_host_cmd(cmd)
	host_working_dir = to_host_working_dir(cmd)

	actual = 
		\\program: ${Str.inspect(host_cmd.program)}
		\\args: ${Str.inspect(host_cmd.args)}
		\\envs: ${Str.inspect(host_cmd.envs)}
		\\working_dir: ${Str.inspect(host_working_dir)}

	expected = 
		\\program: UnixBytes([112, 255])
		\\args: [WindowsU16s([97, 55296])]
		\\envs: [{ name: UnixBytes([75, 255]), value: WindowsU16s([86, 55296]) }]
		\\working_dir: Set(WindowsU16s([67, 58, 92, 55296]))

	actual == expected
}
