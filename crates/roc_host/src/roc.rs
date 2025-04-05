use roc_io_error::IOErr;
use roc_std::{RocBox, RocList, RocResult, RocStr};
use roc_sqlite;
use std::cell::RefCell;
use std::iter::FromIterator;
use std::mem::size_of_val;
use std::os::raw::c_void;
use std::time::Duration;
use tokio::runtime::Runtime;

thread_local! {
   static TOKIO_RUNTIME: Runtime = tokio::runtime::Builder::new_current_thread()
       .enable_io()
       .enable_time()
       .build()
       .unwrap();
}

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
    let heap = roc_sqlite::heap();
    if heap.in_range(c_ptr) {
        heap.dealloc(c_ptr);
        return;
    }

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

#[no_mangle]
pub extern "C" fn roc_fx_send_request(
    roc_request: &roc_http::RequestToAndFromHost,
) -> roc_http::ResponseToAndFromHost {
    TOKIO_RUNTIME.with(|rt| {
        let request = match roc_request.to_hyper_request() {
            Ok(r) => r,
            Err(err) => return err.into(),
        };

        match roc_request.has_timeout() {
            Some(time_limit) => rt
                .block_on(async {
                    tokio::time::timeout(
                        Duration::from_millis(time_limit),
                        async_send_request(request),
                    )
                    .await
                })
                .unwrap_or_else(|_err| roc_http::ResponseToAndFromHost {
                    status: 408,
                    headers: RocList::empty(),
                    body: "Request Timeout".as_bytes().into(),
                }),
            None => rt.block_on(async_send_request(request)),
        }
    })
}

