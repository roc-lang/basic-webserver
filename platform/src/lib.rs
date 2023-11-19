use roc_fn::roc_fn;
use roc_std::{RocList, RocResult, RocStr};
use std::cell::RefCell;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::net::TcpStream;
use std::os::raw::c_void;
use std::time::{SystemTime, UNIX_EPOCH};

mod http_client;
mod server;

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    server::start()
}

// Externs required by roc_std and by the Roc app

#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    libc::malloc(size)
}

#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    _old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    libc::realloc(c_ptr, new_size)
}

#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    libc::free(c_ptr);
}

thread_local! {
    static ROC_CRASH_MSG: RefCell<RocStr> = RefCell::new(RocStr::empty());
}

#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: RocStr) {
    panic!("The Roc app crashed with: {}", msg.as_str());
}

#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    libc::memset(dst, c, n)
}

#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_mmap(
    addr: *mut libc::c_void,
    len: libc::size_t,
    prot: libc::c_int,
    flags: libc::c_int,
    fd: libc::c_int,
    offset: libc::off_t,
) -> *mut libc::c_void {
    libc::mmap(addr, len, prot, flags, fd, offset)
}

#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_shm_open(
    name: *const libc::c_char,
    oflag: libc::c_int,
    mode: libc::mode_t,
) -> libc::c_int {
    libc::shm_open(name, oflag, mode as libc::c_uint)
}

#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_getppid() -> libc::pid_t {
    libc::getppid()
}

// #[no_mangle]
// pub unsafe extern "C" fn roc_panic(msg: &RocStr, tag_id: u32) {
//     match tag_id {
//         0 => {
//             eprintln!("Roc crashed with:\n\n\t{}\n", msg.as_str());

//             print_backtrace();
//             std::process::exit(1);
//         }
//         1 => {
//             eprintln!("The program crashed with:\n\n\t{}\n", msg.as_str());

//             print_backtrace();
//             std::process::exit(1);
//         }
//         _ => todo!(),
//     }
// }

// fn print_backtrace() {
//     eprintln!("Here is the call stack that led to the crash:\n");

//     let mut entries = Vec::new();

//     #[derive(Default)]
//     struct Entry {
//         pub fn_name: String,
//         pub filename: Option<String>,
//         pub line: Option<u32>,
//         pub col: Option<u32>,
//     }

//     backtrace::trace(|frame| {
//         backtrace::resolve_frame(frame, |symbol| {
//             if let Some(fn_name) = symbol.name() {
//                 let fn_name = fn_name.to_string();

//                 if should_show_in_backtrace(&fn_name) {
//                     let mut entry: Entry = Default::default();

//                     entry.fn_name = format_fn_name(&fn_name);

//                     if let Some(path) = symbol.filename() {
//                         entry.filename = Some(path.to_string_lossy().into_owned());
//                     };

//                     entry.line = symbol.lineno();
//                     entry.col = symbol.colno();

//                     entries.push(entry);
//                 }
//             } else {
//                 entries.push(Entry {
//                     fn_name: "???".to_string(),
//                     ..Default::default()
//                 });
//             }
//         });

//         true // keep going to the next frame
//     });

//     for entry in entries {
//         eprintln!("\t{}", entry.fn_name);

//         if let Some(filename) = entry.filename {
//             eprintln!("\t\t{filename}");
//         }
//     }

//     eprintln!("\nOptimizations can make this list inaccurate! If it looks wrong, try running without `--optimize` and with `--linker=legacy`\n");
// }

// fn should_show_in_backtrace(fn_name: &str) -> bool {
//     let is_from_rust = fn_name.contains("::");
//     let is_host_fn = fn_name.starts_with("roc_panic")
//         || fn_name.starts_with("_Effect_effect")
//         || fn_name.starts_with("_roc__")
//         || fn_name.starts_with("rust_main")
//         || fn_name == "_main";

//     !is_from_rust && !is_host_fn
// }

