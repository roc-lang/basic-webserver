import Host
import InternalPath
import path.Path as PathPkg

Env := [].{
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
    cwd! : () => Try(PathPkg.Path, [CwdUnavailable, ..])
    cwd! = || {
        if Host.env_is_windows!("") {
            match Host.env_cwd_windows!("") {
                Ok(u16s) => Ok(PathPkg.windows_u16s(u16s))
                Err(_) => Err(CwdUnavailable)
            }
        } else {
            match Host.env_cwd_unix!("") {
                Ok(bytes) => Ok(PathPkg.unix_bytes(bytes))
                Err(_) => Err(CwdUnavailable)
            }
        }
    }

    ## Gets the path to the currently-running executable.
    ##
    ## Returns `Err(ExePathUnavailable)` if the path cannot be determined.
    exe_path! : () => Try(PathPkg.Path, [ExePathUnavailable, ..])
    exe_path! = || {
        if Host.env_is_windows!("") {
            match Host.env_exe_path_windows!("") {
                Ok(u16s) => Ok(PathPkg.windows_u16s(u16s))
                Err(_) => Err(ExePathUnavailable)
            }
        } else {
            match Host.env_exe_path_unix!("") {
                Ok(bytes) => Ok(PathPkg.unix_bytes(bytes))
                Err(_) => Err(ExePathUnavailable)
            }
        }
    }

    ## Gets the default directory for temporary files.
    temp_dir! : () => PathPkg.Path
    temp_dir! = || InternalPath.from_host_raw(Host.env_temp_dir!(""))
}
