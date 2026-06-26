import IOErr exposing [IOErr]

File := [].{
    ## Read all bytes from a file.
    read_bytes! : Str => Try(List(U8), [FileErr(IOErr), ..])

    ## Write bytes to a file, replacing any existing contents.
    write_bytes! : Str, List(U8) => Try({}, [FileErr(IOErr), ..])

    ## Read a file's contents as a UTF-8 string.
    ##
    ## If the file contains invalid UTF-8, the invalid parts will be replaced with the
    ## [Unicode replacement character](https://unicode.org/glossary/#replacement_character).
    read_utf8! : Str => Try(Str, [FileErr(IOErr), ..])

    ## Write a UTF-8 string to a file, replacing any existing contents.
    write_utf8! : Str, Str => Try({}, [FileErr(IOErr), ..])

    ## Delete a file.
    delete! : Str => Try({}, [FileErr(IOErr), ..])

    ## Returns the size of a file in bytes.
    size_in_bytes! : Str => Try(U64, [FileErr(IOErr), ..])

    ## Checks if the file has any executable bit set.
    is_executable! : Str => Try(Bool, [FileErr(IOErr), ..])

    ## Checks if the file has a readable owner permission bit set.
    is_readable! : Str => Try(Bool, [FileErr(IOErr), ..])

    ## Checks if the file has a writable owner permission bit set.
    is_writable! : Str => Try(Bool, [FileErr(IOErr), ..])

    ## Returns the time when the file was last accessed as nanoseconds since the Unix epoch.
    time_accessed! : Str => Try(U128, [FileErr(IOErr), ..])

    ## Returns the time when the file was last modified as nanoseconds since the Unix epoch.
    time_modified! : Str => Try(U128, [FileErr(IOErr), ..])

    ## Returns the time when the file was created as nanoseconds since the Unix epoch.
    time_created! : Str => Try(U128, [FileErr(IOErr), ..])
}
