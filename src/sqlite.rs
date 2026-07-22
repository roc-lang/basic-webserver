use core::ffi::c_void;
use core::mem::ManuallyDrop;
use std::cell::RefCell;
use std::ffi::{c_char, c_int, CStr, CString};

use crate::abi::{
    roc_host, SqliteHostBindResult, SqliteHostBindResultPayload, SqliteHostBindResultTag,
    SqliteHostColumnValueResult, SqliteHostColumnValueResultPayload,
    SqliteHostColumnValueResultTag, SqliteHostPrepareResult, SqliteHostPrepareResultPayload,
    SqliteHostPrepareResultTag, SqliteHostStepResult, SqliteHostStepResultPayload,
    SqliteHostStepResultTag,
};
use crate::roc_platform_abi::*;

type SqliteValue = BytesOrIntegerOrNullOrRealOrString;
type SqliteValueTag = BytesOrIntegerOrNullOrRealOrStringTag;
type SqliteValuePayload = BytesOrIntegerOrNullOrRealOrStringPayload;
type SqliteError = HostSqlitePrepareErr;
type SqliteBindings = HostSqliteBindArg1;

const SQLITE_STMT_BOX_ALIGN: usize = core::mem::align_of::<u64>();

struct SqliteStatement {
    connection: *mut libsqlite3_sys::sqlite3,
    stmt: *mut libsqlite3_sys::sqlite3_stmt,
}

impl Drop for SqliteStatement {
    fn drop(&mut self) {
        unsafe {
            libsqlite3_sys::sqlite3_finalize(self.stmt);
        }
    }
}

thread_local! {
    // Connections are cached per database path and live until process exit.
    static SQLITE_CONNECTIONS: RefCell<Vec<(SqlitePath, *mut libsqlite3_sys::sqlite3)>> =
        const { RefCell::new(Vec::new()) };
}

#[derive(Clone, PartialEq, Eq)]
enum SqlitePath {
    #[cfg(unix)]
    Unix(Vec<u8>),
    #[cfg(windows)]
    Windows(Vec<u16>),
}

fn box_sqlite_stmt(stmt: SqliteStatement, roc_host: &RocHost) -> *mut u64 {
    let raw: *mut SqliteStatement = Box::into_raw(Box::new(stmt));
    // SAFETY: the payload is initialized immediately below as a u64 containing
    // the owned statement pointer, matching this layout.
    let boxed = unsafe {
        allocate_box(
            core::mem::size_of::<u64>(),
            SQLITE_STMT_BOX_ALIGN,
            false,
            roc_host,
        )
    };
    unsafe {
        *(boxed as *mut u64) = raw as u64;
    }
    boxed as *mut u64
}

unsafe fn sqlite_stmt_ref<'a>(handle: *mut u64) -> &'a mut SqliteStatement {
    &mut *(*handle as *mut SqliteStatement)
}

extern "C" fn drop_sqlite_stmt(data_ptr: *mut c_void, _roc_host: *mut RocHost) {
    unsafe {
        let raw = *(data_ptr as *mut u64) as *mut SqliteStatement;
        if !raw.is_null() {
            drop(Box::from_raw(raw));
        }
    }
}

fn release_sqlite_stmt(handle: *mut u64, roc_host: &RocHost) {
    // SAFETY: the handle came from `box_sqlite_stmt` with this exact layout and
    // this call consumes its owned Roc reference.
    unsafe {
        decref_box_with(
            handle as RocBox,
            SQLITE_STMT_BOX_ALIGN,
            // The boxed payload is a raw `u64` (a pointer to our SqliteStatement),
            // not a Roc-refcounted value. This must match `box_sqlite_stmt`.
            false,
            Some(drop_sqlite_stmt),
            roc_host,
        )
    };
}

// SQLITE_TRANSIENT tells SQLite to make its own copy of bound text/blob data, so
// we don't have to keep the Roc-owned bytes alive past the bind call.
fn sqlite_transient() -> Option<unsafe extern "C" fn(*mut c_void)> {
    Some(unsafe {
        core::mem::transmute::<*const c_void, unsafe extern "C" fn(*mut c_void)>(
            -1isize as *const c_void,
        )
    })
}

