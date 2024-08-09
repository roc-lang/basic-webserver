use roc_fn::roc_fn;
use roc_std::{RocBox, RocList, RocResult, RocStr};
use std::alloc::Layout;
use std::cell::RefCell;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::iter::FromIterator;
use std::net::TcpStream;
use std::os::raw::c_void;
use std::rc::Rc;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::http_client;
use crate::roc_http::{self, ResponseToHost};

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
    static ROC_CRASH_MSG: RefCell<RocStr> = const { RefCell::new(RocStr::empty())};
}

#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: &RocStr, _tag_id: u32) {
    panic!("The Roc app crashed with: {}", msg.as_str());
}

#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: &RocStr, msg: &RocStr) {
    eprintln!("[{}] {}", loc, msg);
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

#[no_mangle]
pub extern "C" fn roc_fx_sendRequest(
    roc_request: &roc_http::RequestToAndFromHost,
) -> roc_http::ResponseFromHost {
    http_client::send_req(roc_request)
}

#[roc_fn(name = "envVar")]
fn env_var(roc_str: &RocStr) -> RocResult<RocStr, ()> {
    match std::env::var_os(roc_str.as_str()) {
        Some(os_str) => RocResult::ok(RocStr::from(os_str.to_string_lossy().to_string().as_str())),
        None => RocResult::err(()),
    }
}

#[roc_fn(name = "envList")]
fn env_dict() -> RocList<(RocStr, RocStr)> {
    use std::borrow::Borrow;

    let mut entries = Vec::new();

    for (key, val) in std::env::vars_os() {
        let key = RocStr::from(key.to_string_lossy().borrow());
        let value = RocStr::from(val.to_string_lossy().borrow());

        entries.push((key, value));
    }

    RocList::from_slice(entries.as_slice())
}

#[roc_fn(name = "exePath")]
fn exe_path() -> RocResult<RocList<u8>, ()> {
    match std::env::current_exe() {
        Ok(path_buf) => RocResult::ok(os_str_to_roc_path(path_buf.as_path().as_os_str())),
        Err(_) => RocResult::err(()),
    }
}

#[roc_fn(name = "setCwd")]
fn set_cwd(roc_path: &roc_std::RocList<u8>) -> RocResult<(), ()> {
    match std::env::set_current_dir(path_from_roc_path(roc_path)) {
        Ok(()) => RocResult::ok(()),
        Err(_) => RocResult::err(()),
    }
}

#[roc_fn(name = "cwd")]
fn cwd() -> roc_std::RocList<u8> {
    // TODO instead, call getcwd on UNIX and GetCurrentDirectory on Windows
    match std::env::current_dir() {
        Ok(path_buf) => os_str_to_roc_path(path_buf.into_os_string().as_os_str()),
        Err(_) => RocList::empty(), // Default to empty path
    }
}

#[roc_fn(name = "stdoutLine")]
fn stdout_line(roc_str: &RocStr) {
    println!("{}", roc_str.as_str());
}

#[roc_fn(name = "stdoutWrite")]
fn stdout_write(roc_str: &RocStr) {
    let string = roc_str.as_str();
    print!("{}", string);
}

#[roc_fn(name = "stdoutFlush")]
fn stdout_flush() {
    std::io::stdout().flush().unwrap()
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
fn stderr_flush() {
    std::io::stderr().flush().unwrap()
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
fn command_output(roc_cmd: &roc_app::InternalCommand) -> roc_app::InternalOutput {
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
                        let error = roc_app::InternalCommandErr::ExitCode(code);
                        RocResult::err(error)
                    }
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        let error = roc_app::InternalCommandErr::KilledBySignal();
                        RocResult::err(error)
                    }
                }
            };

            roc_app::InternalOutput {
                status,
                stdout: RocList::from(&output.stdout[..]),
                stderr: RocList::from(&output.stderr[..]),
            }
        }
        Err(err) => roc_app::InternalOutput {
            status: RocResult::err(roc_app::InternalCommandErr::IOError(RocStr::from(
                err.to_string().as_str(),
            ))),
            stdout: RocList::empty(),
            stderr: RocList::empty(),
        },
    }
}