// fn format_fn_name(fn_name: &str) -> String {
//     // e.g. convert "_Num_sub_a0c29024d3ec6e3a16e414af99885fbb44fa6182331a70ab4ca0886f93bad5"
//     // to ["Num", "sub", "a0c29024d3ec6e3a16e414af99885fbb44fa6182331a70ab4ca0886f93bad5"]
//     let mut pieces_iter = fn_name.split("_");

//     if let (_, Some(module_name), Some(name)) =
//         (pieces_iter.next(), pieces_iter.next(), pieces_iter.next())
//     {
//         display_roc_fn(module_name, name)
//     } else {
//         "???".to_string()
//     }
// }

// fn display_roc_fn(module_name: &str, fn_name: &str) -> String {
//     let module_name = if module_name == "#UserApp" {
//         "app"
//     } else {
//         module_name
//     };

//     let fn_name = if fn_name.parse::<u64>().is_ok() {
//         "(anonymous function)"
//     } else {
//         fn_name
//     };

//     format!("\u{001B}[36m{module_name}\u{001B}[39m.{fn_name}")
// }

#[roc_fn(name = "sendRequest")]
fn send_req(roc_request: &roc_app::InternalRequest) -> roc_app::InternalResponse {
    http_client::send_req(roc_request)
}

#[roc_fn(name = "envVar")]
fn env_var(roc_str: &RocStr) -> RocResult<RocStr, ()> {
    match std::env::var_os(roc_str.as_str()) {
        Some(os_str) => RocResult::ok(RocStr::from(os_str.to_string_lossy().to_string().as_str())),
        None => RocResult::err(()),
    }
}

#[roc_fn(name = "stdoutLine")]
fn stdout_line(roc_str: &RocStr) {
    print!("{}\n", roc_str.as_str());
}

#[roc_fn(name = "stdoutWrite")]
fn stdout_write(roc_str: &RocStr) {
    let string = roc_str.as_str();
    print!("{}", string);
}

#[roc_fn(name = "stdoutFlush")]
fn stdout_flush() -> RocResult<(), glue_manual::InternalError> {
    match std::io::stdout().flush() {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(glue_manual::InternalError::IOError(RocStr::from(
            err.to_string().as_str(),
        ))),
    }
}

#[roc_fn(name = "stderrLine")]
fn stderr_line(roc_str: &RocStr) {
    let string = roc_str.as_str();
    eprintln!("{}", string);
}

#[roc_fn(name = "stderrWrite")]
fn stderr_write(roc_str: &RocStr) {
    let string = roc_str.as_str();
    eprint!("{}", string);
}

#[roc_fn(name = "stderrFlush")]
fn stderr_flush() -> RocResult<(), glue_manual::InternalError> {
    match std::io::stderr().flush() {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(glue_manual::InternalError::IOError(RocStr::from(
            err.to_string().as_str(),
        ))),
    }
}

#[roc_fn(name = "posixTime")]
fn posix_time() -> roc_std::U128 {
    // TODO in future may be able to avoid this panic by using C APIs
    let since_epoch = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time went backwards");

    roc_std::U128::from(since_epoch.as_nanos())
}