fn sqlite_errmsg(connection: *mut libsqlite3_sys::sqlite3, code: c_int) -> String {
    unsafe {
        let mut message = CStr::from_ptr(libsqlite3_sys::sqlite3_errstr(code))
            .to_string_lossy()
            .into_owned();
        if !connection.is_null() {
            let detailed = libsqlite3_sys::sqlite3_errmsg(connection);
            if !detailed.is_null() {
                message = CStr::from_ptr(detailed).to_string_lossy().into_owned();
            }
        }
        message
    }
}

fn sqlite_error(code: c_int, message: &str, roc_host: &RocHost) -> SqliteError {
    SqliteError {
        code: code as i64,
        message: RocStr::from_str(message, roc_host),
    }
}

fn sqlite_err_from_stmt(stmt: &SqliteStatement, code: c_int, roc_host: &RocHost) -> SqliteError {
    let message = sqlite_errmsg(stmt.connection, code);
    sqlite_error(code, &message, roc_host)
}

fn sqlite_path_from_raw(
    path: HostSqlitePrepareArg0,
    roc_host: &RocHost,
) -> Result<SqlitePath, (c_int, String)> {
    let result = if path.is_windows {
        #[cfg(windows)]
        {
            Ok(SqlitePath::Windows(path.windows_u16s.as_slice().to_vec()))
        }
        #[cfg(not(windows))]
        {
            Err((
                libsqlite3_sys::SQLITE_CANTOPEN,
                "Windows database paths are not supported on this host".to_string(),
            ))
        }
    } else {
        #[cfg(unix)]
        {
            Ok(SqlitePath::Unix(path.unix_bytes.as_slice().to_vec()))
        }
        #[cfg(not(unix))]
        {
            Err((
                libsqlite3_sys::SQLITE_CANTOPEN,
                "Unix database paths are not supported on this host".to_string(),
            ))
        }
    };

    unsafe { path.unix_bytes.decref(roc_host) };
    unsafe { path.windows_u16s.decref(roc_host) };
    result
}

#[cfg(windows)]
unsafe extern "C" {
    fn sqlite3_open16(filename: *const c_void, pp_db: *mut *mut libsqlite3_sys::sqlite3) -> c_int;
}

fn sqlite_open_native(path: &SqlitePath) -> Result<*mut libsqlite3_sys::sqlite3, (c_int, String)> {
    let mut connection: *mut libsqlite3_sys::sqlite3 = core::ptr::null_mut();

    let err = match path {
        #[cfg(unix)]
        SqlitePath::Unix(bytes) => {
            let cpath = CString::new(bytes.as_slice()).map_err(|_| {
                (
                    libsqlite3_sys::SQLITE_ERROR,
                    "database path contained an interior nul byte".to_string(),
                )
            })?;
            let flags = libsqlite3_sys::SQLITE_OPEN_CREATE
                | libsqlite3_sys::SQLITE_OPEN_READWRITE
                | libsqlite3_sys::SQLITE_OPEN_NOMUTEX;
            unsafe {
                libsqlite3_sys::sqlite3_open_v2(
                    cpath.as_ptr(),
                    &mut connection,
                    flags,
                    core::ptr::null(),
                )
            }
        }
        #[cfg(windows)]
        SqlitePath::Windows(units) => {
            if units.iter().any(|unit| *unit == 0) {
                return Err((
                    libsqlite3_sys::SQLITE_ERROR,
                    "database path contained an interior nul code unit".to_string(),
                ));
            }
            let mut terminated = units.clone();
            terminated.push(0);
            unsafe { sqlite3_open16(terminated.as_ptr() as *const c_void, &mut connection) }
        }
    };

    if err != libsqlite3_sys::SQLITE_OK {
        let message = sqlite_errmsg(connection, err);
        if !connection.is_null() {
            unsafe { libsqlite3_sys::sqlite3_close(connection) };
        }
        Err((err, message))
    } else {
        Ok(connection)
    }
}

