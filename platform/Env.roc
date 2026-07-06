import Host

Env := [].{
    ## Reads the given environment variable.
    ##
    ## If the value is invalid Unicode, the invalid parts will be replaced with the
    ## [Unicode replacement character](https://unicode.org/glossary/#replacement_character).
    ##
    ## Returns `Err(VarNotFound(name))` if the variable is not set.
    var! : Str => Try(Str, [VarNotFound(Str), ..])
    var! = |name| Ok(Host.env_var!(name)?)

    ## Reads the [current working directory](https://en.wikipedia.org/wiki/Working_directory)
    ## from the environment.
    ##
    ## TODO: Return Path.Path once this zero-argument Try-returning API can be
    ## changed safely without triggering the current runtime crash.
    ##
    ## Returns `Err(CwdUnavailable)` if the cwd cannot be determined.
    cwd! : () => Try(Str, [CwdUnavailable, ..])
    cwd! = ||
        match Host.env_cwd!("") {
            Ok(path) => Ok(path)
            Err(_) => Err(CwdUnavailable)
        }

    ## Gets the path to the currently-running executable.
    ##
    ## TODO: Return Path.Path once this zero-argument Try-returning API can be
    ## changed safely without triggering the current runtime crash.
    ##
    ## Returns `Err(ExePathUnavailable)` if the path cannot be determined.
    exe_path! : () => Try(Str, [ExePathUnavailable, ..])
    exe_path! = ||
        match Host.env_exe_path!("") {
            Ok(path) => Ok(path)
            Err(_) => Err(ExePathUnavailable)
        }

    ## Gets the default directory for temporary files.
    ##
    ## TODO: Return Path.Path with cwd! and exe_path! once the compiler/runtime
    ## issue is resolved.
    temp_dir! : () => Str
    temp_dir! = || Host.env_temp_dir!("")
}
