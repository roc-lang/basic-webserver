use core::ffi::c_void;
use core::mem::ManuallyDrop;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::abi::{
    roc_host, TcpHostConnectResult, TcpHostConnectResultPayload, TcpHostConnectResultTag,
    TcpHostReadExactlyResult, TcpHostReadUntilResult, TcpHostReadUpToResult,
    TcpHostReadUpToResultPayload, TcpHostReadUpToResultTag, TcpHostWriteResult,
    TcpHostWriteResultPayload, TcpHostWriteResultTag,
};
use crate::capability::{try_lock, CapabilityLockError};
use crate::roc_platform_abi::*;

const TCP_STREAM_BOX_ALIGN: usize = core::mem::align_of::<u64>();
const TCP_OPERATION_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_MATERIALIZED_TCP_BYTES: u64 = 8 * 1024 * 1024;

fn box_tcp_stream(stream: BufReader<TcpStream>, roc_host: &RocHost) -> *mut u64 {
    let raw: *mut Mutex<BufReader<TcpStream>> = Box::into_raw(Box::new(Mutex::new(stream)));
    // SAFETY: the payload is initialized immediately below as a u64 containing
    // the owned stream pointer, matching this layout.
    let boxed = unsafe {
        allocate_box(
            core::mem::size_of::<u64>(),
            TCP_STREAM_BOX_ALIGN,
            false,
            roc_host,
        )
    };
    unsafe {
        *(boxed as *mut u64) = raw as u64;
    }
    boxed as *mut u64
}

unsafe fn tcp_stream_ref<'a>(handle: *mut u64) -> &'a Mutex<BufReader<TcpStream>> {
    &*(*handle as *const Mutex<BufReader<TcpStream>>)
}

extern "C" fn drop_tcp_stream(data_ptr: *mut c_void, _roc_host: *mut RocHost) {
    unsafe {
        let raw = *(data_ptr as *mut u64) as *mut Mutex<BufReader<TcpStream>>;
        if !raw.is_null() {
            drop(Box::from_raw(raw));
        }
    }
}

fn release_tcp_stream(handle: *mut u64, roc_host: &RocHost) {
    // SAFETY: the handle came from `box_tcp_stream` with this exact layout and
    // this call consumes its owned Roc reference.
    unsafe {
        decref_box_with(
            handle as RocBox,
            TCP_STREAM_BOX_ALIGN,
            // The boxed payload is a raw `u64` (a pointer to our BufReader), not a
            // Roc-refcounted value. This must match `box_tcp_stream`.
            false,
            Some(drop_tcp_stream),
            roc_host,
        )
    };
}

fn to_tcp_connect_err(err: io::Error, roc_host: &RocHost) -> RocStr {
    let message = match err.kind() {
        io::ErrorKind::PermissionDenied => "ErrorKind::PermissionDenied".to_string(),
        io::ErrorKind::AddrInUse => "ErrorKind::AddrInUse".to_string(),
        io::ErrorKind::AddrNotAvailable => "ErrorKind::AddrNotAvailable".to_string(),
        io::ErrorKind::ConnectionRefused => "ErrorKind::ConnectionRefused".to_string(),
        io::ErrorKind::Interrupted => "ErrorKind::Interrupted".to_string(),
        io::ErrorKind::TimedOut => "ErrorKind::TimedOut".to_string(),
        io::ErrorKind::Unsupported => "ErrorKind::Unsupported".to_string(),
        other => format!("{:?}", other),
    };
    RocStr::from_str(&message, roc_host)
}

fn to_tcp_stream_err(err: io::Error, roc_host: &RocHost) -> RocStr {
    let message = match err.kind() {
        io::ErrorKind::PermissionDenied => "ErrorKind::PermissionDenied".to_string(),
        io::ErrorKind::ConnectionRefused => "ErrorKind::ConnectionRefused".to_string(),
        io::ErrorKind::ConnectionReset => "ErrorKind::ConnectionReset".to_string(),
        io::ErrorKind::Interrupted => "ErrorKind::Interrupted".to_string(),
        io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock => "ErrorKind::TimedOut".to_string(),
        io::ErrorKind::OutOfMemory => "ErrorKind::OutOfMemory".to_string(),
        io::ErrorKind::BrokenPipe => "ErrorKind::BrokenPipe".to_string(),
        other => format!("{:?}", other),
    };
    RocStr::from_str(&message, roc_host)
}