fn sqlite_get_connection(
    path: SqlitePath,
) -> Result<*mut libsqlite3_sys::sqlite3, (c_int, String)> {
    SQLITE_CONNECTIONS.with(|cell| {
        for (conn_path, connection) in cell.borrow().iter() {
            if conn_path == &path {
                return Ok(*connection);
            }
        }

        let connection = sqlite_open_native(&path)?;
        cell.borrow_mut().push((path, connection));
        Ok(connection)
    })
}

fn sqlite_value_integer(value: i64) -> SqliteValue {
    SqliteValue {
        payload: SqliteValuePayload {
            integer: ManuallyDrop::new(value),
        },
        tag: SqliteValueTag::Integer,
    }
}

fn sqlite_value_real(value: f64) -> SqliteValue {
    SqliteValue {
        payload: SqliteValuePayload {
            real: ManuallyDrop::new(value),
        },
        tag: SqliteValueTag::Real,
    }
}

fn sqlite_value_string(value: RocStr) -> SqliteValue {
    SqliteValue {
        payload: SqliteValuePayload {
            string: ManuallyDrop::new(value),
        },
        tag: SqliteValueTag::String,
    }
}

fn sqlite_value_bytes(value: RocListWith<u8, false>) -> SqliteValue {
    SqliteValue {
        payload: SqliteValuePayload {
            bytes: ManuallyDrop::new(value),
        },
        tag: SqliteValueTag::Bytes,
    }
}

fn sqlite_value_null() -> SqliteValue {
    SqliteValue {
        payload: SqliteValuePayload { null: [] },
        tag: SqliteValueTag::Null,
    }
}

fn try_sqlite_prepare_ok(handle: *mut u64) -> SqliteHostPrepareResult {
    SqliteHostPrepareResult {
        payload: SqliteHostPrepareResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: SqliteHostPrepareResultTag::Ok,
    }
}

fn try_sqlite_prepare_err(error: SqliteError) -> SqliteHostPrepareResult {
    SqliteHostPrepareResult {
        payload: SqliteHostPrepareResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostPrepareResultTag::Err,
    }
}

fn try_sqlite_unit_ok() -> SqliteHostBindResult {
    SqliteHostBindResult {
        payload: SqliteHostBindResultPayload { ok: [] },
        tag: SqliteHostBindResultTag::Ok,
    }
}

fn try_sqlite_unit_err(error: SqliteError) -> SqliteHostBindResult {
    SqliteHostBindResult {
        payload: SqliteHostBindResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostBindResultTag::Err,
    }
}

fn try_sqlite_value_ok(value: SqliteValue) -> SqliteHostColumnValueResult {
    SqliteHostColumnValueResult {
        payload: SqliteHostColumnValueResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: SqliteHostColumnValueResultTag::Ok,
    }
}

fn try_sqlite_value_err(error: SqliteError) -> SqliteHostColumnValueResult {
    SqliteHostColumnValueResult {
        payload: SqliteHostColumnValueResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostColumnValueResultTag::Err,
    }
}

// `host_step!` marshals a Bool: true => a row is ready (SQLITE_ROW),
// false => the statement is done (SQLITE_DONE).
fn try_sqlite_step_ok(has_row: bool) -> SqliteHostStepResult {
    SqliteHostStepResult {
        payload: SqliteHostStepResultPayload {
            ok: ManuallyDrop::new(has_row),
        },
        tag: SqliteHostStepResultTag::Ok,
    }
}

fn try_sqlite_step_err(error: SqliteError) -> SqliteHostStepResult {
    SqliteHostStepResult {
        payload: SqliteHostStepResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostStepResultTag::Err,
    }
}

unsafe fn sqlite_bind_one(
    stmt: *mut libsqlite3_sys::sqlite3_stmt,
    index: c_int,
    value: &SqliteValue,
) -> c_int {
    match value.tag {
        SqliteValueTag::Integer => {
            libsqlite3_sys::sqlite3_bind_int64(stmt, index, *value.payload.integer)
        }
        SqliteValueTag::Real => {
            libsqlite3_sys::sqlite3_bind_double(stmt, index, *value.payload.real)
        }
        SqliteValueTag::String => {
            let text = value.payload.string.as_str();
            libsqlite3_sys::sqlite3_bind_text64(
                stmt,
                index,
                text.as_ptr() as *const c_char,
                text.len() as u64,
                sqlite_transient(),
                libsqlite3_sys::SQLITE_UTF8 as u8,
            )
        }
        SqliteValueTag::Bytes => {
            let bytes = value.payload.bytes.as_slice();
            libsqlite3_sys::sqlite3_bind_blob64(
                stmt,
                index,
                bytes.as_ptr() as *const c_void,
                bytes.len() as u64,
                sqlite_transient(),
            )
        }
        SqliteValueTag::Null => libsqlite3_sys::sqlite3_bind_null(stmt, index),
    }
}

