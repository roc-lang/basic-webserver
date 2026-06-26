import IOErr exposing [IOErr]

# TODO: This is a temporary vendored subset of roc-lang/path until packages can
# be used here. The long-term API should preserve OS paths as raw Unix bytes or
# Windows U16s end-to-end; some current Env and Dir helpers still expose lossy
# Str paths during the migration.

PathType : {
    is_file : Bool,
    is_sym_link : Bool,
    is_dir : Bool,
}

Path :: [
    # We have these different internal representations for two reasons:
    # 1. If I'm calling an OS API, passing a path I got from the OS is definitely safe.
    #    However, passing a Path I got from a RocStr might be unsafe; it may contain \0
    #    characters, which would result in the operation happening on a totally different
    #    path. As such, we need to check for \0s and fail without calling the OS API if we
    #    find one in the path.
    # 2. If I'm converting the Path to a Str, doing that conversion on a Path that was
    #    created from a RocStr needs no further processing. However, if it came from the OS,
    #    then we need to know what charset to assume it had, in order to decode it properly.
    # These come from the OS (e.g. when reading a directory, calling `canonicalize`,
    # or reading an environment variable - which, incidentally, are nul-terminated),
    # so we know they are both nul-terminated and do not contain interior nuls.
    # As such, they can be passed directly to OS APIs.
    #
    # Note that the nul terminator byte is right after the end of the length (into the
    # unused capacity), so this can both be compared directly to other `List U8`s that
    # aren't nul-terminated, while also being able to be passed directly to OS APIs.
    FromOperatingSystem(List(U8)),

    # These come from userspace (e.g. Path.from_bytes), so they need to be checked for interior
    # nuls and then nul-terminated before the host can pass them to OS APIs.
    ArbitraryBytes(List(U8)),

    # This was created as a RocStr, so it might have interior nul bytes but it's definitely UTF-8.
    # That means we can `to_str` it trivially, but have to validate before sending it to OS
    # APIs that expect a nul-terminated `char*`.
    #
    # Note that both UNIX and Windows APIs will accept UTF-8, because on Windows the host calls
    # `_setmbcp(_MB_CP_UTF8);` to set the process's Code Page to UTF-8 before doing anything else.
    # See https://docs.microsoft.com/en-us/windows/apps/design/globalizing/use-utf8-code-page#-a-vs--w-apis
    # and https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/setmbcp?view=msvc-170
    # for more details on the UTF-8 Code Page in Windows.
    FromStr(Str),
].{
    host_path_type! : List(U8) => Try(PathType, IOErr)

    ## Returns `Bool.True` if the path exists on disk and is pointing at a regular file.
    ##
    ## This function will traverse symbolic links to query information about the
    ## destination file. In case of broken symbolic links this will return `Bool.False`.
    is_file! : Path => Try(Bool, [PathErr(IOErr), ..])
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
    is_dir! : Path => Try(Bool, [PathErr(IOErr), ..])
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
    is_sym_link! : Path => Try(Bool, [PathErr(IOErr), ..])
    is_sym_link! = |path|
        match type!(path) {
            Ok(IsSymLink) => Ok(Bool.True)
            Ok(_) => Ok(Bool.False)
            Err(err) => Err(err)
        }

    ## Unfortunately, operating system paths do not include information about which charset
    ## they were originally encoded with. It's most common (but not guaranteed) that they will
    ## have been encoded with the same charset as the operating system's curent locale (which
    ## typically does not change after it is set during installation of the OS), so
    ## this should convert a [Path] to a valid string as long as the path was created
    ## with the given `Charset`. (Use `Env.charset` to get the current system charset.)
    ##
    ## For a conversion to [Str] that is lossy but does not return a [Try], see
    ## [display].
    ## to_inner : Path -> [Str Str, Bytes (List U8)]

    ## Assumes a path is encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8),
    ## and converts it to a string using `Str.from_utf8_lossy`.
    ##
    ## This conversion is lossy because the path may contain invalid UTF-8 bytes. If that happens,
    ## any invalid bytes will be replaced with the [Unicode replacement character](https://unicode.org/glossary/#replacement_character)
    ## instead of returning an error. As such, it's rarely a good idea to use the [Str] returned
    ## by this function for any purpose other than displaying it to a user.
    ##
    ## When you don't know for sure what a path's encoding is, UTF-8 is a popular guess because
    ## it's the default on UNIX and also is the encoding used in Roc strings. This platform also
    ## automatically runs applications under the [UTF-8 code page](https://docs.microsoft.com/en-us/windows/apps/design/globalizing/use-utf8-code-page)
    ## on Windows.
    ##
    ## Converting paths to strings can be an unreliable operation, because operating systems
    ## don't record the paths' encodings. This means it's possible for the path to have been
    ## encoded with a different character set than UTF-8 even if UTF-8 is the system default,
    ## which means when [display] converts them to a string, the string may include gibberish.
    ## [Here is an example.](https://unix.stackexchange.com/questions/667652/can-a-file-path-be-invalid-utf-8/667863#667863)
    ##
    ## If you happen to know the `Charset` that was used to encode the path, you can use
    ## `to_str_using_charset` (TODO) instead of [display].
    display : Path -> Str
    display = |path|
        match path {
            FromStr(str) => str

            FromOperatingSystem(bytes) | ArbitraryBytes(bytes) =>

                match Str.from_utf8(bytes) {
                    Ok(str) => str
                    Err(_) => Str.from_utf8_lossy(bytes)
                }
        }

    ## Note that the path may not be valid depending on the filesystem where it is used.
    ## For example, paths containing `:` are valid on ext4 and NTFS filesystems, but not
    ## on FAT ones. So if you have multiple disks on the same machine, but they have
    ## different filesystems, then this path could be valid on one but invalid on another!
    ##
    ## It's safest to assume paths are invalid (even syntactically) until given to an operation
    ## which uses them to open a file. If that operation succeeds, then the path was valid
    ## (at the time). Otherwise, error handling can happen for that operation rather than validating
    ## up front for a false sense of security (given symlinks, parts of a path being renamed, etc.).
    from_str : Str -> Path
    from_str = |str|
        FromStr(str)

    # TODO add charset and to_str_using_charset function, see display comment

    ## Return the type of the path if the path exists on disk.
    ##
    ## > [`File.type`](File#type!) does the same thing, except it takes a [Str] instead of a [Path].
    type! : Path => Try([IsFile, IsDir, IsSymLink], [PathErr(IOErr), ..])
    type! = |path| {
        Path.host_path_type!(to_bytes(path))
            .map_err(|err| PathErr(err))
            .map_ok(|path_type|{
                if path_type.is_sym_link {
                    IsSymLink
                } else if path_type.is_dir {
                    IsDir
                } else {
                    IsFile
                }
            })
    }
}

## TODO do this in the host, and iterate over the Str
## bytes when possible instead of always converting to
## a heap-allocated List.
to_bytes : Path -> List(U8)
to_bytes = |path|
    match path {
        FromOperatingSystem(bytes) => bytes
        ArbitraryBytes(bytes) => bytes
        FromStr(str) => Str.to_utf8(str)
    }
