use core::ffi::c_void;
use core::mem::ManuallyDrop;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::{mpsc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use crate::abi::{
    roc_host, TcpHostConnectResult, TcpHostConnectResultPayload, TcpHostConnectResultTag,
    TcpHostReadExactlyResult, TcpHostReadUntilResult, TcpHostReadUpToResult,
    TcpHostReadUpToResultPayload, TcpHostReadUpToResultTag, TcpHostWriteResult,
    TcpHostWriteResultPayload, TcpHostWriteResultTag,
};
use crate::bounded_gate::{AcquireError, BoundedGate};
use crate::capability::{try_lock, CapabilityLockError};
use crate::host_resource::{
    DeallocRoute, HostResourceHeap, LookupError, ReserveError, ResourceReservation,
};
use crate::roc_platform_abi::*;

const TCP_OPERATION_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_MATERIALIZED_TCP_BYTES: u64 = 8 * 1024 * 1024;
const MAX_OPEN_TCP_STREAMS: usize = 64;

type TcpResource = Mutex<BufReader<TcpStream>>;

static TCP_STREAMS: OnceLock<HostResourceHeap<TcpResource>> = OnceLock::new();
static TCP_RESOLUTION_GATE: BoundedGate =
    BoundedGate::new(MAX_OPEN_TCP_STREAMS, MAX_OPEN_TCP_STREAMS);

fn tcp_streams() -> &'static HostResourceHeap<TcpResource> {
    TCP_STREAMS.get_or_init(|| HostResourceHeap::new(MAX_OPEN_TCP_STREAMS))
}

fn reserve_tcp_stream() -> Result<ResourceReservation<'static, TcpResource>, ReserveError> {
    tcp_streams().reserve()
}

unsafe fn tcp_stream_ref(handle: *mut u64) -> Result<&'static TcpResource, LookupError> {
    unsafe { tcp_streams().get(handle) }
}

fn release_tcp_stream(handle: *mut u64, roc_host: &RocHost) {
    // SAFETY: hosted arguments transfer one owned Roc reference. Final release
    // routes through the resource heap and closes the stream.
    unsafe { decref_box(handle as RocBox, roc_host) };
}

pub(crate) fn route_resource_dealloc(ptr: *mut c_void) -> DeallocRoute {
    match TCP_STREAMS.get() {
        Some(heap) => heap.route_dealloc(ptr),
        None => DeallocRoute::NotOwned,
    }
}

pub(crate) fn contains_resource_address(ptr: *const c_void) -> bool {
    TCP_STREAMS
        .get()
        .is_some_and(|heap| heap.contains_address(ptr))
}

pub(crate) fn active_resources() -> usize {
    TCP_STREAMS.get().map_or(0, HostResourceHeap::active)
}

pub(crate) fn resource_high_water() -> usize {
    TCP_STREAMS.get().map_or(0, HostResourceHeap::high_water)
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

fn tcp_read_up_to_impl(
    stream: &mut BufReader<TcpStream>,
    bytes_to_read: u64,
) -> io::Result<Vec<u8>> {
    stream
        .get_mut()
        .set_read_timeout(Some(TCP_OPERATION_TIMEOUT))?;
    let mut chunk = stream.by_ref().take(bytes_to_read);
    let received = chunk.fill_buf()?.to_vec();
    stream.consume(received.len());
    Ok(received)
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

fn run_resolver_with_deadline(
    deadline: Instant,
    resolve: impl FnOnce() -> io::Result<Vec<SocketAddr>> + Send + 'static,
) -> io::Result<Vec<SocketAddr>> {
    let permit = TCP_RESOLUTION_GATE.acquire(deadline).map_err(|error| {
        let message = match error {
            AcquireError::Saturated => "TCP name resolver capacity exhausted",
            AcquireError::TimedOut => "TCP name resolution deadline exceeded",
        };
        io::Error::new(io::ErrorKind::TimedOut, message)
    })?;
    let (sender, receiver) = mpsc::sync_channel(1);
    thread::Builder::new()
        .name("roc-tcp-resolver".to_owned())
        .spawn(move || {
            let result = resolve();
            let _ = sender.send(result);
            drop(permit);
        })?;

    match receiver.recv_timeout(remaining_timeout(deadline)?) {
        Ok(result) => result,
        Err(mpsc::RecvTimeoutError::Timeout) => Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "TCP name resolution deadline exceeded",
        )),
        Err(mpsc::RecvTimeoutError::Disconnected) => {
            Err(io::Error::other("TCP name resolver stopped unexpectedly"))
        }
    }
}