fn sqlite_bind_all(
    stmt: &mut SqliteStatement,
    bindings: &[SqliteBindings],
    roc_host: &RocHost,
) -> SqliteHostBindResult {
    if let Err(error) = sqlite_validate_bindings(stmt, bindings, roc_host) {
        return try_sqlite_unit_err(error);
    }

    // Clear old bindings so callers must supply every parameter each time.
    let cleared = unsafe { libsqlite3_sys::sqlite3_clear_bindings(stmt.stmt) };
    if cleared != libsqlite3_sys::SQLITE_OK {
        return try_sqlite_unit_err(sqlite_err_from_stmt(stmt, cleared, roc_host));
    }

    for binding in bindings {
        let name = match CString::new(binding.name.as_str()) {
            Ok(name) => name,
            Err(_) => {
                return try_sqlite_unit_err(sqlite_error(
                    libsqlite3_sys::SQLITE_ERROR,
                    "binding name contained an interior nul byte",
                    roc_host,
                ));
            }
        };
        let index =
            unsafe { libsqlite3_sys::sqlite3_bind_parameter_index(stmt.stmt, name.as_ptr()) };
        if index == 0 {
            return try_sqlite_unit_err(sqlite_error(
                libsqlite3_sys::SQLITE_ERROR,
                &format!("unknown parameter: {}", binding.name.as_str()),
                roc_host,
            ));
        }
        let err = unsafe { sqlite_bind_one(stmt.stmt, index, &binding.value) };
        if err != libsqlite3_sys::SQLITE_OK {
            return try_sqlite_unit_err(sqlite_err_from_stmt(stmt, err, roc_host));
        }
    }

    try_sqlite_unit_ok()
}

fn first_duplicate_name<'a>(names: impl IntoIterator<Item = &'a str>) -> Option<&'a str> {
    let mut seen = Vec::new();
    for name in names {
        if seen.contains(&name) {
            return Some(name);
        }
        seen.push(name);
    }
    None
}

