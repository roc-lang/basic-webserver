import Host
import InternalPath
import IOErr
import OsStr
import Path

## Read process environment data without losing native operating-system strings.
Env := [].{

	## CPU architecture reported for the current platform build.
	ARCH : [X86, X64, ARM, AARCH64, OTHER(Str)]

	## Operating system reported for the current platform build.
	OS : [LINUX, MACOS, WINDOWS, OTHER(Str)]

	## Read an environment variable using an exact native name and value.
	var! : OsStr => Try(OsStr, [VarNotFound(OsStr), EnvErr(IOErr), ..])
	var! = |name|
		match Host.env_var!(OsStr.to_raw(name)) {
			Ok(raw) => Ok(OsStr.from_raw(raw))
			Err(VarNotFound(raw_name)) => Err(VarNotFound(OsStr.from_raw(raw_name)))
			Err(EnvErr(err)) => Err(EnvErr(err))
		}

	## Read an environment variable whose value must be valid Unicode text.
	## The name remains native-safe; quoted names work through OsStr.from_quote.
	var_str! : OsStr => Try(Str, [VarNotFound(OsStr), EnvErr(IOErr), InvalidStr(U64), ..])
	var_str! = |name|
		match var!(name) {
			Ok(value) =>
				match OsStr.to_str_try(value) {
					Ok(str) => Ok(str)
					Err(InvalidStr(index)) => Err(InvalidStr(index))
				}
			Err(VarNotFound(raw_name)) => Err(VarNotFound(raw_name))
			Err(EnvErr(err)) => Err(EnvErr(err))
		}

	## Read the byte-preserving directory inherited when the platform launched.
	## The platform never changes this process-global directory.
	cwd! : () => Try(Path, [CwdUnavailable, ..])
	cwd! = || {
		if Host.env_is_windows!("") {
			match Host.env_cwd_windows!("") {
				Ok(u16s) => Ok(Path.windows_u16s(u16s))
				Err(_) => Err(CwdUnavailable)
			}
		} else {
			match Host.env_cwd_unix!("") {
				Ok(bytes) => Ok(Path.unix_bytes(bytes))
				Err(_) => Err(CwdUnavailable)
			}
		}
	}

	## Return the path to the currently running executable.
	exe_path! : () => Try(Path, [ExePathUnavailable, ..])
	exe_path! = || {
		if Host.env_is_windows!("") {
			match Host.env_exe_path_windows!("") {
				Ok(u16s) => Ok(Path.windows_u16s(u16s))
				Err(_) => Err(ExePathUnavailable)
			}
		} else {
			match Host.env_exe_path_unix!("") {
				Ok(bytes) => Ok(Path.unix_bytes(bytes))
				Err(_) => Err(ExePathUnavailable)
			}
		}
	}

	## Return the platform's default temporary directory.
	temp_dir! : () => Path
	temp_dir! = || InternalPath.from_host_raw(Host.env_temp_dir!(""))

	## Return all environment variables as exact native `{ name, value }` records.
	## Iteration order is unspecified. A list avoids imposing Unix equality on
	## Windows, where environment variable names are case-insensitive.
	dict! : () => List({ name : OsStr, value : OsStr })
	dict! = ||
		Host.env_dict!().map(
			|variable| {
				name: OsStr.from_raw(variable.name),
				value: OsStr.from_raw(variable.value),
			},
		)

	## Return the architecture and operating system for this host build.
	platform! : () => { arch : ARCH, os : OS }
	platform! = || {
		from_host = Host.env_current_arch_os!("")

		arch =
			match from_host.arch {
				"x86" => X86
				"x86_64" => X64
				"arm" => ARM
				"aarch64" => AARCH64
				other => OTHER(other)
			}

		os =
			match from_host.os {
				"linux" => LINUX
				"macos" => MACOS
				"windows" => WINDOWS
				other => OTHER(other)
			}

		{ arch, os }
	}
}
