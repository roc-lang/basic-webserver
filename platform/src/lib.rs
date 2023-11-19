use roc_fn::roc_fn;
use roc_std::{RocList, RocResult, RocStr};
use std::cell::RefCell;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::net::TcpStream;
use std::os::raw::c_void;
use std::time::{SystemTime, UNIX_EPOCH};

mod http_client;
mod server;
mod tcp_glue;

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
fn tcp_connect(host: &RocStr, port: u16) -> tcp_glue::ConnectResult {
    match TcpStream::connect((host.as_str(), port)) {
        Ok(stream) => {
            let reader = BufReader::new(stream);
            let ptr = Box::into_raw(Box::new(reader)) as u64;

            tcp_glue::ConnectResult::Connected(ptr)
        }
        Err(err) => tcp_glue::ConnectResult::Error(to_tcp_connect_err(err)),
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
) -> tcp_glue::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut chunk = reader.take(bytes_to_read as u64);

    match chunk.fill_buf() {
        Ok(received) => {
            let received = received.to_vec();
            reader.consume(received.len());

            let roc_list = RocList::from(&received[..]);
            tcp_glue::ReadResult::Read(roc_list)
        }

        Err(err) => tcp_glue::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[roc_fn(name = "tcpReadExactly")]
fn tcp_read_exactly(
    bytes_to_read: usize,
    stream_ptr: *mut BufReader<TcpStream>,
) -> tcp_glue::ReadExactlyResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut buffer = Vec::with_capacity(bytes_to_read);
    let mut chunk = reader.take(bytes_to_read as u64);

    match chunk.read_to_end(&mut buffer) {
        Ok(read) => {
            if read < bytes_to_read {
                tcp_glue::ReadExactlyResult::UnexpectedEOF
            } else {
                let roc_list = RocList::from(&buffer[..]);
                tcp_glue::ReadExactlyResult::Read(roc_list)
            }
        }

        Err(err) => tcp_glue::ReadExactlyResult::Error(to_tcp_stream_err(err)),
    }
}

#[roc_fn(name = "tcpReadUntil")]
pub extern "C" fn tcp_read_until(
    byte: u8,
    stream_ptr: *mut BufReader<TcpStream>,
) -> tcp_glue::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut buffer = vec![];

    match reader.read_until(byte, &mut buffer) {
        Ok(_) => {
            let roc_list = RocList::from(&buffer[..]);
            tcp_glue::ReadResult::Read(roc_list)
        }

        Err(err) => tcp_glue::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[roc_fn(name = "tcpWrite")]
fn tcp_write(msg: &RocList<u8>, stream_ptr: *mut BufReader<TcpStream>) -> tcp_glue::WriteResult {
    let reader = unsafe { &mut *stream_ptr };
    let mut stream = reader.get_ref();

    match stream.write_all(msg.as_slice()) {
        Ok(_) => tcp_glue::WriteResult::Wrote,
        Err(err) => tcp_glue::WriteResult::Error(to_tcp_stream_err(err)),
    }
}

fn to_tcp_connect_err(err: std::io::Error) -> tcp_glue::ConnectErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => tcp_glue::ConnectErr::PermissionDenied,
        ErrorKind::AddrInUse => tcp_glue::ConnectErr::AddrInUse,
        ErrorKind::AddrNotAvailable => tcp_glue::ConnectErr::AddrNotAvailable,
        ErrorKind::ConnectionRefused => tcp_glue::ConnectErr::ConnectionRefused,
        ErrorKind::Interrupted => tcp_glue::ConnectErr::Interrupted,
        ErrorKind::TimedOut => tcp_glue::ConnectErr::TimedOut,
        ErrorKind::Unsupported => tcp_glue::ConnectErr::Unsupported,
        _ => tcp_glue::ConnectErr::Unrecognized(
            RocStr::from(kind.to_string().as_str()),
            err.raw_os_error().unwrap_or_default(),
        ),
    }
}

fn to_tcp_stream_err(err: std::io::Error) -> tcp_glue::StreamErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => tcp_glue::StreamErr::PermissionDenied,
        ErrorKind::ConnectionRefused => tcp_glue::StreamErr::ConnectionRefused,
        ErrorKind::ConnectionReset => tcp_glue::StreamErr::ConnectionReset,
        ErrorKind::Interrupted => tcp_glue::StreamErr::Interrupted,
        ErrorKind::OutOfMemory => tcp_glue::StreamErr::OutOfMemory,
        ErrorKind::BrokenPipe => tcp_glue::StreamErr::BrokenPipe,
        _ => tcp_glue::StreamErr::Unrecognized(
            RocStr::from(kind.to_string().as_str()),
            err.raw_os_error().unwrap_or_default(),
        ),
    }
}

#[roc_fn(name = "sleepMillis")]
fn sleep_millis(milliseconds: u64) {
    let duration = std::time::Duration::from_millis(milliseconds);
    std::thread::sleep(duration);
}