fn sqlite_validate_bindings(
    stmt: &SqliteStatement,
    bindings: &[SqliteBindings],
    roc_host: &RocHost,
) -> Result<(), SqliteError> {
    if let Some(name) = first_duplicate_name(bindings.iter().map(|binding| binding.name.as_str())) {
        return Err(sqlite_error(
            libsqlite3_sys::SQLITE_ERROR,
            &format!("duplicate binding: {}", name),
            roc_host,
        ));
    }

    for binding in bindings {
        let name = CString::new(binding.name.as_str()).map_err(|_| {
            sqlite_error(
                libsqlite3_sys::SQLITE_ERROR,
                "binding name contained an interior nul byte",
                roc_host,
            )
        })?;
        let parameter_index =
            unsafe { libsqlite3_sys::sqlite3_bind_parameter_index(stmt.stmt, name.as_ptr()) };
        if parameter_index == 0 {
            return Err(sqlite_error(
                libsqlite3_sys::SQLITE_ERROR,
                &format!("unknown parameter: {}", binding.name.as_str()),
                roc_host,
            ));
        }
    }

    let parameter_count = unsafe { libsqlite3_sys::sqlite3_bind_parameter_count(stmt.stmt) };
    for parameter_index in 1..=parameter_count {
        let parameter_name =
            unsafe { libsqlite3_sys::sqlite3_bind_parameter_name(stmt.stmt, parameter_index) };
        if parameter_name.is_null() {
            return Err(sqlite_error(
                libsqlite3_sys::SQLITE_ERROR,
                &format!(
                    "positional parameter at index {} cannot be bound by name",
                    parameter_index
                ),
                roc_host,
            ));
        }

        let parameter_name = unsafe { CStr::from_ptr(parameter_name) };
        let found = bindings
            .iter()
            .any(|binding| binding.name.as_str().as_bytes() == parameter_name.to_bytes());
        if !found {
            return Err(sqlite_error(
                libsqlite3_sys::SQLITE_ERROR,
                &format!(
                    "missing binding for parameter: {}",
                    parameter_name.to_string_lossy()
                ),
                roc_host,
            ));
        }
    }

    Ok(())
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_prepare(
    path: HostSqlitePrepareArg0,
    query: RocStr,
) -> SqliteHostPrepareResult {
    let roc_host = roc_host();
    let path = match sqlite_path_from_raw(path, roc_host) {
        Ok(path) => path,
        Err((code, message)) => {
            unsafe { query.decref(roc_host) };
            return try_sqlite_prepare_err(sqlite_error(code, &message, roc_host));
        }
    };
    let query_string = query.as_str().to_owned();
    unsafe { query.decref(roc_host) };

    let connection = match sqlite_get_connection(path) {
        Ok(connection) => connection,
        Err((code, message)) => {
            return try_sqlite_prepare_err(sqlite_error(code, &message, roc_host));
        }
    };

    let mut stmt: *mut libsqlite3_sys::sqlite3_stmt = core::ptr::null_mut();
    let mut tail: *const c_char = core::ptr::null();
    let query_start = query_string.as_ptr() as *const c_char;
    let err = unsafe {
        libsqlite3_sys::sqlite3_prepare_v2(
            connection,
            query_start,
            query_string.len() as c_int,
            &mut stmt,
            &mut tail,
        )
    };
    if err != libsqlite3_sys::SQLITE_OK {
        let message = sqlite_errmsg(connection, err);
        if !stmt.is_null() {
            unsafe {
                libsqlite3_sys::sqlite3_finalize(stmt);
            }
        }
        return try_sqlite_prepare_err(sqlite_error(err, &message, roc_host));
    }
    if stmt.is_null() {
        return try_sqlite_prepare_err(sqlite_error(
            libsqlite3_sys::SQLITE_ERROR,
            "query did not contain a SQL statement",
            roc_host,
        ));
    }
    if !tail.is_null() {
        let tail_offset = unsafe { tail.offset_from(query_start) };
        if tail_offset >= 0 {
            let tail_index = tail_offset as usize;
            if tail_index <= query_string.len()
                && query_string.as_bytes()[tail_index..]
                    .iter()
                    .any(|byte| !byte.is_ascii_whitespace())
            {
                unsafe {
                    libsqlite3_sys::sqlite3_finalize(stmt);
                }
                return try_sqlite_prepare_err(sqlite_error(
                    libsqlite3_sys::SQLITE_ERROR,
                    "query contained more than one SQL statement",
                    roc_host,
                ));
            }
        }
    }

    let handle = box_sqlite_stmt(SqliteStatement { connection, stmt }, roc_host);
    try_sqlite_prepare_ok(handle)
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_bind(
    handle: *mut u64,
    bindings: RocList<SqliteBindings>,
) -> SqliteHostBindResult {
    let roc_host = roc_host();
    let result = {
        let stmt = unsafe { sqlite_stmt_ref(handle) };
        sqlite_bind_all(stmt, bindings.as_slice(), roc_host)
    };
    for binding in bindings.as_slice() {
        unsafe { binding.decref(roc_host) };
    }
    unsafe { bindings.decref(roc_host) };
    release_sqlite_stmt(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_columns(handle: *mut u64) -> RocList<RocStr> {
    let roc_host = roc_host();
    let stmt = unsafe { sqlite_stmt_ref(handle) };
    let count = unsafe { libsqlite3_sys::sqlite3_column_count(stmt.stmt) }.max(0) as usize;
    // SAFETY: every allocated element is initialized below before return.
    let list = unsafe { RocList::<RocStr>::allocate(count, roc_host) };
    for index in 0..count {
        let name = unsafe {
            let raw = libsqlite3_sys::sqlite3_column_name(stmt.stmt, index as c_int);
            if raw.is_null() {
                RocStr::from_str("", roc_host)
            } else {
                RocStr::from_str(CStr::from_ptr(raw).to_string_lossy().as_ref(), roc_host)
            }
        };
        unsafe {
            list.elements.add(index).write(name);
        }
    }
    release_sqlite_stmt(handle, roc_host);
    list
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_column_value(
    handle: *mut u64,
    i: u64,
) -> SqliteHostColumnValueResult {
    let roc_host = roc_host();
    let result = {
        let stmt = unsafe { sqlite_stmt_ref(handle) };
        let count = unsafe { libsqlite3_sys::sqlite3_column_count(stmt.stmt) }.max(0) as u64;
        if i >= count {
            try_sqlite_value_err(sqlite_error(
                libsqlite3_sys::SQLITE_ERROR,
                &format!("column index out of range: {} of {}", i, count),
                roc_host,
            ))
        } else {
            let index = i as c_int;
            let value = unsafe {
                match libsqlite3_sys::sqlite3_column_type(stmt.stmt, index) {
                    libsqlite3_sys::SQLITE_INTEGER => {
                        sqlite_value_integer(libsqlite3_sys::sqlite3_column_int64(stmt.stmt, index))
                    }
                    libsqlite3_sys::SQLITE_FLOAT => {
                        sqlite_value_real(libsqlite3_sys::sqlite3_column_double(stmt.stmt, index))
                    }
                    libsqlite3_sys::SQLITE_TEXT => {
                        let text = libsqlite3_sys::sqlite3_column_text(stmt.stmt, index);
                        let len =
                            libsqlite3_sys::sqlite3_column_bytes(stmt.stmt, index).max(0) as usize;
                        let slice = if text.is_null() {
                            &[][..]
                        } else {
                            std::slice::from_raw_parts(text, len)
                        };
                        sqlite_value_string(RocStr::from_str(
                            String::from_utf8_lossy(slice).as_ref(),
                            roc_host,
                        ))
                    }
                    libsqlite3_sys::SQLITE_BLOB => {
                        let blob =
                            libsqlite3_sys::sqlite3_column_blob(stmt.stmt, index) as *const u8;
                        let len =
                            libsqlite3_sys::sqlite3_column_bytes(stmt.stmt, index).max(0) as usize;
                        let slice = if blob.is_null() {
                            &[][..]
                        } else {
                            std::slice::from_raw_parts(blob, len)
                        };
                        sqlite_value_bytes(RocListWith::<u8, false>::from_slice(slice, roc_host))
                    }
                    _ => sqlite_value_null(),
                }
            };
            try_sqlite_value_ok(value)
        }
    };
    release_sqlite_stmt(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_step(handle: *mut u64) -> SqliteHostStepResult {
    let roc_host = roc_host();
    let result = {
        let stmt = unsafe { sqlite_stmt_ref(handle) };
        let err = unsafe { libsqlite3_sys::sqlite3_step(stmt.stmt) };
        if err == libsqlite3_sys::SQLITE_ROW {
            try_sqlite_step_ok(true)
        } else if err == libsqlite3_sys::SQLITE_DONE {
            try_sqlite_step_ok(false)
        } else {
            try_sqlite_step_err(sqlite_err_from_stmt(stmt, err, roc_host))
        }
    };
    release_sqlite_stmt(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_reset(handle: *mut u64) -> SqliteHostBindResult {
    let roc_host = roc_host();
    let result = {
        let stmt = unsafe { sqlite_stmt_ref(handle) };
        let err = unsafe { libsqlite3_sys::sqlite3_reset(stmt.stmt) };
        if err == libsqlite3_sys::SQLITE_OK {
            try_sqlite_unit_ok()
        } else {
            try_sqlite_unit_err(sqlite_err_from_stmt(stmt, err, roc_host))
        }
    };
    release_sqlite_stmt(handle, roc_host);
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_duplicate_name_returns_first_repeated_name() {
        let names = [":one", ":two", ":one", ":three", ":two"];

        assert_eq!(first_duplicate_name(names), Some(":one"));
    }

    #[test]
    fn first_duplicate_name_returns_none_without_repeats() {
        let names = [":one", ":two", ":three"];

        assert_eq!(first_duplicate_name(names), None);
    }
}