#[roc_fn(name = "commandStatus")]
fn command_status(
    roc_cmd: &roc_app::InternalCommand,
) -> roc_std::RocResult<(), roc_app::InternalCommandErr> {
    use std::borrow::Borrow;

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

    match cmd.status() {
        Ok(status) => {
            if status.success() {
                RocResult::ok(())
            } else {
                match status.code() {
                    Some(code) => {
                        let error = roc_app::InternalCommandErr::ExitCode(code);
                        RocResult::err(error)
                    }
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        let error = roc_app::InternalCommandErr::KilledBySignal();
                        RocResult::err(error)
                    }
                }
            }
        }
        Err(err) => {
            let str = RocStr::from(err.to_string().borrow());
            let error = roc_app::InternalCommandErr::IOError(str);
            RocResult::err(error)
        }
    }
}

#[roc_fn(name = "tcpConnect")]
fn tcp_connect(host: &RocStr, port: u16) -> roc_app::ConnectResult {
    match TcpStream::connect((host.as_str(), port)) {
        Ok(stream) => {
            let reader = BufReader::new(stream);
            let ptr = Box::into_raw(Box::new(reader)) as u64;

            roc_app::ConnectResult::Connected(ptr)
        }
        Err(err) => roc_app::ConnectResult::Error(to_tcp_connect_err(err)),
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
) -> roc_app::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut chunk = reader.take(bytes_to_read as u64);

    match chunk.fill_buf() {
        Ok(received) => {
            let received = received.to_vec();
            reader.consume(received.len());

            let roc_list = RocList::from(&received[..]);
            roc_app::ReadResult::Read(roc_list)
        }

        Err(err) => roc_app::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[roc_fn(name = "tcpReadExactly")]
fn tcp_read_exactly(
    bytes_to_read: usize,
    stream_ptr: *mut BufReader<TcpStream>,
) -> roc_app::ReadExactlyResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut buffer = Vec::with_capacity(bytes_to_read);
    let mut chunk = reader.take(bytes_to_read as u64);

    match chunk.read_to_end(&mut buffer) {
        Ok(read) => {
            if read < bytes_to_read {
                roc_app::ReadExactlyResult::UnexpectedEOF()
            } else {
                let roc_list = RocList::from(&buffer[..]);
                roc_app::ReadExactlyResult::Read(roc_list)
            }
        }

        Err(err) => roc_app::ReadExactlyResult::Error(to_tcp_stream_err(err)),
    }
}

#[roc_fn(name = "tcpReadUntil")]
pub extern "C" fn tcp_read_until(
    byte: u8,
    stream_ptr: *mut BufReader<TcpStream>,
) -> roc_app::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut buffer = vec![];

    match reader.read_until(byte, &mut buffer) {
        Ok(_) => {
            let roc_list = RocList::from(&buffer[..]);
            roc_app::ReadResult::Read(roc_list)
        }

        Err(err) => roc_app::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[roc_fn(name = "tcpWrite")]
fn tcp_write(msg: &RocList<u8>, stream_ptr: *mut BufReader<TcpStream>) -> roc_app::WriteResult {
    let reader = unsafe { &mut *stream_ptr };
    let mut stream = reader.get_ref();

    match stream.write_all(msg.as_slice()) {
        Ok(_) => roc_app::WriteResult::Wrote(),
        Err(err) => roc_app::WriteResult::Error(to_tcp_stream_err(err)),
    }
}

fn to_tcp_connect_err(err: std::io::Error) -> roc_app::ConnectErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => roc_app::ConnectErr::PermissionDenied(),
        ErrorKind::AddrInUse => roc_app::ConnectErr::AddrInUse(),
        ErrorKind::AddrNotAvailable => roc_app::ConnectErr::AddrNotAvailable(),
        ErrorKind::ConnectionRefused => roc_app::ConnectErr::ConnectionRefused(),
        ErrorKind::Interrupted => roc_app::ConnectErr::Interrupted(),
        ErrorKind::TimedOut => roc_app::ConnectErr::TimedOut(),
        ErrorKind::Unsupported => roc_app::ConnectErr::Unsupported(),
        _ => roc_app::ConnectErr::Unrecognized(roc_app::ConnectErr_Unrecognized {
            f1: RocStr::from(kind.to_string().as_str()),
            f0: err.raw_os_error().unwrap_or_default(),
        }),
    }
}