#[derive(Debug)]
enum ReadUntilError {
    Io(io::Error),
    TooLarge,
}

fn read_until_from_bufread<R: BufRead>(
    stream: &mut R,
    delim: u8,
    max_bytes: u64,
    mut before_fill: impl FnMut(&mut R) -> io::Result<()>,
) -> Result<Vec<u8>, ReadUntilError> {
    let mut buffer = Vec::new();
    loop {
        before_fill(stream).map_err(ReadUntilError::Io)?;
        let (done, used) = {
            let available = match stream.fill_buf() {
                Ok(n) => n,
                Err(ref e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(ReadUntilError::Io(e)),
            };
            let wanted = available
                .iter()
                .position(|&b| b == delim)
                .map_or(available.len(), |index| index + 1);
            let remaining = max_bytes.saturating_sub(buffer.len() as u64) as usize;
            if wanted > remaining {
                buffer.extend_from_slice(&available[..remaining]);
                stream.consume(remaining);
                return Err(ReadUntilError::TooLarge);
            }
            buffer.extend_from_slice(&available[..wanted]);
            (
                wanted != available.len() || available.last() == Some(&delim),
                wanted,
            )
        };
        stream.consume(used);
        if done || used == 0 {
            return Ok(buffer);
        }
    }
}

fn tcp_read_until_impl(
    stream: &mut BufReader<TcpStream>,
    delim: u8,
) -> Result<Vec<u8>, ReadUntilError> {
    let deadline = Instant::now() + TCP_OPERATION_TIMEOUT;
    read_until_from_bufread(stream, delim, MAX_MATERIALIZED_TCP_BYTES, |stream| {
        stream
            .get_mut()
            .set_read_timeout(Some(remaining_timeout(deadline)?))
    })
}

fn try_tcp_connect_ok(handle: *mut u64) -> TcpHostConnectResult {
    TcpHostConnectResult {
        payload: TcpHostConnectResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: TcpHostConnectResultTag::Ok,
    }
}

fn try_tcp_connect_err(error: RocStr) -> TcpHostConnectResult {
    TcpHostConnectResult {
        payload: TcpHostConnectResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: TcpHostConnectResultTag::Err,
    }
}

// The three read host fns share an identical result layout (`Try(List U8, Str)`).
fn try_tcp_read_ok(bytes: RocListWith<u8, false>) -> TcpHostReadUpToResult {
    TcpHostReadUpToResult {
        payload: TcpHostReadUpToResultPayload {
            ok: ManuallyDrop::new(bytes),
        },
        tag: TcpHostReadUpToResultTag::Ok,
    }
}

fn try_tcp_read_err(error: RocStr) -> TcpHostReadUpToResult {
    TcpHostReadUpToResult {
        payload: TcpHostReadUpToResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: TcpHostReadUpToResultTag::Err,
    }
}

fn try_tcp_write_ok() -> TcpHostWriteResult {
    TcpHostWriteResult {
        payload: TcpHostWriteResultPayload { ok: [] },
        tag: TcpHostWriteResultTag::Ok,
    }
}

fn try_tcp_write_err(error: RocStr) -> TcpHostWriteResult {
    TcpHostWriteResult {
        payload: TcpHostWriteResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: TcpHostWriteResultTag::Err,
    }
}

fn tcp_stream_busy(roc_host: &RocHost) -> RocStr {
    RocStr::from_str("StreamBusy", roc_host)
}

fn tcp_stream_unavailable(roc_host: &RocHost) -> RocStr {
    RocStr::from_str("StreamNotFound", roc_host)
}

fn tcp_read_limit_exceeded(roc_host: &RocHost) -> RocStr {
    RocStr::from_str("ReadLimitExceeded", roc_host)
}

fn remaining_timeout(deadline: Instant) -> io::Result<Duration> {
    let remaining = deadline.saturating_duration_since(Instant::now());
    if remaining.is_zero() {
        Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "TCP operation deadline exceeded",
        ))
    } else {
        Ok(remaining)
    }
}

