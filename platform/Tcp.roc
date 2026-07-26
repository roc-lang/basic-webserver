import Host

## Connect to TCP servers and exchange buffered byte streams.
##
## Connect, read, and write operations have a 30-second host timeout.
## Materialized reads are limited to 8 MiB; callers should use repeated
## `read_up_to!` operations for larger protocols.
Tcp :: [].{

	## Represents a TCP stream.
	##
	## The connection is automatically closed when the last reference to the
	## stream is dropped. The host synchronizes stream access, so it is safe to
	## retain in application context. A concurrent operation returns
	## `TcpReadErr(StreamBusy)` or `TcpWriteErr(StreamBusy)`.
	Stream :: { host : Host.TcpStream }.{

		## Render the stream without exposing its host handle.
		to_inspect : Stream -> Str
		to_inspect = |_| "Tcp.Stream(<opaque>)"

		## Read up to a number of bytes from this TCP stream. Requests larger
		## than 8 MiB return `TcpReadErr(ReadLimitExceeded)`.
		read_up_to! : Stream, U64 => Try(List(U8), _)
		read_up_to! = |stream, bytes_to_read|
			Host.tcp_read_up_to!(stream.host, bytes_to_read)
				.map_err(|err| TcpReadErr(parse_stream_err(err)))

		## Read an exact number of bytes or fail.
		##
		## `TcpUnexpectedEOF` is returned if the stream ends before the specified
		## number of bytes is reached.
		read_exactly! : Stream, U64 => Try(List(U8), _)
		read_exactly! = |stream, bytes_to_read|
			match Host.tcp_read_exactly!(stream.host, bytes_to_read) {
				Ok(bytes) => Ok(bytes)
				Err("UnexpectedEof") => Err(TcpUnexpectedEOF)
				Err(err) => Err(TcpReadErr(parse_stream_err(err)))
			}

		## Read until a delimiter or EOF is reached. If found, the delimiter is
		## included as the last byte.
		read_until! : Stream, U8 => Try(List(U8), _)
		read_until! = |stream, byte|
			Host.tcp_read_until!(stream.host, byte)
				.map_err(|err| TcpReadErr(parse_stream_err(err)))

		## Read until a newline (`\n`, byte 10) or EOF is reached as UTF-8.
		## If found, the newline is included as the last character.
		read_line! : Stream => Try(Str, _)
		read_line! = |stream|
		# NB: use `match` rather than `?` here — `read_until!` yields a
		# single-variant error union and `?` currently miscompiles (roc#9826).
			match read_until!(stream, 10) {
				Ok(bytes) => Str.from_utf8(bytes).map_err(|err| TcpReadBadUtf8(err))
				Err(err) => Err(err)
			}

		## Write bytes to this TCP stream.
		write! : Stream, List(U8) => Try({}, _)
		write! = |stream, bytes|
			Host.tcp_write!(stream.host, bytes)
				.map_err(|err| TcpWriteErr(parse_stream_err(err)))

		## Write a string to this TCP stream, encoded as UTF-8.
		write_utf8! : Stream, Str => Try({}, _)
		write_utf8! = |stream, str| write!(stream, Str.to_utf8(str))
	}

	## Represents errors that can occur when connecting to a remote host.
	ConnectErr(a) : [

		## The host already retains its maximum of 64 TCP streams.
		CapacityExhausted,
		PermissionDenied,
		AddrInUse,
		AddrNotAvailable,
		ConnectionRefused,
		Interrupted,
		TimedOut,
		Unsupported,
		Unrecognized(Str),
		..a,
	]

	## Represents errors that can occur when performing an effect with a `Stream`.
	StreamErr(a) : [
		StreamNotFound,

		## Another handler is currently reading from or writing to this stream.
		StreamBusy,

		## A materialized read requested or encountered more than 8 MiB.
		ReadLimitExceeded,
		PermissionDenied,
		ConnectionRefused,
		ConnectionReset,
		Interrupted,
		TimedOut,
		OutOfMemory,
		BrokenPipe,
		Unrecognized(Str),
		..a,
	]

	## Opens a TCP connection to a remote host.
	##
	## ```roc
	## # Connect to localhost:8080
	## stream = Tcp.connect!("localhost", 8080)?
	## ```
	##
	## Valid hostnames look like `127.0.0.1`, `::1`, `localhost`, or `roc-lang.org`.
	connect! = |host, port|
		Host.tcp_connect!(host, port)
			.map_ok(|stream| Stream.{ host: stream })
			.map_err(parse_connect_err)

	## Convert a `ConnectErr` to a `Str` you can print.
	connect_err_to_str = |err|
		match err {
			CapacityExhausted => "CapacityExhausted"
			PermissionDenied => "PermissionDenied"
			AddrInUse => "AddrInUse"
			AddrNotAvailable => "AddrNotAvailable"
			ConnectionRefused => "ConnectionRefused"
			Interrupted => "Interrupted"
			TimedOut => "TimedOut"
			Unsupported => "Unsupported"
			Unrecognized(message) => "Unrecognized Error: ${message}"
		}

	## Convert a `StreamErr` to a `Str` you can print.
	stream_err_to_str = |err|
		match err {
			StreamNotFound => "StreamNotFound"
			StreamBusy => "StreamBusy"
			ReadLimitExceeded => "ReadLimitExceeded"
			PermissionDenied => "PermissionDenied"
			ConnectionRefused => "ConnectionRefused"
			ConnectionReset => "ConnectionReset"
			Interrupted => "Interrupted"
			TimedOut => "TimedOut"
			OutOfMemory => "OutOfMemory"
			BrokenPipe => "BrokenPipe"
			Unrecognized(message) => "Unrecognized Error: ${message}"
		}
}

# ---- internal helpers (module-private) -----------------------------------------

parse_connect_err : Str -> Tcp.ConnectErr(a)
parse_connect_err = |err|
	match err {
		"StreamCapacityExhausted" => CapacityExhausted
		"ErrorKind::PermissionDenied" => PermissionDenied
		"ErrorKind::AddrInUse" => AddrInUse
		"ErrorKind::AddrNotAvailable" => AddrNotAvailable
		"ErrorKind::ConnectionRefused" => ConnectionRefused
		"ErrorKind::Interrupted" => Interrupted
		"ErrorKind::TimedOut" => TimedOut
		"ErrorKind::Unsupported" => Unsupported
		other => Unrecognized(other)
	}

parse_stream_err : Str -> Tcp.StreamErr(a)
parse_stream_err = |err|
	match err {
		"StreamNotFound" => StreamNotFound
		"StreamBusy" => StreamBusy
		"ReadLimitExceeded" => ReadLimitExceeded
		"ErrorKind::PermissionDenied" => PermissionDenied
		"ErrorKind::ConnectionRefused" => ConnectionRefused
		"ErrorKind::ConnectionReset" => ConnectionReset
		"ErrorKind::Interrupted" => Interrupted
		"ErrorKind::TimedOut" => TimedOut
		"ErrorKind::OutOfMemory" => OutOfMemory
		"ErrorKind::BrokenPipe" => BrokenPipe
		other => Unrecognized(other)
	}
