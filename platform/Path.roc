import IOErr exposing [IOErr]
import Host
import InternalPath
import path.Path as PathPkg

Path := [].{
    ## Filesystem path type from roc-lang/path.
    Path : PathPkg.Path

    ## Create a Unix path from a Roc string by storing its UTF-8 bytes.
    unix : Str -> PathPkg.Path
    unix = PathPkg.unix

    ## Create a Unix path from raw bytes without validating UTF-8.
    unix_bytes : List(U8) -> PathPkg.Path
    unix_bytes = PathPkg.unix_bytes

    ## Create a Windows path from a Roc string by storing its UTF-16 code units.
    windows : Str -> PathPkg.Path
    windows = PathPkg.windows

    ## Create a Windows path from raw UTF-16 code units.
    windows_u16s : List(U16) -> PathPkg.Path
    windows_u16s = PathPkg.windows_u16s

    ## Convert a path to a string if its raw representation is valid text.
    to_str : PathPkg.Path -> Try(Str, [InvalidStr(U64)])
    to_str = PathPkg.to_str

    ## Convert a path to a display string, replacing invalid text with U+FFFD.
    display : PathPkg.Path -> Str
    display = PathPkg.display

    ## Returns everything after the last directory separator.
    filename : PathPkg.Path -> Try(PathPkg.Path, [IsDirPath, EndsInDots])
    filename = PathPkg.filename

    ## Returns the filename extension without the leading dot.
    ext : PathPkg.Path -> Try(PathPkg.Path, [IsDirPath, EndsInDots])
    ext = PathPkg.ext

    ## Adds a separator and a string component to the path.
    join : PathPkg.Path, Str -> PathPkg.Path
    join = PathPkg.join

    ## Expose the raw OS-specific representation.
    to_raw : PathPkg.Path -> [UnixBytes(List(U8)), WindowsU16s(List(U16))]
    to_raw = PathPkg.to_raw

    ## Build a path from the raw OS-specific representation.
    from_raw : [UnixBytes(List(U8)), WindowsU16s(List(U16))] -> PathPkg.Path
    from_raw = PathPkg.from_raw

    ## Create a Unix path from a Roc string.
    ##
    ## This is kept for compatibility with the older basic-webserver Path API.
    from_str : Str -> PathPkg.Path
    from_str = PathPkg.unix

    ## Returns `Bool.True` if the path exists on disk and is pointing at a regular file.
    ##
    ## This function will traverse symbolic links to query information about the
    ## destination file. In case of broken symbolic links this will return `Bool.False`.
    is_file! : PathPkg.Path => Try(Bool, [PathErr(IOErr), ..])
    is_file! = |path|
        match type!(path) {
            Ok(IsFile) => Ok(Bool.True)
            Ok(_) => Ok(Bool.False)
            Err(err) => Err(err)
        }

    ## Returns `Bool.True` if the path exists on disk and is pointing at a directory.
    ##
    ## This function will traverse symbolic links to query information about the
    ## destination file. In case of broken symbolic links this will return `Bool.False`.
    is_dir! : PathPkg.Path => Try(Bool, [PathErr(IOErr), ..])
    is_dir! = |path|
        match type!(path) {
            Ok(IsDir) => Ok(Bool.True)
            Ok(_) => Ok(Bool.False)
            Err(err) => Err(err)
        }

    ## Returns `Bool.True` if the path exists on disk and is pointing at a symbolic link.
    ##
    ## This function will not traverse symbolic links - it checks whether the path
    ## itself is a symlink.
    is_sym_link! : PathPkg.Path => Try(Bool, [PathErr(IOErr), ..])
    is_sym_link! = |path|
        match type!(path) {
            Ok(IsSymLink) => Ok(Bool.True)
            Ok(_) => Ok(Bool.False)
            Err(err) => Err(err)
        }

    ## Return the type of the path if the path exists on disk.
    type! : PathPkg.Path => Try([IsFile, IsDir, IsSymLink], [PathErr(IOErr), ..])
    type! = |path| {
        match Host.path_type!(InternalPath.to_host_raw(path)) {
            Ok(path_type) =>
                if path_type.is_sym_link {
                    Ok(IsSymLink)
                } else if path_type.is_dir {
                    Ok(IsDir)
                } else {
                    Ok(IsFile)
                }
            Err(err) => Err(PathErr(err))
        }
    }
}