fn to_tcp_stream_err(err: std::io::Error) -> roc_app::StreamErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => roc_app::StreamErr::PermissionDenied(),
        ErrorKind::ConnectionRefused => roc_app::StreamErr::ConnectionRefused(),
        ErrorKind::ConnectionReset => roc_app::StreamErr::ConnectionReset(),
        ErrorKind::Interrupted => roc_app::StreamErr::Interrupted(),
        ErrorKind::OutOfMemory => roc_app::StreamErr::OutOfMemory(),
        ErrorKind::BrokenPipe => roc_app::StreamErr::BrokenPipe(),
        _ => roc_app::StreamErr::Unrecognized(roc_app::ConnectErr_Unrecognized {
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
) -> roc_std::RocResult<(), roc_app::WriteErr> {
    write_slice(roc_path, roc_str.as_str().as_bytes())
}

#[roc_fn(name = "fileWriteBytes")]
fn file_write_bytes(
    roc_path: &RocList<u8>,
    roc_bytes: &RocList<u8>,
) -> roc_std::RocResult<(), roc_app::WriteErr> {
    write_slice(roc_path, roc_bytes.as_slice())
}

fn write_slice(roc_path: &RocList<u8>, bytes: &[u8]) -> roc_std::RocResult<(), roc_app::WriteErr> {
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
fn path_from_roc_path(bytes: &RocList<u8>) -> std::borrow::Cow<'_, std::path::Path> {
    use std::os::windows::ffi::OsStringExt;

    let bytes = bytes.as_slice();
    assert_eq!(bytes.len() % 2, 0);
    let characters: &[u16] =
        unsafe { std::slice::from_raw_parts(bytes.as_ptr().cast(), bytes.len() / 2) };

    let os_string = std::ffi::OsString::from_wide(characters);

    std::borrow::Cow::Owned(std::path::PathBuf::from(os_string))
}

fn to_roc_write_error(err: std::io::Error) -> roc_app::WriteErr {
    match err.kind() {
        ErrorKind::NotFound => roc_app::WriteErr::NotFound(),
        ErrorKind::AlreadyExists => roc_app::WriteErr::AlreadyExists(),
        ErrorKind::Interrupted => roc_app::WriteErr::Interrupted(),
        ErrorKind::OutOfMemory => roc_app::WriteErr::OutOfMemory(),
        ErrorKind::PermissionDenied => roc_app::WriteErr::PermissionDenied(),
        ErrorKind::TimedOut => roc_app::WriteErr::TimedOut(),
        // TODO investigate support the following IO errors may need to update API
        ErrorKind::WriteZero => roc_app::WriteErr::WriteZero(),
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
        _ => roc_app::WriteErr::Unsupported(),
    }
}

#[roc_fn(name = "fileDelete")]
fn file_delete(roc_path: &RocList<u8>) -> roc_std::RocResult<(), roc_app::ReadErr> {
    match std::fs::remove_file(path_from_roc_path(roc_path)) {
        Ok(()) => RocResult::ok(()),
        Err(err) => RocResult::err(to_roc_read_error(err)),
    }
}

#[roc_fn(name = "fileReadBytes")]
fn file_read_bytes(roc_path: &RocList<u8>) -> roc_std::RocResult<RocList<u8>, roc_app::ReadErr> {
    let mut bytes = Vec::new();

    match std::fs::File::open(path_from_roc_path(roc_path)) {
        Ok(mut file) => match file.read_to_end(&mut bytes) {
            Ok(_bytes_read) => RocResult::ok(RocList::from(bytes.as_slice())),
            Err(err) => RocResult::err(to_roc_read_error(err)),
        },
        Err(err) => RocResult::err(to_roc_read_error(err)),
    }
}

fn to_roc_read_error(err: std::io::Error) -> roc_app::ReadErr {
    match err.kind() {
        ErrorKind::Interrupted => roc_app::ReadErr::Interrupted(),
        ErrorKind::NotFound => roc_app::ReadErr::NotFound(),
        ErrorKind::OutOfMemory => roc_app::ReadErr::OutOfMemory(),
        ErrorKind::PermissionDenied => roc_app::ReadErr::PermissionDenied(),
        ErrorKind::TimedOut => roc_app::ReadErr::TimedOut(),
        // TODO investigate support the following IO errors may need to update API
        // std::io::ErrorKind:: => roc_app::ReadErr::TooManyHardlinks,
        // std::io::ErrorKind:: => roc_app::ReadErr::TooManySymlinks,
        // std::io::ErrorKind:: => roc_app::ReadErr::Unrecognized,
        // std::io::ErrorKind::StaleNetworkFileHandle <- unstable language feature
        // std::io::ErrorKind::InvalidFilename <- unstable language feature
        _ => roc_app::ReadErr::Unsupported(),
    }
}

#[roc_fn(name = "dirList")]
fn dir_list(
    roc_path: &RocList<u8>,
) -> roc_std::RocResult<RocList<RocList<u8>>, roc_app::InternalDirReadErr> {
    let path = path_from_roc_path(roc_path);
    let current_path = roc_app::UnwrappedPath::ArbitraryBytes(roc_path.clone());

    if path.is_dir() {
        let dir = match std::fs::read_dir(path) {
            Ok(dir) => dir,
            Err(err) => {
                return roc_std::RocResult::err(roc_app::InternalDirReadErr::DirReadErr(
                    current_path,
                    RocStr::from(err.to_string().as_str()),
                ))
            }
        };

        let mut entries = Vec::new();

        for entry in dir.flatten() {
            let path = entry.path();
            let str = path.as_os_str();
            entries.push(os_str_to_roc_path(str));
        }

        roc_std::RocResult::ok(RocList::from_iter(entries))
    } else {
        roc_std::RocResult::err(roc_app::InternalDirReadErr::DirReadErr(
            current_path,
            RocStr::from("Path is not a directory"),
        ))
    }
}

#[cfg(target_family = "unix")]
fn os_str_to_roc_path(os_str: &std::ffi::OsStr) -> RocList<u8> {
    use std::os::unix::ffi::OsStrExt;

    RocList::from(os_str.as_bytes())
}

#[cfg(target_family = "windows")]
fn os_str_to_roc_path(os_str: &std::ffi::OsStr) -> RocList<u8> {
    use std::os::windows::ffi::OsStrExt;

    let bytes: Vec<_> = os_str.encode_wide().flat_map(|c| c.to_be_bytes()).collect();

    RocList::from(bytes.as_slice())
}

#[repr(C, align(8))]
pub struct SQLiteError {
    code: i64,
    message: roc_std::RocStr,
}

#[repr(C, align(8))]
pub struct SQLiteBindings {
    name: roc_std::RocStr,
    value: roc_app::SQLiteValue,
}

impl sqlite::Bindable for &SQLiteBindings {
    fn bind(self, stmt: &mut sqlite::Statement) -> sqlite::Result<()> {
        match self.value.discriminant() {
            roc_app::discriminant_SQLiteValue::Bytes => {
                stmt.bind((self.name.as_str(), self.value.borrow_Bytes().as_slice()))
            }
            roc_app::discriminant_SQLiteValue::Integer => {
                stmt.bind((self.name.as_str(), self.value.borrow_Integer()))
            }
            roc_app::discriminant_SQLiteValue::Real => {
                stmt.bind((self.name.as_str(), self.value.borrow_Real()))
            }
            roc_app::discriminant_SQLiteValue::String => {
                stmt.bind((self.name.as_str(), self.value.borrow_String().as_str()))
            }
            roc_app::discriminant_SQLiteValue::Null => {
                stmt.bind((self.name.as_str(), sqlite::Value::Null))
            }
        }
    }
}

impl roc_std::RocRefcounted for SQLiteBindings {
    fn inc(&mut self) {
        self.name.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.name.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

struct SQLiteConnection {
    path: String,
    connection: Rc<sqlite::Connection>,
}

thread_local! {
    static SQLITE_CONNECTIONS : RefCell<Vec<SQLiteConnection>> = const {RefCell::new(vec![])};
}

fn get_connection(path: &str) -> Result<Rc<sqlite::Connection>, sqlite::Error> {
    SQLITE_CONNECTIONS.with(|connections| {
        for c in connections.borrow().iter() {
            if c.path == path {
                return Ok(Rc::clone(&c.connection));
            }
        }

        let connection = match sqlite::Connection::open_with_flags(
            path,
            sqlite::OpenFlags::new()
                .with_create()
                .with_read_write()
                .with_no_mutex(),
        ) {
            Ok(new_con) => new_con,
            Err(err) => {
                return Err(err);
            }
        };

        let rc_connection = Rc::new(connection);
        let new_connection = SQLiteConnection {
            path: path.to_owned(),
            connection: Rc::clone(&rc_connection),
        };

        connections.borrow_mut().push(new_connection);
        Ok(rc_connection)
    })
}

#[roc_fn(name = "sqliteExecute")]
fn sqlite_execute(
    db_path: &roc_std::RocStr,
    query: &roc_std::RocStr,
    bindings: &roc_std::RocList<SQLiteBindings>,
) -> roc_std::RocResult<RocList<RocList<roc_app::SQLiteValue>>, SQLiteError> {
    // Get the connection
    let connection = {
        match get_connection(db_path.as_str()) {
            Ok(c) => c,
            Err(err) => {
                return RocResult::err(SQLiteError {
                    code: err.code.unwrap_or_default() as i64,
                    message: RocStr::from(err.message.unwrap_or_default().as_str()),
                });
            }
        }
    };

    // Prepare the query
    let mut statement = {
        match connection.prepare(query.as_str()) {
            Ok(c) => c,
            Err(err) => {
                return RocResult::err(SQLiteError {
                    code: err.code.unwrap_or_default() as i64,
                    message: RocStr::from(err.message.unwrap_or_default().as_str()),
                });
            }
        }
    };

    // Add bindings for the query
    for binding in bindings {
        match statement.bind(binding) {
            Ok(()) => {}
            Err(err) => {
                return RocResult::err(SQLiteError {
                    code: err.code.unwrap_or_default() as i64,
                    message: RocStr::from(err.message.unwrap_or_default().as_str()),
                });
            }
        }
    }

    let mut cursor = statement.iter();
    let column_count = cursor.column_count();

    // Save space for 1000 rows without allocating
    let mut roc_values: RocList<RocList<roc_app::SQLiteValue>> = RocList::with_capacity(1000);

    while let Ok(Some(row_values)) = cursor.try_next() {
        let mut row = RocList::with_capacity(column_count);

        // For each column in the row
        for value in row_values {
            row.push(roc_sql_from_sqlite_value(value));
        }

        roc_values.push(row);
    }

    RocResult::ok(roc_values)
}

fn roc_sql_from_sqlite_value(value: sqlite::Value) -> roc_app::SQLiteValue {
    match value {
        sqlite::Value::Binary(bytes) => {
            roc_app::SQLiteValue::Bytes(RocList::from_slice(&bytes[..]))
        }
        sqlite::Value::Float(f64) => roc_app::SQLiteValue::Real(f64),
        sqlite::Value::Integer(i64) => roc_app::SQLiteValue::Integer(i64),
        sqlite::Value::String(str) => roc_app::SQLiteValue::String(RocStr::from(str.as_str())),
        sqlite::Value::Null => roc_app::SQLiteValue::Null(),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tempDir() -> RocList<u8> {
    let path_os_string_bytes = std::env::temp_dir().into_os_string().into_encoded_bytes();

    RocList::from(path_os_string_bytes.as_slice())
}

pub struct Model {
    model: RocBox<()>,
}
impl Model {
    unsafe fn init(model: RocBox<()>) -> Self {
        // Set the refcount to constant to ensure this never gets freed.
        // This also makes it thread-safe.
        let data_ptr: *mut usize = std::mem::transmute(model);
        let rc_ptr = data_ptr.offset(-1);
        let max_refcount = 0;
        *rc_ptr = max_refcount;
        Self {
            model: std::mem::transmute(data_ptr),
        }
    }
}

unsafe impl Send for Model {}
unsafe impl Sync for Model {}

pub fn call_roc_init() -> Model {
    extern "C" {
        #[link_name = "roc__forHost_1_exposed_generic"]
        fn load_init_captures(init_captures: *mut u8);

        #[link_name = "roc__forHost_1_exposed_size"]
        fn exposed_size() -> usize;

        #[link_name = "roc__forHost_0_caller"]
        fn init_caller(
            inputs: *const u8,
            init_captures: *const u8,
            model: *mut RocResult<RocBox<()>, i32>,
        );

        #[link_name = "roc__forHost_0_size"]
        fn init_captures_size() -> usize;

        #[link_name = "roc__forHost_1_size"]
        fn respond_captures_size() -> usize;

        #[link_name = "roc__forHost_0_result_size"]
        fn init_result_size() -> usize;
    }

    unsafe {
        let respond_captures_size = respond_captures_size();
        if respond_captures_size != 0 {
            panic!("This platform does not allow for the respond function to have captures, but respond has {} bytes of captures. Ensure respond is a top level function and not a lambda.", respond_captures_size);
        }
        // allocate memory for captures
        let captures_size = init_captures_size();
        let captures_layout = Layout::array::<u8>(captures_size).unwrap();
        let captures_ptr = std::alloc::alloc(captures_layout);

        // initialise roc
        debug_assert_eq!(captures_size, exposed_size());
        load_init_captures(captures_ptr);

        // save stack space for return value
        let mut result: RocResult<RocBox<()>, i32> = RocResult::err(-1);
        debug_assert_eq!(std::mem::size_of_val(&result), init_result_size());

        // call server init to get the model RocBox<()>
        init_caller(
            // This inputs pointer will never get dereferenced
            std::mem::MaybeUninit::uninit().as_ptr(),
            captures_ptr,
            &mut result,
        );

        // deallocate captures
        std::alloc::dealloc(captures_ptr, captures_layout);

        match result.into() {
            Err(exit_code) => {
                std::process::exit(exit_code);
            }
            Ok(model) => Model::init(model),
        }
    }
}

pub fn call_roc_respond(
    request: &roc_http::RequestToAndFromHost,
    model: &Model,
) -> Result<roc_http::ResponseToHost, &'static str> {
    extern "C" {
        #[link_name = "roc__forHost_1_caller"]
        fn respond_fn_caller(
            inputs: *const roc_http::RequestToAndFromHost,
            model: *const RocBox<()>,
            captures: *const u8,
            output: *mut u8,
        );

        #[link_name = "roc__forHost_1_result_size"]
        fn respond_fn_result_size() -> usize;

        #[link_name = "roc__forHost_2_caller"]
        fn respond_task_caller(
            inputs: *const u8,
            captures: *const u8,
            output: *mut roc_http::ResponseToHost,
        );

        #[link_name = "roc__forHost_2_size"]
        fn respond_task_size() -> usize;

        #[link_name = "roc__forHost_2_result_size"]
        fn respond_task_result_size() -> usize;
    }

    unsafe {
        // allocated memory for return value
        let intermediate_result_size = respond_fn_result_size();
        let intermediate_result_layout = Layout::array::<u8>(intermediate_result_size).unwrap();
        let intermediate_result_ptr = std::alloc::alloc(intermediate_result_layout);

        // call the respond function to get the Task
        debug_assert_eq!(intermediate_result_size, respond_task_size());
        respond_fn_caller(
            request,
            &model.model,
            // In init, we ensured that respond never has captures.
            std::mem::MaybeUninit::uninit().as_ptr(),
            intermediate_result_ptr,
        );

        // save stack space for return value
        let mut result = ResponseToHost {
            body: RocList::empty(),
            headers: RocList::empty(),
            status: 500,
        };
        debug_assert_eq!(std::mem::size_of_val(&result), respond_task_result_size());

        // call the Task
        respond_task_caller(
            // This inputs pointer will never get dereferenced
            std::mem::MaybeUninit::uninit().as_ptr(),
            intermediate_result_ptr,
            &mut result,
        );

        // deallocate captures
        std::alloc::dealloc(intermediate_result_ptr, intermediate_result_layout);

        Ok(result)
    }
}
