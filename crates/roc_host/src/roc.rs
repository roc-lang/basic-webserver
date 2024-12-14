use roc_io_error::IOErr;
use roc_std::{RocBox, RocList, RocResult, RocStr};
use std::cell::RefCell;
use std::mem::ManuallyDrop;
use std::os::raw::c_void;
use std::rc::Rc;

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
) -> RocResult<roc_http::ResponseFromHost, ()> {
    RocResult::ok(http_client::send_req(roc_request))
}

#[no_mangle]
pub extern "C" fn roc_fx_envVar(roc_str: &RocStr) -> RocResult<RocStr, ()> {
    roc_env::env_var(roc_str)
}

#[no_mangle]
pub extern "C" fn roc_fx_envDict() -> RocList<(RocStr, RocStr)> {
    roc_env::env_dict()
}

#[no_mangle]
pub extern "C" fn roc_fx_exePath() -> RocResult<RocList<u8>, ()> {
    roc_env::exe_path()
}

#[no_mangle]
pub extern "C" fn roc_fx_setCwd(roc_path: &RocList<u8>) -> RocResult<(), ()> {
    roc_env::set_cwd(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_cwd() -> RocResult<RocList<u8>, ()> {
    // TODO change to roc_env when that is moved in basic-cli
    roc_file::cwd()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutLine(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutWrite(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_write(text)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrLine(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrWrite(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_write(text)
}

#[no_mangle]
pub extern "C" fn roc_fx_posixTime() -> roc_std::U128 {
    roc_env::posix_time()
}

#[no_mangle]
pub extern "C" fn roc_fx_commandStatus(
    roc_cmd: &roc_command::Command,
) -> RocResult<(), RocList<u8>> {
    roc_command::command_status(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_commandOutput(
    roc_cmd: &roc_command::Command,
) -> roc_command::CommandOutput {
    roc_command::command_output(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpConnect(host: &RocStr, port: u16) -> RocResult<RocBox<()>, RocStr> {
    roc_tcp::tcp_connect(host, port)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadUpTo(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    roc_tcp::tcp_read_up_to(stream, bytes_to_read)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadExactly(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    roc_tcp::tcp_read_exactly(stream, bytes_to_read)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadUntil(
    stream: RocBox<()>,
    byte: u8,
) -> RocResult<RocList<u8>, RocStr> {
    roc_tcp::tcp_read_until(stream, byte)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpWrite(stream: RocBox<()>, msg: &RocList<u8>) -> RocResult<(), RocStr> {
    roc_tcp::tcp_write(stream, msg)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileWriteUtf8(
    roc_path: &RocList<u8>,
    roc_str: &RocStr,
) -> RocResult<(), IOErr> {
    roc_file::file_write_utf8(roc_path, roc_str)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileWriteBytes(
    roc_path: &RocList<u8>,
    roc_bytes: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::file_write_bytes(roc_path, roc_bytes)
}

#[no_mangle]
pub extern "C" fn roc_fx_pathType(
    roc_path: &RocList<u8>,
) -> RocResult<roc_file::InternalPathType, roc_io_error::IOErr> {
    roc_file::path_type(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileReadBytes(
    roc_path: &RocList<u8>,
) -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_file::file_read_bytes(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileReader(
    roc_path: &RocList<u8>,
    size: u64,
) -> RocResult<RocBox<()>, roc_io_error::IOErr> {
    roc_file::file_reader(roc_path, size)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileReadLine(
    data: RocBox<()>,
) -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_file::file_read_line(data)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileDelete(roc_path: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::file_delete(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_dirList(
    roc_path: &RocList<u8>,
) -> RocResult<RocList<RocList<u8>>, roc_io_error::IOErr> {
    roc_file::dir_list(roc_path)
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

#[no_mangle]
pub extern "C" fn roc_fx_sqliteExecute(
    db_path: &roc_std::RocStr,
    query: &roc_std::RocStr,
    bindings: &RocList<SQLiteBindings>,
) -> RocResult<RocList<RocList<roc_app::SQLiteValue>>, SQLiteError> {
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
    roc_env::temp_dir()
}

#[derive(Debug)]
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
        #[link_name = "roc__initForHost_1_exposed"]
        fn caller(not_used: i32) -> RocResult<RocBox<()>, i32>;

        #[link_name = "roc__initForHost_1_exposed_size"]
        fn size() -> usize;
    }

    dbg!("CALLING INIT");

    let result = unsafe {
        let result = caller(0);
        assert_eq!(std::mem::size_of_val(&result), size());
        result
    };

    match result.into() {
        Err(exit_code) => {
            std::process::exit(exit_code);
        }
        Ok(model) => {
            dbg!("GOT MODEL");
            unsafe { Model::init(model) }
        }
    }
}

pub fn call_roc_respond(
    request: roc_http::RequestToAndFromHost,
    model: &Model,
) -> roc_http::ResponseToHost {
    extern "C" {
        #[link_name = "roc__respondForHost_1_exposed"]
        fn caller(
            inputs: *const ManuallyDrop<roc_http::RequestToAndFromHost>,
            model: *const RocBox<()>,
            output: *mut roc_http::ResponseToHost,
        );

        #[link_name = "roc__respondForHost_1_exposed_size"]
        fn size() -> usize;
    }

    dbg!("CALLING RESPOND");

    unsafe {
        // save stack space for return value
        let mut result = ResponseToHost {
            body: RocList::empty(),
            headers: RocList::empty(),
            status: 500,
        };
        assert_eq!(std::mem::size_of_val(&result), size());

        caller(&ManuallyDrop::new(request), &model.model, &mut result);
        assert_eq!(std::mem::size_of_val(&result), size());

        dbg!(&result);

        result
    }
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
