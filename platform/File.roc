import Host
import InternalPath
import Path

## Open files for incremental, buffered reading.
##
## Whole-file operations and filesystem metadata are available on [`Path`](Path).
File :: [].{

	## Represents a buffered file reader.
	##
	## Close it explicitly when reading stops before EOF. Reaching EOF also closes
	## it, and server shutdown closes any remaining readers. The host synchronizes
	## its cursor, so it is safe to retain in application context. Concurrent
	## reads saturate with `FileErr(Other(...))`.
	Reader :: { host : Host.FileReader }.{

		## Render the reader without exposing its host handle.
		to_inspect : Reader -> Str
		to_inspect = |_| "File.Reader(<opaque>)"

		## Read bytes up to and including the next newline from this buffered reader.
		## A line larger than the platform's 8 MiB materialization limit fails
		## with `FileErr(Other(_))`; process large records in a format with
		## bounded delimiters.
		##
		## Returns an empty list at EOF.
		read_line! : Reader => Try(List(U8), _)
		read_line! = |reader|
			Host.file_read_line!(reader.host)
				.map_err(|FileErr(err)| FileErr(err))

		## Close this reader. Closing an already closed reader is harmless.
		close! : Reader => {}
		close! = |reader| Host.file_close_reader!(reader.host)
	}

	## Open a file for buffered reading using the default buffer capacity.
	##
	## ```roc
	## reader = File.open_reader!("LICENSE")?
	## line = reader.read_line!()?
	## ```
	open_reader! = |path|
		Host.file_open_reader!(InternalPath.to_host_raw!(path), 0)
			.map_ok(|reader| Reader.{ host: reader })
			.map_err(|FileErr(err)| FileErr(err))

	## Open a file for buffered reading using a specific buffer capacity. The
	## capacity must not exceed 1 MiB.
	open_reader_with_capacity! = |path, capacity|
		Host.file_open_reader!(InternalPath.to_host_raw!(path), capacity)
			.map_ok(|reader| Reader.{ host: reader })
			.map_err(|FileErr(err)| FileErr(err))
}