fn connect_with_timeout(host: &str, port: u16) -> io::Result<TcpStream> {
    let addresses = (host, port).to_socket_addrs()?;
    let deadline = Instant::now() + TCP_OPERATION_TIMEOUT;
    let mut last_error = None;
    for address in addresses {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            break;
        }
        match TcpStream::connect_timeout(&address, remaining) {
            Ok(stream) => {
                stream.set_read_timeout(Some(TCP_OPERATION_TIMEOUT))?;
                stream.set_write_timeout(Some(TCP_OPERATION_TIMEOUT))?;
                return Ok(stream);
            }
            Err(error) => last_error = Some(error),
        }
    }
    Err(last_error.unwrap_or_else(|| {
        io::Error::new(
            io::ErrorKind::TimedOut,
            "TCP connection resolution or establishment timed out",
        )
    }))
}

#[no_mangle]
pub extern "C" fn hosted_tcp_connect(host: RocStr, port: u16) -> TcpHostConnectResult {
    let roc_host = roc_host();
    let host_string = host.as_str().to_owned();
    unsafe { host.decref(roc_host) };

    match connect_with_timeout(&host_string, port) {
        Ok(stream) => {
            let handle = box_tcp_stream(BufReader::new(stream), roc_host);
            try_tcp_connect_ok(handle)
        }
        Err(err) => try_tcp_connect_err(to_tcp_connect_err(err, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_tcp_read_up_to(
    handle: *mut u64,
    bytes_to_read: u64,
) -> TcpHostReadUpToResult {
    let roc_host = roc_host();
    let result = {
        if bytes_to_read > MAX_MATERIALIZED_TCP_BYTES {
            try_tcp_read_err(tcp_read_limit_exceeded(roc_host))
        } else {
            let stream = unsafe { tcp_stream_ref(handle) };
            match try_lock(stream) {
                Ok(mut stream) => {
                    let mut chunk = stream.by_ref().take(bytes_to_read);
                    match chunk.fill_buf() {
                        Ok(received) => {
                            let received = received.to_vec();
                            stream.consume(received.len());
                            try_tcp_read_ok(unsafe {
                                RocListWith::<u8, false>::from_slice(&received, roc_host)
                            })
                        }
                        Err(err) => try_tcp_read_err(to_tcp_stream_err(err, roc_host)),
                    }
                }
                Err(CapabilityLockError::Busy) => try_tcp_read_err(tcp_stream_busy(roc_host)),
                Err(CapabilityLockError::Poisoned) => {
                    try_tcp_read_err(tcp_stream_unavailable(roc_host))
                }
            }
        }
    };
    release_tcp_stream(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_tcp_read_exactly(
    handle: *mut u64,
    bytes_to_read: u64,
) -> TcpHostReadExactlyResult {
    let roc_host = roc_host();
    let result = {
        if bytes_to_read > MAX_MATERIALIZED_TCP_BYTES {
            try_tcp_read_err(tcp_read_limit_exceeded(roc_host))
        } else {
            let stream = unsafe { tcp_stream_ref(handle) };
            match try_lock(stream) {
                Ok(mut stream) => {
                    let mut buffer = Vec::with_capacity(bytes_to_read as usize);
                    let mut chunk = [0_u8; 64 * 1024];
                    let deadline = Instant::now() + TCP_OPERATION_TIMEOUT;
                    let read_result = (|| -> io::Result<()> {
                        while buffer.len() as u64 != bytes_to_read {
                            stream
                                .get_mut()
                                .set_read_timeout(Some(remaining_timeout(deadline)?))?;
                            let remaining = (bytes_to_read - buffer.len() as u64) as usize;
                            let chunk_bytes = remaining.min(chunk.len());
                            let read = stream.read(&mut chunk[..chunk_bytes])?;
                            if read == 0 {
                                return Err(io::Error::new(
                                    io::ErrorKind::UnexpectedEof,
                                    "TCP stream ended before the requested byte count",
                                ));
                            }
                            buffer.extend_from_slice(&chunk[..read]);
                        }
                        Ok(())
                    })();
                    match read_result {
                        Ok(()) => try_tcp_read_ok(unsafe {
                            RocListWith::<u8, false>::from_slice(&buffer, roc_host)
                        }),
                        Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => {
                            try_tcp_read_err(RocStr::from_str("UnexpectedEof", roc_host))
                        }
                        Err(error) => try_tcp_read_err(to_tcp_stream_err(error, roc_host)),
                    }
                }
                Err(CapabilityLockError::Busy) => try_tcp_read_err(tcp_stream_busy(roc_host)),
                Err(CapabilityLockError::Poisoned) => {
                    try_tcp_read_err(tcp_stream_unavailable(roc_host))
                }
            }
        }
    };
    release_tcp_stream(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_tcp_read_until(handle: *mut u64, byte: u8) -> TcpHostReadUntilResult {
    let roc_host = roc_host();
    let result = {
        let stream = unsafe { tcp_stream_ref(handle) };
        match try_lock(stream) {
            Ok(mut stream) => match tcp_read_until_impl(&mut stream, byte) {
                Ok(buffer) => try_tcp_read_ok(unsafe {
                    RocListWith::<u8, false>::from_slice(&buffer, roc_host)
                }),
                Err(ReadUntilError::TooLarge) => {
                    try_tcp_read_err(tcp_read_limit_exceeded(roc_host))
                }
                Err(ReadUntilError::Io(err)) => try_tcp_read_err(to_tcp_stream_err(err, roc_host)),
            },
            Err(CapabilityLockError::Busy) => try_tcp_read_err(tcp_stream_busy(roc_host)),
            Err(CapabilityLockError::Poisoned) => {
                try_tcp_read_err(tcp_stream_unavailable(roc_host))
            }
        }
    };
    release_tcp_stream(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_tcp_write(
    handle: *mut u64,
    msg: RocListWith<u8, false>,
) -> TcpHostWriteResult {
    let roc_host = roc_host();
    let result = {
        let stream = unsafe { tcp_stream_ref(handle) };
        match try_lock(stream) {
            Ok(mut stream) => {
                let deadline = Instant::now() + TCP_OPERATION_TIMEOUT;
                let mut written = 0;
                let write_result = (|| -> io::Result<()> {
                    while written != msg.len() {
                        stream
                            .get_mut()
                            .set_write_timeout(Some(remaining_timeout(deadline)?))?;
                        let count = stream.get_mut().write(&msg.as_slice()[written..])?;
                        if count == 0 {
                            return Err(io::Error::new(
                                io::ErrorKind::WriteZero,
                                "failed to write the complete TCP message",
                            ));
                        }
                        written += count;
                    }
                    Ok(())
                })();
                match write_result {
                    Ok(()) => try_tcp_write_ok(),
                    Err(error) => try_tcp_write_err(to_tcp_stream_err(error, roc_host)),
                }
            }
            Err(CapabilityLockError::Busy) => try_tcp_write_err(tcp_stream_busy(roc_host)),
            Err(CapabilityLockError::Poisoned) => {
                try_tcp_write_err(tcp_stream_unavailable(roc_host))
            }
        }
    };
    unsafe { msg.decref(roc_host) };
    release_tcp_stream(handle, roc_host);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn read_until_includes_delimiter() {
        let mut reader = BufReader::new(Cursor::new(b"abc\ndef".to_vec()));

        let bytes = read_until_from_bufread(&mut reader, b'\n', 1024, |_| Ok(())).unwrap();

        assert_eq!(bytes, b"abc\n");
    }

    #[test]
    fn read_until_returns_remaining_bytes_at_eof() {
        let mut reader = BufReader::new(Cursor::new(b"abcdef".to_vec()));

        let bytes = read_until_from_bufread(&mut reader, b'\n', 1024, |_| Ok(())).unwrap();

        assert_eq!(bytes, b"abcdef");
    }

    #[test]
    fn read_until_returns_empty_at_empty_eof() {
        let mut reader = BufReader::new(Cursor::new(Vec::<u8>::new()));

        let bytes = read_until_from_bufread(&mut reader, b'\n', 1024, |_| Ok(())).unwrap();

        assert!(bytes.is_empty());
    }

    #[test]
    fn read_until_enforces_limit_before_growing_the_result() {
        let mut reader = BufReader::new(Cursor::new(b"abcdef\n".to_vec()));

        assert!(matches!(
            read_until_from_bufread(&mut reader, b'\n', 4, |_| Ok(())),
            Err(ReadUntilError::TooLarge)
        ));
        assert_eq!(reader.fill_buf().unwrap(), b"ef\n");
    }
}