#[roc_fn(name = "commandOutput")]
fn command_output(roc_cmd: &glue_manual::InternalCommand) -> glue_manual::InternalOutput {
    let args = roc_cmd.args.into_iter().map(|arg| arg.as_str());
    let num_envs = roc_cmd.envs.len() / 2;
    let flat_envs = &roc_cmd.envs;

    // Environment vairables must be passed in key=value pairs
    assert_eq!(flat_envs.len() % 2, 0);

    let mut envs = Vec::with_capacity(num_envs);
    for chunk in flat_envs.chunks(2) {
        let key = chunk[0].as_str();
        let value = chunk[1].as_str();
        envs.push((key, value));
    }

    // Create command
    let mut cmd = std::process::Command::new(roc_cmd.program.as_str());

    // Set arguments
    cmd.args(args);

    // Clear environment variables if cmd.clearEnvs set
    // otherwise inherit environment variables if cmd.clearEnvs is not set
    if roc_cmd.clearEnvs {
        cmd.env_clear();
    };

    // Set environment variables
    cmd.envs(envs);

    match cmd.output() {
        Ok(output) => {
            // Status of the child process, successful/exit code/killed by signal
            let status = if output.status.success() {
                RocResult::ok(())
            } else {
                match output.status.code() {
                    Some(code) => {
                        let error = glue_manual::InternalCommandErr::ExitCode(code);
                        RocResult::err(error)
                    }
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        let error = glue_manual::InternalCommandErr::KilledBySignal();
                        RocResult::err(error)
                    }
                }
            };

            glue_manual::InternalOutput {
                status: status,
                stdout: roc_std::RocList::from(&output.stdout[..]),
                stderr: roc_std::RocList::from(&output.stderr[..]),
            }
        }
        Err(err) => glue_manual::InternalOutput {
            status: RocResult::err(glue_manual::InternalCommandErr::IOError(RocStr::from(
                err.to_string().as_str(),
            ))),
            stdout: roc_std::RocList::empty(),
            stderr: roc_std::RocList::empty(),
        },
    }
}

#[roc_fn(name = "tcpConnect")]
fn tcp_connect(host: &RocStr, port: u16) -> glue_manual::ConnectResult {
    match TcpStream::connect((host.as_str(), port)) {
        Ok(stream) => {
            let reader = BufReader::new(stream);
            let ptr = Box::into_raw(Box::new(reader)) as u64;

            glue_manual::ConnectResult::Connected(ptr)
        }
        Err(err) => glue_manual::ConnectResult::Error(to_tcp_connect_err(err)),
    }
}

#[roc_fn(name = "tcpClose")]
fn tcp_close(stream_ptr: *mut BufReader<TcpStream>) {
    unsafe {
        drop(Box::from_raw(stream_ptr));
    }
}

#[roc_fn(name = "tcpReadUpTo")]
fn tcp_read_up_to(
    bytes_to_read: usize,
    stream_ptr: *mut BufReader<TcpStream>,
) -> glue_manual::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut chunk = reader.take(bytes_to_read as u64);

    match chunk.fill_buf() {
        Ok(received) => {
            let received = received.to_vec();
            reader.consume(received.len());

            let roc_list = RocList::from(&received[..]);
            glue_manual::ReadResult::Read(roc_list)
        }

        Err(err) => glue_manual::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[roc_fn(name = "tcpReadExactly")]
fn tcp_read_exactly(
    bytes_to_read: usize,
    stream_ptr: *mut BufReader<TcpStream>,
) -> glue_manual::ReadExactlyResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut buffer = Vec::with_capacity(bytes_to_read);
    let mut chunk = reader.take(bytes_to_read as u64);

    match chunk.read_to_end(&mut buffer) {
        Ok(read) => {
            if read < bytes_to_read {
                glue_manual::ReadExactlyResult::UnexpectedEOF()
            } else {
                let roc_list = RocList::from(&buffer[..]);
                glue_manual::ReadExactlyResult::Read(roc_list)
            }
        }

        Err(err) => glue_manual::ReadExactlyResult::Error(to_tcp_stream_err(err)),
    }
}

