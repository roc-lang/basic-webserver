import Host
import InternalPath
import Path exposing [Path]

Env := [].{
    ARCH : [X86, X64, ARM, AARCH64, OTHER(Str)]
    OS : [LINUX, MACOS, WINDOWS, OTHER(Str)]

    ## Reads the given environment variable.
    ##
    ## If the value is invalid Unicode, the invalid parts will be replaced with the
    ## [Unicode replacement character](https://unicode.org/glossary/#replacement_character).
    ##
    ## Returns `Err(VarNotFound(name))` if the variable is not set.
    var! : Str => Try(Str, [VarNotFound(Str), ..])
    var! = |name|
        match Host.env_var!(name) {
            Ok(value) => Ok(value)
            Err(VarNotFound(missing_name)) => Err(VarNotFound(missing_name))
        }

    ## Reads the [current working directory](https://en.wikipedia.org/wiki/Working_directory)
    ## from the environment.
    ##
    ## Returns `Err(CwdUnavailable)` if the cwd cannot be determined.
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

    ## Sets the current working directory in the environment. After changing it,
    ## relative file operations resolve from the new directory.
    set_cwd! : Path => Try({}, [InvalidCwd, ..])
    set_cwd! = |path|
        match Host.env_set_cwd!(InternalPath.to_host_raw!(path)) {
            Ok(done) => Ok(done)
            Err(_) => Err(InvalidCwd)
        }

    ## Gets the path to the currently-running executable.
    ##
    ## Returns `Err(ExePathUnavailable)` if the path cannot be determined.
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

    ## Gets the default directory for temporary files.
    temp_dir! : () => Path
    temp_dir! = || InternalPath.from_host_raw(Host.env_temp_dir!(""))

    ## Reads all process environment variables into a Dict.
    dict! : () => Dict(Str, Str)
    dict! = ||
        List.fold(
            Host.env_dict!(""),
            Dict.empty(),
            |dict, { key, value }| Dict.insert(dict, key, value),
        )

    ## Returns the current architecture and operating system.
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
