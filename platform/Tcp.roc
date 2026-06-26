Tcp := [].{
    ## Represents a TCP stream.
    ##
    ## The connection is automatically closed when the last reference to the
    ## stream is dropped. This is an opaque `Box(U64)` handle into a host-side
    ## `BufReader<TcpStream>`.
    Stream :: Box(U64)

    # ---- Host functions (the FFI boundary) -------------------------------------
    # Errors are carried across as raw `Str` and parsed into tag unions below.

    host_connect! : Str, U16 => Try(Stream, Str)
    host_read_up_to! : Stream, U64 => Try(List(U8), Str)
    host_read_exactly! : Stream, U64 => Try(List(U8), Str)
    host_read_until! : Stream, U8 => Try(List(U8), Str)
    host_write! : Stream, List(U8) => Try({}, Str)

    ## Represents errors that can occur when connecting to a remote host.
    ConnectErr : [
        PermissionDenied,
        AddrInUse,
        AddrNotAvailable,
        ConnectionRefused,
        Interrupted,
        TimedOut,
        Unsupported,
        Unrecognized(Str),
    ]

    ## Represents errors that can occur when performing an effect with a [Stream].
    StreamErr : [
        StreamNotFound,
        PermissionDenied,
        ConnectionRefused,
        ConnectionReset,
        Interrupted,
        OutOfMemory,
        BrokenPipe,
        Unrecognized(Str),
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
        Tcp.host_connect!(host, port).map_err(parse_connect_err)

    ## Read up to a number of bytes from the TCP stream.
    ##
    ## ```roc
    ## received_bytes = Tcp.read_up_to!(stream, 64)?
    ## ```
    ##
    ## > To read an exact number of bytes or fail, use [Tcp.read_exactly!] instead.
    read_up_to! = |stream, bytes_to_read|
        Tcp.host_read_up_to!(stream, bytes_to_read)
            .map_err(|err| TcpReadErr(parse_stream_err(err)))

    ## Read an exact number of bytes or fail.
    ##
    ## ```roc
    ## bytes = Tcp.read_exactly!(stream, 64)?
    ## ```
    ##
    ## `TcpUnexpectedEOF` is returned if the stream ends before the specified
    ## number of bytes is reached.
    read_exactly! = |stream, bytes_to_read|
        match Tcp.host_read_exactly!(stream, bytes_to_read) {
            Ok(bytes) => Ok(bytes)
            Err("UnexpectedEof") => Err(TcpUnexpectedEOF)
            Err(err) => Err(TcpReadErr(parse_stream_err(err)))
        }

    ## Read until a delimiter or EOF is reached.
    ##
    ## ```roc
    ## # Read until null terminator
    ## bytes = Tcp.read_until!(stream, 0)?
    ## ```
    ##
    ## If found, the delimiter is included as the last byte.
    read_until! = |stream, byte|
        Tcp.host_read_until!(stream, byte)
            .map_err(|err| TcpReadErr(parse_stream_err(err)))

    ## Read until a newline (`\n`, byte 10) or EOF is reached, decoded as a [Str].
    ##
    ## ```roc
    ## line_str = Tcp.read_line!(stream)?
    ## ```
    ##
    ## If found, the newline is included as the last character in the [Str].
    read_line! = |stream|
        # NB: use `match` rather than `?` here — `read_until!` yields a single-
        # variant error union and `?` on that currently miscompiles (roc#9826).
        match read_until!(stream, 10) {
            Ok(bytes) => Str.from_utf8(bytes).map_err(|err| TcpReadBadUtf8(err))
            Err(err) => Err(err)
        }

    ## Writes bytes to a TCP stream.
    ##
    ## ```roc
    ## # Writes the bytes 1, 2, 3
    ## Tcp.write!(stream, [1, 2, 3])?
    ## ```
    ##
    ## > To write a [Str], use [Tcp.write_utf8!] instead.
    write! = |stream, bytes|
        Tcp.host_write!(stream, bytes)
            .map_err(|err| TcpWriteErr(parse_stream_err(err)))

    ## Writes a [Str] to a TCP stream, encoded as UTF-8.
    ##
    ## ```roc
    ## Tcp.write_utf8!(stream, "Hi from Roc!")?
    ## ```
    write_utf8! = |stream, str|
        write!(stream, Str.to_utf8(str))

    ## Convert a [ConnectErr] to a [Str] you can print.
    connect_err_to_str = |err|
        match err {
            PermissionDenied => "PermissionDenied"
            AddrInUse => "AddrInUse"
            AddrNotAvailable => "AddrNotAvailable"
            ConnectionRefused => "ConnectionRefused"
            Interrupted => "Interrupted"
            TimedOut => "TimedOut"
            Unsupported => "Unsupported"
            Unrecognized(message) => "Unrecognized Error: ${message}"
        }

    ## Convert a [StreamErr] to a [Str] you can print.
    stream_err_to_str = |err|
        match err {
            StreamNotFound => "StreamNotFound"
            PermissionDenied => "PermissionDenied"
            ConnectionRefused => "ConnectionRefused"
            ConnectionReset => "ConnectionReset"
            Interrupted => "Interrupted"
            OutOfMemory => "OutOfMemory"
            BrokenPipe => "BrokenPipe"
            Unrecognized(message) => "Unrecognized Error: ${message}"
        }
}

# ---- internal helpers (module-private) -----------------------------------------

parse_connect_err = |err|
    match err {
        "ErrorKind::PermissionDenied" => PermissionDenied
        "ErrorKind::AddrInUse" => AddrInUse
        "ErrorKind::AddrNotAvailable" => AddrNotAvailable
        "ErrorKind::ConnectionRefused" => ConnectionRefused
        "ErrorKind::Interrupted" => Interrupted
        "ErrorKind::TimedOut" => TimedOut
        "ErrorKind::Unsupported" => Unsupported
        other => Unrecognized(other)
    }

parse_stream_err = |err|
    match err {
        "StreamNotFound" => StreamNotFound
        "ErrorKind::PermissionDenied" => PermissionDenied
        "ErrorKind::ConnectionRefused" => ConnectionRefused
        "ErrorKind::ConnectionReset" => ConnectionReset
        "ErrorKind::Interrupted" => Interrupted
        "ErrorKind::OutOfMemory" => OutOfMemory
        "ErrorKind::BrokenPipe" => BrokenPipe
        other => Unrecognized(other)
    }