#[roc_fn(name = "tcpReadUntil")]
pub extern "C" fn tcp_read_until(
    byte: u8,
    stream_ptr: *mut BufReader<TcpStream>,
) -> glue_manual::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut buffer = vec![];

    match reader.read_until(byte, &mut buffer) {
        Ok(_) => {
            let roc_list = RocList::from(&buffer[..]);
            glue_manual::ReadResult::Read(roc_list)
        }

        Err(err) => glue_manual::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[roc_fn(name = "tcpWrite")]
fn tcp_write(msg: &RocList<u8>, stream_ptr: *mut BufReader<TcpStream>) -> glue_manual::WriteResult {
    let reader = unsafe { &mut *stream_ptr };
    let mut stream = reader.get_ref();

    match stream.write_all(msg.as_slice()) {
        Ok(_) => glue_manual::WriteResult::Wrote(),
        Err(err) => glue_manual::WriteResult::Error(to_tcp_stream_err(err)),
    }
}

fn to_tcp_connect_err(err: std::io::Error) -> glue_manual::ConnectErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => glue_manual::ConnectErr::PermissionDenied(),
        ErrorKind::AddrInUse => glue_manual::ConnectErr::AddrInUse(),
        ErrorKind::AddrNotAvailable => glue_manual::ConnectErr::AddrNotAvailable(),
        ErrorKind::ConnectionRefused => glue_manual::ConnectErr::ConnectionRefused(),
        ErrorKind::Interrupted => glue_manual::ConnectErr::Interrupted(),
        ErrorKind::TimedOut => glue_manual::ConnectErr::TimedOut(),
        ErrorKind::Unsupported => glue_manual::ConnectErr::Unsupported(),
        _ => glue_manual::ConnectErr::Unrecognized(glue_manual::ConnectErr_Unrecognized {
            f1: RocStr::from(kind.to_string().as_str()),
            f0: err.raw_os_error().unwrap_or_default(),
        }),
    }
}

fn to_tcp_stream_err(err: std::io::Error) -> glue_manual::StreamErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => glue_manual::StreamErr::PermissionDenied(),
        ErrorKind::ConnectionRefused => glue_manual::StreamErr::ConnectionRefused(),
        ErrorKind::ConnectionReset => glue_manual::StreamErr::ConnectionReset(),
        ErrorKind::Interrupted => glue_manual::StreamErr::Interrupted(),
        ErrorKind::OutOfMemory => glue_manual::StreamErr::OutOfMemory(),
        ErrorKind::BrokenPipe => glue_manual::StreamErr::BrokenPipe(),
        _ => glue_manual::StreamErr::Unrecognized(glue_manual::ConnectErr_Unrecognized {
            f1: RocStr::from(kind.to_string().as_str()),
            f0: err.raw_os_error().unwrap_or_default(),
        }),
    }
}

#[roc_fn(name = "sleepMillis")]
fn sleep_millis(milliseconds: u64) {
    let duration = std::time::Duration::from_millis(milliseconds);
    std::thread::sleep(duration);
}

#[roc_fn(name = "fileWriteUtf8")]
fn file_write_utf8(
    roc_path: &RocList<u8>,
    roc_str: &RocStr,
) -> roc_std::RocResult<(), glue_manual::WriteErr> {
    write_slice(roc_path, roc_str.as_str().as_bytes())
}

#[roc_fn(name = "fileWriteBytes")]
fn file_write_bytes(
    roc_path: &RocList<u8>,
    roc_bytes: &RocList<u8>,
) -> roc_std::RocResult<(), glue_manual::WriteErr> {
    write_slice(roc_path, roc_bytes.as_slice())
}

fn write_slice(roc_path: &roc_std::RocList<u8>, bytes: &[u8]) -> roc_std::RocResult<(), glue_manual::WriteErr> {
    match std::fs::File::create(path_from_roc_path(roc_path)) {
        Ok(mut file) => match file.write_all(bytes) {
            Ok(()) => RocResult::ok(()),
            Err(err) => RocResult::err(to_roc_write_error(err)),
        },
        Err(err) => RocResult::err(to_roc_write_error(err)),
    }
}

#[cfg(target_family = "unix")]
fn path_from_roc_path(bytes: &RocList<u8>) -> std::borrow::Cow<'_, std::path::Path> {
    use std::os::unix::ffi::OsStrExt;
    let os_str = std::ffi::OsStr::from_bytes(bytes.as_slice());
    std::borrow::Cow::Borrowed(std::path::Path::new(os_str))
}

#[cfg(target_family = "windows")]
fn path_from_roc_path(bytes: &RocList<u8>) -> Cow<'_, Path> {
    use std::os::windows::ffi::OsStringExt;

    let bytes = bytes.as_slice();
    assert_eq!(bytes.len() % 2, 0);
    let characters: &[u16] =
        unsafe { std::slice::from_raw_parts(bytes.as_ptr().cast(), bytes.len() / 2) };

    let os_string = std::ffi::OsString::from_wide(characters);

    Cow::Owned(std::path::PathBuf::from(os_string))
}


