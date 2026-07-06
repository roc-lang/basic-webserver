import IOErr exposing [IOErr]
import Host

File := [].{
    ## Read all bytes from a file.
    read_bytes! : Str => Try(List(U8), [FileErr(IOErr), ..])
    read_bytes! = |path| Ok(Host.file_read_bytes!(path)?)

    ## Write bytes to a file, replacing any existing contents.
    write_bytes! : Str, List(U8) => Try({}, [FileErr(IOErr), ..])
    write_bytes! = |path, bytes| Ok(Host.file_write_bytes!(path, bytes)?)

    ## Read a file's contents as a UTF-8 string.
    ##
    ## If the file contains invalid UTF-8, the invalid parts will be replaced with the
    ## [Unicode replacement character](https://unicode.org/glossary/#replacement_character).
    read_utf8! : Str => Try(Str, [FileErr(IOErr), ..])
    read_utf8! = |path| Ok(Host.file_read_utf8!(path)?)

    ## Write a UTF-8 string to a file, replacing any existing contents.
    write_utf8! : Str, Str => Try({}, [FileErr(IOErr), ..])
    write_utf8! = |path, content| Ok(Host.file_write_utf8!(path, content)?)

    ## Delete a file.
    delete! : Str => Try({}, [FileErr(IOErr), ..])
    delete! = |path| Ok(Host.file_delete!(path)?)

    ## Returns the size of a file in bytes.
    size_in_bytes! : Str => Try(U64, [FileErr(IOErr), ..])
    size_in_bytes! = |path| Ok(Host.file_size_in_bytes!(path)?)

    ## Checks if the file has any executable bit set.
    is_executable! : Str => Try(Bool, [FileErr(IOErr), ..])
    is_executable! = |path| Ok(Host.file_is_executable!(path)?)

    ## Checks if the file has a readable owner permission bit set.
    is_readable! : Str => Try(Bool, [FileErr(IOErr), ..])
    is_readable! = |path| Ok(Host.file_is_readable!(path)?)

    ## Checks if the file has a writable owner permission bit set.
    is_writable! : Str => Try(Bool, [FileErr(IOErr), ..])
    is_writable! = |path| Ok(Host.file_is_writable!(path)?)

    ## Returns the time when the file was last accessed as nanoseconds since the Unix epoch.
    time_accessed! : Str => Try(U128, [FileErr(IOErr), ..])
    time_accessed! = |path| Ok(Host.file_time_accessed!(path)?)

    ## Returns the time when the file was last modified as nanoseconds since the Unix epoch.
    time_modified! : Str => Try(U128, [FileErr(IOErr), ..])
    time_modified! = |path| Ok(Host.file_time_modified!(path)?)

    ## Returns the time when the file was created as nanoseconds since the Unix epoch.
    time_created! : Str => Try(U128, [FileErr(IOErr), ..])
    time_created! = |path| Ok(Host.file_time_created!(path)?)
}
