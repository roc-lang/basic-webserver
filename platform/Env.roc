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
    ## TODO: This temporarily returns a lossy Str path. When the vendored Path
    ## subset is replaced by roc-lang/path, return a byte-preserving Path value.
    ##
    ## Returns `Err(CwdUnavailable)` if the cwd cannot be determined.
    cwd! : {} => Try(Str, [CwdUnavailable, ..])
    cwd! = |{}| Ok(Host.env_cwd!({})?)

    ## Gets the path to the currently-running executable.
    ##
    ## TODO: This temporarily returns a lossy Str path. When the vendored Path
    ## subset is replaced by roc-lang/path, return a byte-preserving Path value.
    ##
    ## Returns `Err(ExePathUnavailable)` if the path cannot be determined.
    exe_path! : {} => Try(Str, [ExePathUnavailable, ..])
    exe_path! = |{}| Ok(Host.env_exe_path!({})?)

    ## Gets the default directory for temporary files.
    ##
    ## TODO: This temporarily returns a lossy Str path. When the vendored Path
    ## subset is replaced by roc-lang/path, return a byte-preserving Path value.
    temp_dir! : {} => Str
    temp_dir! = |{}| Host.env_temp_dir!({})
}