fn resolve_addresses(host: &str, port: u16, deadline: Instant) -> io::Result<Vec<SocketAddr>> {
    if let Ok(address) = host.parse::<IpAddr>() {
        return Ok(vec![SocketAddr::new(address, port)]);
    }

    let host = host.to_owned();
    run_resolver_with_deadline(deadline, move || {
        (host.as_str(), port)
            .to_socket_addrs()
            .map(|addresses| addresses.collect())
    })
}

fn connect_with_timeout(host: &str, port: u16) -> io::Result<TcpStream> {
    let deadline = Instant::now() + TCP_OPERATION_TIMEOUT;
    let addresses = resolve_addresses(host, port, deadline)?;
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

    let reservation = match reserve_tcp_stream() {
        Ok(reservation) => reservation,
        Err(ReserveError::Capacity) => {
            return try_tcp_connect_err(RocStr::from_str("StreamCapacityExhausted", roc_host));
        }
    };
    match connect_with_timeout(&host_string, port) {
        Ok(stream) => {
            let handle = reservation.insert(Mutex::new(BufReader::new(stream)));
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
            match unsafe { tcp_stream_ref(handle) } {
                Ok(stream) => match try_lock(stream) {
                    Ok(mut stream) => match tcp_read_up_to_impl(&mut stream, bytes_to_read) {
                        Ok(received) => try_tcp_read_ok(unsafe {
                            RocListWith::<u8, false>::from_slice(&received, roc_host)
                        }),
                        Err(err) => try_tcp_read_err(to_tcp_stream_err(err, roc_host)),
                    },
                    Err(CapabilityLockError::Busy) => try_tcp_read_err(tcp_stream_busy(roc_host)),
                    Err(CapabilityLockError::Poisoned) => {
                        try_tcp_read_err(tcp_stream_unavailable(roc_host))
                    }
                },
                Err(_) => try_tcp_read_err(tcp_stream_unavailable(roc_host)),
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
            match unsafe { tcp_stream_ref(handle) } {
                Ok(stream) => match try_lock(stream) {
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
                },
                Err(_) => try_tcp_read_err(tcp_stream_unavailable(roc_host)),
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
        match unsafe { tcp_stream_ref(handle) } {
            Ok(stream) => match try_lock(stream) {
                Ok(mut stream) => match tcp_read_until_impl(&mut stream, byte) {
                    Ok(buffer) => try_tcp_read_ok(unsafe {
                        RocListWith::<u8, false>::from_slice(&buffer, roc_host)
                    }),
                    Err(ReadUntilError::TooLarge) => {
                        try_tcp_read_err(tcp_read_limit_exceeded(roc_host))
                    }
                    Err(ReadUntilError::Io(err)) => {
                        try_tcp_read_err(to_tcp_stream_err(err, roc_host))
                    }
                },
                Err(CapabilityLockError::Busy) => try_tcp_read_err(tcp_stream_busy(roc_host)),
                Err(CapabilityLockError::Poisoned) => {
                    try_tcp_read_err(tcp_stream_unavailable(roc_host))
                }
            },
            Err(_) => try_tcp_read_err(tcp_stream_unavailable(roc_host)),
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
        match unsafe { tcp_stream_ref(handle) } {
            Ok(stream) => match try_lock(stream) {
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
            },
            Err(_) => try_tcp_write_err(tcp_stream_unavailable(roc_host)),
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
    use std::net::TcpListener;

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

    #[test]
    fn read_up_to_resets_a_stale_socket_timeout() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let mut writer = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (reader, _) = listener.accept().unwrap();
        reader
            .set_read_timeout(Some(Duration::from_millis(1)))
            .unwrap();
        writer.write_all(b"x").unwrap();

        let mut reader = BufReader::new(reader);
        assert_eq!(tcp_read_up_to_impl(&mut reader, 1).unwrap(), b"x");
        assert_eq!(
            reader.get_ref().read_timeout().unwrap(),
            Some(TCP_OPERATION_TIMEOUT)
        );
    }

    #[test]
    fn name_resolution_honors_its_deadline() {
        let result = run_resolver_with_deadline(Instant::now() + Duration::from_millis(10), || {
            thread::sleep(Duration::from_millis(100));
            Ok(Vec::new())
        });

        assert_eq!(result.unwrap_err().kind(), io::ErrorKind::TimedOut);
    }
}
