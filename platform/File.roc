import IOErr exposing [IOErr]
import Host

File := [].{
    ## Represents a buffered file reader.
    ##
    ## The file is automatically closed when the last reference to the reader is
    ## dropped. This is an opaque `Box(U64)` handle into a host-side
    ## `BufReader<File>`.
    Reader : Host.FileReader

    ## Read all bytes from a file.
    read_bytes! : Str => Try(List(U8), [FileErr(IOErr), ..])
    read_bytes! = |path|
        match Host.file_read_bytes!(path) {
            Ok(bytes) => Ok(bytes)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Write bytes to a file, replacing any existing contents.
    write_bytes! : Str, List(U8) => Try({}, [FileErr(IOErr), ..])
    write_bytes! = |path, bytes|
        match Host.file_write_bytes!(path, bytes) {
            Ok(done) => Ok(done)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Read a file's contents as a UTF-8 string.
    ##
    ## If the file contains invalid UTF-8, the invalid parts will be replaced with the
    ## [Unicode replacement character](https://unicode.org/glossary/#replacement_character).
    read_utf8! : Str => Try(Str, [FileErr(IOErr), ..])
    read_utf8! = |path|
        match Host.file_read_utf8!(path) {
            Ok(content) => Ok(content)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Write a UTF-8 string to a file, replacing any existing contents.
    write_utf8! : Str, Str => Try({}, [FileErr(IOErr), ..])
    write_utf8! = |path, content|
        match Host.file_write_utf8!(path, content) {
            Ok(done) => Ok(done)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Open a file for buffered reading using the default buffer capacity.
    ##
    ## ```roc
    ## reader = File.open_reader!("LICENSE")?
    ## line = File.read_line!(reader)?
    ## ```
    open_reader! : Str => Try(Reader, [FileErr(IOErr), ..])
    open_reader! = |path|
        match Host.file_open_reader!(path, 0) {
            Ok(reader) => Ok(reader)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Open a file for buffered reading using a specific buffer capacity.
    open_reader_with_capacity! : Str, U64 => Try(Reader, [FileErr(IOErr), ..])
    open_reader_with_capacity! = |path, capacity|
        match Host.file_open_reader!(path, capacity) {
            Ok(reader) => Ok(reader)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Read bytes up to and including the next newline from a buffered reader.
    ##
    ## Returns an empty list at EOF.
    read_line! : Reader => Try(List(U8), [FileErr(IOErr), ..])
    read_line! = |reader|
        match Host.file_read_line!(reader) {
            Ok(bytes) => Ok(bytes)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Delete a file.
    delete! : Str => Try({}, [FileErr(IOErr), ..])
    delete! = |path|
        match Host.file_delete!(path) {
            Ok(done) => Ok(done)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Returns the size of a file in bytes.
    size_in_bytes! : Str => Try(U64, [FileErr(IOErr), ..])
    size_in_bytes! = |path|
        match Host.file_size_in_bytes!(path) {
            Ok(size) => Ok(size)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Checks if the file has any executable bit set.
    is_executable! : Str => Try(Bool, [FileErr(IOErr), ..])
    is_executable! = |path|
        match Host.file_is_executable!(path) {
            Ok(is_executable) => Ok(is_executable)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Checks if the file has a readable owner permission bit set.
    is_readable! : Str => Try(Bool, [FileErr(IOErr), ..])
    is_readable! = |path|
        match Host.file_is_readable!(path) {
            Ok(is_readable) => Ok(is_readable)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Checks if the file has a writable owner permission bit set.
    is_writable! : Str => Try(Bool, [FileErr(IOErr), ..])
    is_writable! = |path|
        match Host.file_is_writable!(path) {
            Ok(is_writable) => Ok(is_writable)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Returns the time when the file was last accessed as nanoseconds since the Unix epoch.
    time_accessed! : Str => Try(U128, [FileErr(IOErr), ..])
    time_accessed! = |path|
        match Host.file_time_accessed!(path) {
            Ok(time) => Ok(time)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Returns the time when the file was last modified as nanoseconds since the Unix epoch.
    time_modified! : Str => Try(U128, [FileErr(IOErr), ..])
    time_modified! = |path|
        match Host.file_time_modified!(path) {
            Ok(time) => Ok(time)
            Err(FileErr(err)) => Err(FileErr(err))
        }

    ## Returns the time when the file was created as nanoseconds since the Unix epoch.
    time_created! : Str => Try(U128, [FileErr(IOErr), ..])
    time_created! = |path|
        match Host.file_time_created!(path) {
            Ok(time) => Ok(time)
            Err(FileErr(err)) => Err(FileErr(err))
        }
}