fn to_roc_write_error(err: std::io::Error) -> glue_manual::WriteErr {
    match err.kind() {
        ErrorKind::NotFound => glue_manual::WriteErr::NotFound(),
        ErrorKind::AlreadyExists => glue_manual::WriteErr::AlreadyExists(),
        ErrorKind::Interrupted => glue_manual::WriteErr::Interrupted(),
        ErrorKind::OutOfMemory => glue_manual::WriteErr::OutOfMemory(),
        ErrorKind::PermissionDenied => glue_manual::WriteErr::PermissionDenied(),
        ErrorKind::TimedOut => glue_manual::WriteErr::TimedOut(),
        // TODO investigate support the following IO errors may need to update API
        ErrorKind::WriteZero => glue_manual::WriteErr::WriteZero(),
        // TODO investigate support the following IO errors
        // std::io::ErrorKind::FileTooLarge <- unstable language feature
        // std::io::ErrorKind::ExecutableFileBusy <- unstable language feature
        // std::io::ErrorKind::FilesystemQuotaExceeded <- unstable language feature
        // std::io::ErrorKind::InvalidFilename <- unstable language feature
        // std::io::ErrorKind::ResourceBusy <- unstable language feature
        // std::io::ErrorKind::ReadOnlyFilesystem <- unstable language feature
        // std::io::ErrorKind::TooManyLinks <- unstable language feature
        // std::io::ErrorKind::StaleNetworkFileHandle <- unstable language feature
        // std::io::ErrorKind::StorageFull <- unstable language feature
        _ => glue_manual::WriteErr::Unsupported(),
    }
}

#[roc_fn(name = "fileDelete")]
fn file_delete(roc_path: &RocList<u8>) -> roc_std::RocResult<(), glue_manual::ReadErr> {
    match std::fs::remove_file(path_from_roc_path(roc_path)) {
        Ok(()) => RocResult::ok(()),
        Err(err) => RocResult::err(to_roc_read_error(err)),
    }
}

#[roc_fn(name = "fileReadBytes")]
fn file_read_bytes(roc_path: &RocList<u8>) -> roc_std::RocResult<roc_std::RocList<u8>, glue_manual::ReadErr> {
    let mut bytes = Vec::new();

    match std::fs::File::open(path_from_roc_path(roc_path)) {
        Ok(mut file) => match file.read_to_end(&mut bytes) {
            Ok(_bytes_read) => RocResult::ok(RocList::from(bytes.as_slice())),
            Err(err) => RocResult::err(to_roc_read_error(err)),
        },
        Err(err) => RocResult::err(to_roc_read_error(err)),
    }
}

fn to_roc_read_error(err: std::io::Error) -> glue_manual::ReadErr {
    match err.kind() {
        ErrorKind::Interrupted => glue_manual::ReadErr::Interrupted(),
        ErrorKind::NotFound => glue_manual::ReadErr::NotFound(),
        ErrorKind::OutOfMemory => glue_manual::ReadErr::OutOfMemory(),
        ErrorKind::PermissionDenied => glue_manual::ReadErr::PermissionDenied(),
        ErrorKind::TimedOut => glue_manual::ReadErr::TimedOut(),
        // TODO investigate support the following IO errors may need to update API
        // std::io::ErrorKind:: => glue_manual::ReadErr::TooManyHardlinks,
        // std::io::ErrorKind:: => glue_manual::ReadErr::TooManySymlinks,
        // std::io::ErrorKind:: => glue_manual::ReadErr::Unrecognized,
        // std::io::ErrorKind::StaleNetworkFileHandle <- unstable language feature
        // std::io::ErrorKind::InvalidFilename <- unstable language feature
        _ => glue_manual::ReadErr::Unsupported(),
    }
}