async fn async_send_request(request: hyper::Request<hyper::Body>) -> roc_http::ResponseToAndFromHost {
    use hyper::Client;
    use hyper_rustls::HttpsConnectorBuilder;

    let https = HttpsConnectorBuilder::new()
        .with_native_roots()
        .https_or_http()
        .enable_http1()
        .build();

    let client: Client<_, hyper::Body> = Client::builder().build(https);
    let res = client.request(request).await;

    match res {
        Ok(response) => {
            let status = response.status();

            let headers = RocList::from_iter(response.headers().iter().map(|(name, value)| {
                roc_http::Header::new(name.as_str(), value.to_str().unwrap_or_default())
            }));

            let status = status.as_u16();

            let bytes = hyper::body::to_bytes(response.into_body()).await.unwrap();
            let body: RocList<u8> = RocList::from_iter(bytes);

            roc_http::ResponseToAndFromHost {
                body,
                status,
                headers,
            }
        }
        Err(err) => {
            if err.is_timeout() {
                roc_http::ResponseToAndFromHost {
                    status: 408,
                    headers: RocList::empty(),
                    body: "Request Timeout".as_bytes().into(),
                }
            } else if err.is_connect() || err.is_closed() {
                roc_http::ResponseToAndFromHost {
                    status: 500,
                    headers: RocList::empty(),
                    body: "Network Error".as_bytes().into(),
                }
            } else {
                roc_http::ResponseToAndFromHost {
                    status: 500,
                    headers: RocList::empty(),
                    body: err.to_string().as_bytes().into(),
                }
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_env_var(roc_str: &RocStr) -> RocResult<RocStr, ()> {
    roc_env::env_var(roc_str)
}

#[no_mangle]
pub extern "C" fn roc_fx_env_dict() -> RocList<(RocStr, RocStr)> {
    roc_env::env_dict()
}

#[no_mangle]
pub extern "C" fn roc_fx_exe_path() -> RocResult<RocList<u8>, ()> {
    roc_env::exe_path()
}

#[no_mangle]
pub extern "C" fn roc_fx_set_cwd(roc_path: &RocList<u8>) -> RocResult<(), ()> {
    roc_env::set_cwd(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_cwd() -> RocResult<RocList<u8>, ()> {
    roc_env::cwd()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdout_line(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stdout_write(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_write(text)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderr_line(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderr_write(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_write(text)
}

#[no_mangle]
pub extern "C" fn roc_fx_posix_time() -> roc_std::U128 {
    roc_env::posix_time()
}

#[no_mangle]
pub extern "C" fn roc_fx_command_status(
    roc_cmd: &roc_command::Command,
) -> RocResult<i32, roc_io_error::IOErr> {
    roc_command::command_status(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_command_output(
    roc_cmd: &roc_command::Command,
) -> roc_command::OutputFromHost {
    roc_command::command_output(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_connect(host: &RocStr, port: u16) -> RocResult<RocBox<()>, RocStr> {
    roc_http::tcp_connect(host, port)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_read_up_to(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    roc_http::tcp_read_up_to(stream, bytes_to_read)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_read_exactly(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    roc_http::tcp_read_exactly(stream, bytes_to_read)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_read_until(
    stream: RocBox<()>,
    byte: u8,
) -> RocResult<RocList<u8>, RocStr> {
    roc_http::tcp_read_until(stream, byte)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_write(stream: RocBox<()>, msg: &RocList<u8>) -> RocResult<(), RocStr> {
    roc_http::tcp_write(stream, msg)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_write_utf8(
    roc_path: &RocList<u8>,
    roc_str: &RocStr,
) -> RocResult<(), IOErr> {
    roc_file::file_write_utf8(roc_path, roc_str)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_write_bytes(
    roc_path: &RocList<u8>,
    roc_bytes: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::file_write_bytes(roc_path, roc_bytes)
}

#[no_mangle]
pub extern "C" fn roc_fx_path_type(
    roc_path: &RocList<u8>,
) -> RocResult<roc_file::InternalPathType, roc_io_error::IOErr> {
    roc_file::path_type(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_read_bytes(
    roc_path: &RocList<u8>,
) -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_file::file_read_bytes(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_reader(
    roc_path: &RocList<u8>,
    size: u64,
) -> RocResult<RocBox<()>, roc_io_error::IOErr> {
    roc_file::file_reader(roc_path, size)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_read_line(
    data: RocBox<()>,
) -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_file::file_read_line(data)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_delete(roc_path: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::file_delete(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_dir_list(
    roc_path: &RocList<u8>,
) -> RocResult<RocList<RocList<u8>>, roc_io_error::IOErr> {
    roc_file::dir_list(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_temp_dir() -> RocList<u8> {
    roc_env::temp_dir()
}

#[derive(Clone, Debug)]
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

        // Ensure all sqlite stmts that escapes init has an zero (constant) refcount.
        // This ensures it is safe to share between threads and is never freed.
        let heap = roc_sqlite::heap();
        heap.promote_all_to_constant();

        Self {
            model: std::mem::transmute::<*mut usize, roc_std::RocBox<()>>(data_ptr),
        }
    }
}

unsafe impl Send for Model {}
unsafe impl Sync for Model {}

pub fn call_roc_init() -> Model {
    extern "C" {
        #[link_name = "roc__init_for_host_1_exposed"]
        fn caller(not_used: i32) -> RocResult<RocBox<()>, i32>;

        #[link_name = "roc__init_for_host_1_exposed_size"]
        fn size() -> i64;
    }

    let result = unsafe {
        let result = caller(0);
        debug_assert_eq!(std::mem::size_of_val(&result) as i64, size());
        result
    };

    match result.into() {
        Err(exit_code) => std::process::exit(exit_code),
        Ok(model) => unsafe { Model::init(model) },
    }
}

pub fn call_roc_respond(
    request: roc_http::RequestToAndFromHost,
    model: Model,
) -> roc_http::ResponseToAndFromHost {
    extern "C" {
        #[link_name = "roc__respond_for_host_1_exposed_generic"]
        fn caller(
            output: *mut roc_http::ResponseToAndFromHost,
            request_ptr: *const roc_http::RequestToAndFromHost,
            boxed_model: RocBox<()>,
        );

        #[link_name = "roc__respond_for_host_1_exposed_size"]
        fn size() -> i64;
    }

    unsafe {
        // save stack space for return value
        let mut result = roc_http::ResponseToAndFromHost {
            body: RocList::empty(),
            headers: RocList::empty(),
            status: 500,
        };

        debug_assert_eq!(std::mem::size_of_val(&result) as i64, size());

        caller(&mut result, &request, model.model.clone());

        std::mem::forget(request);

        result
    }
}

//  TODO use these functions to create seamless slices and avoid unnecessary allocations

#[allow(dead_code)]
const REFCOUNT_CONSTANT: u64 = 0;
#[allow(dead_code)]
const SEAMLESS_SLICE_BIT: usize = isize::MIN as usize;

// This is only safe to call if the underlying data is guaranteed to be alive for the lifetime of the roc list.
#[allow(dead_code)]
pub unsafe fn to_const_seamless_roc_list(data: &[u8]) -> RocList<u8> {
    let const_refcount_allocation =
        (&REFCOUNT_CONSTANT as *const u64) as usize + size_of_val(&REFCOUNT_CONSTANT);
    let const_seamless_slice = (const_refcount_allocation >> 1) | SEAMLESS_SLICE_BIT;

    RocList::from_raw_parts(data.as_ptr() as *mut u8, data.len(), const_seamless_slice)
}
// This is only safe to call if the underlying data is guaranteed to be alive for the lifetime of the roc list.
#[allow(dead_code)]
pub unsafe fn to_const_seamless_roc_str(data: &str) -> RocStr {
    // TODO: consider still generating small strings here if the str is small enough.
    let const_refcount_allocation =
        (&REFCOUNT_CONSTANT as *const u64) as usize + size_of_val(&REFCOUNT_CONSTANT);
    let const_seamless_slice = (const_refcount_allocation >> 1) | SEAMLESS_SLICE_BIT;

    RocStr::from_raw_parts(data.as_ptr() as *mut u8, data.len(), const_seamless_slice)
}

#[no_mangle]
pub extern "C" fn roc_fx_getLocale() -> RocResult<RocStr, ()> {
    roc_env::get_locale()
}

#[no_mangle]
pub extern "C" fn roc_fx_getLocales() -> RocList<RocStr> {
    roc_env::get_locales()
}

#[no_mangle]
pub extern "C" fn roc_fx_currentArchOS() -> roc_env::ReturnArchOS {
    roc_env::current_arch_os()
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_bind(
    stmt: RocBox<()>,
    bindings: &RocList<roc_sqlite::SqliteBindings>,
) -> RocResult<(), roc_sqlite::SqliteError> {
    roc_sqlite::bind(stmt, bindings)
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_prepare(
    db_path: &roc_std::RocStr,
    query: &roc_std::RocStr,
) -> roc_std::RocResult<RocBox<()>, roc_sqlite::SqliteError> {
    roc_sqlite::prepare(db_path, query)
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_columns(stmt: RocBox<()>) -> RocList<RocStr> {
    roc_sqlite::columns(stmt)
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_column_value(
    stmt: RocBox<()>,
    i: u64,
) -> RocResult<roc_sqlite::SqliteValue, roc_sqlite::SqliteError> {
    roc_sqlite::column_value(stmt, i)
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_step(
    stmt: RocBox<()>,
) -> RocResult<roc_sqlite::SqliteState, roc_sqlite::SqliteError> {
    roc_sqlite::step(stmt)
}

/// Resets a prepared statement back to its initial state, ready to be re-executed.
#[no_mangle]
pub extern "C" fn roc_fx_sqlite_reset(stmt: RocBox<()>) -> RocResult<(), roc_sqlite::SqliteError> {
    roc_sqlite::reset(stmt)
}

#[no_mangle]
pub extern "C" fn roc_fx_sleep_millis(milliseconds: u64) {
    let duration = Duration::from_millis(milliseconds);
    std::thread::sleep(duration);
}
