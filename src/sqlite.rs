use core::ffi::c_void;
use core::mem::ManuallyDrop;
use std::ffi::{c_char, c_int, CStr, CString};
use std::sync::{Mutex, MutexGuard, OnceLock};
use std::thread::ThreadId;

use crate::abi::{
    roc_host, SqliteHostBindResult, SqliteHostBindResultPayload, SqliteHostBindResultTag,
    SqliteHostColumnValueResult, SqliteHostColumnValueResultPayload,
    SqliteHostColumnValueResultTag, SqliteHostColumnsResult, SqliteHostColumnsResultPayload,
    SqliteHostColumnsResultTag, SqliteHostPrepareResult, SqliteHostPrepareResultPayload,
    SqliteHostPrepareResultTag, SqliteHostStepResult, SqliteHostStepResultPayload,
    SqliteHostStepResultTag,
};
use crate::capability::{try_lock, CapabilityLockError};
use crate::host_resource::{
    DeallocRoute, HostResourceHeap, LookupError, ReserveError, ResourceReservation,
};
use crate::roc_platform_abi::*;

type SqliteValue = BytesOrIntegerOrNullOrRealOrString;
type SqliteValueTag = BytesOrIntegerOrNullOrRealOrStringTag;
type SqliteValuePayload = BytesOrIntegerOrNullOrRealOrStringPayload;
type SqliteError = HostSqlitePrepareErr;
type SqliteBindings = HostSqliteBindArg1;

const SQLITE_BUSY_TIMEOUT_MS: c_int = 1_000;
const MAX_OPEN_SQLITE_STATEMENTS: usize = 64;

#[derive(Default)]
struct StatementLease {
    owner: Option<ThreadId>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum StatementLeaseError {
    Busy,
    NotStarted,
}

impl StatementLease {
    fn begin(&mut self) -> Result<(), StatementLeaseError> {
        if self.owner.is_some() {
            Err(StatementLeaseError::Busy)
        } else {
            self.owner = Some(std::thread::current().id());
            Ok(())
        }
    }

    fn validate(&self) -> Result<(), StatementLeaseError> {
        match self.owner {
            Some(owner) if owner == std::thread::current().id() => Ok(()),
            Some(_) => Err(StatementLeaseError::Busy),
            None => Err(StatementLeaseError::NotStarted),
        }
    }

    fn finish(&mut self) -> Result<(), StatementLeaseError> {
        self.validate()?;
        self.owner = None;
        Ok(())
    }
}

struct SqliteStatement {
    connection: *mut libsqlite3_sys::sqlite3,
    stmt: *mut libsqlite3_sys::sqlite3_stmt,
    lease: StatementLease,
}

// The connection is opened in SQLite's serialized mode and every access to the
// statement and connection is guarded by the containing Mutex.
unsafe impl Send for SqliteStatement {}

impl Drop for SqliteStatement {
    fn drop(&mut self) {
        unsafe {
            libsqlite3_sys::sqlite3_finalize(self.stmt);
            let closed = libsqlite3_sys::sqlite3_close(self.connection);
            debug_assert_eq!(closed, libsqlite3_sys::SQLITE_OK);
        }
    }
}

enum SqlitePath {
    #[cfg(unix)]
    Unix(Vec<u8>),
    #[cfg(windows)]
    Windows(Vec<u16>),
}

type SqliteResource = Mutex<SqliteStatement>;

static SQLITE_STATEMENTS: OnceLock<HostResourceHeap<SqliteResource>> = OnceLock::new();

fn sqlite_statements() -> &'static HostResourceHeap<SqliteResource> {
    SQLITE_STATEMENTS.get_or_init(|| HostResourceHeap::new(MAX_OPEN_SQLITE_STATEMENTS))
}

fn reserve_sqlite_statement() -> Result<ResourceReservation<'static, SqliteResource>, ReserveError>
{
    sqlite_statements().reserve()
}

unsafe fn sqlite_stmt_ref(
    handle: *mut u64,
) -> Result<&'static Mutex<SqliteStatement>, LookupError> {
    unsafe { sqlite_statements().get(handle) }
}

fn release_sqlite_stmt(handle: *mut u64, roc_host: &RocHost) {
    // SAFETY: hosted arguments transfer one owned Roc reference. Final release
    // routes through the resource heap and drops the native statement.
    unsafe { decref_box(handle as RocBox, roc_host) };
}

pub(crate) fn route_resource_dealloc(ptr: *mut c_void) -> DeallocRoute {
    match SQLITE_STATEMENTS.get() {
        Some(heap) => heap.route_dealloc(ptr),
        None => DeallocRoute::NotOwned,
    }
}

pub(crate) fn contains_resource_address(ptr: *const c_void) -> bool {
    SQLITE_STATEMENTS
        .get()
        .is_some_and(|heap| heap.contains_address(ptr))
}

pub(crate) fn active_resources() -> usize {
    SQLITE_STATEMENTS.get().map_or(0, HostResourceHeap::active)
}

pub(crate) fn resource_high_water() -> usize {
    SQLITE_STATEMENTS
        .get()
        .map_or(0, HostResourceHeap::high_water)
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

fn sqlite_statement_busy(roc_host: &RocHost) -> SqliteError {
    sqlite_error(
        libsqlite3_sys::SQLITE_BUSY,
        "prepared statement is already in use by another handler",
        roc_host,
    )
}

fn sqlite_statement_unavailable(roc_host: &RocHost) -> SqliteError {
    sqlite_error(
        libsqlite3_sys::SQLITE_MISUSE,
        "prepared statement is unavailable",
        roc_host,
    )
}

fn try_lock_sqlite_statement<'a>(
    statement: &'a Mutex<SqliteStatement>,
    roc_host: &RocHost,
) -> Result<MutexGuard<'a, SqliteStatement>, SqliteError> {
    match try_lock(statement) {
        Ok(statement) => Ok(statement),
        Err(CapabilityLockError::Busy) => Err(sqlite_statement_busy(roc_host)),
        Err(CapabilityLockError::Poisoned) => Err(sqlite_statement_unavailable(roc_host)),
    }
}

fn statement_owned_by_current_handler(
    statement: &SqliteStatement,
    roc_host: &RocHost,
) -> Result<(), SqliteError> {
    match statement.lease.validate() {
        Ok(()) => Ok(()),
        Err(StatementLeaseError::Busy) => Err(sqlite_statement_busy(roc_host)),
        Err(StatementLeaseError::NotStarted) => Err(sqlite_error(
            libsqlite3_sys::SQLITE_MISUSE,
            "prepared statement must be bound before use",
            roc_host,
        )),
    }
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
                | libsqlite3_sys::SQLITE_OPEN_FULLMUTEX;
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
        let timeout_err =
            unsafe { libsqlite3_sys::sqlite3_busy_timeout(connection, SQLITE_BUSY_TIMEOUT_MS) };
        if timeout_err != libsqlite3_sys::SQLITE_OK {
            let message = sqlite_errmsg(connection, timeout_err);
            unsafe { libsqlite3_sys::sqlite3_close(connection) };
            Err((timeout_err, message))
        } else {
            Ok(connection)
        }
    }
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

fn try_sqlite_columns_ok(columns: RocList<RocStr>) -> SqliteHostColumnsResult {
    SqliteHostColumnsResult {
        payload: SqliteHostColumnsResultPayload {
            ok: ManuallyDrop::new(columns),
        },
        tag: SqliteHostColumnsResultTag::Ok,
    }
}

fn try_sqlite_columns_err(error: SqliteError) -> SqliteHostColumnsResult {
    SqliteHostColumnsResult {
        payload: SqliteHostColumnsResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostColumnsResultTag::Err,
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

    let reservation = match reserve_sqlite_statement() {
        Ok(reservation) => reservation,
        Err(ReserveError::Capacity) => {
            return try_sqlite_prepare_err(sqlite_error(
                libsqlite3_sys::SQLITE_BUSY,
                "SQLite statement capacity is exhausted",
                roc_host,
            ));
        }
    };

    let connection = match sqlite_open_native(&path) {
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
        unsafe { libsqlite3_sys::sqlite3_close(connection) };
        return try_sqlite_prepare_err(sqlite_error(err, &message, roc_host));
    }
    if stmt.is_null() {
        unsafe { libsqlite3_sys::sqlite3_close(connection) };
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
                    libsqlite3_sys::sqlite3_close(connection);
                }
                return try_sqlite_prepare_err(sqlite_error(
                    libsqlite3_sys::SQLITE_ERROR,
                    "query contained more than one SQL statement",
                    roc_host,
                ));
            }
        }
    }

    let handle = reservation.insert(Mutex::new(SqliteStatement {
        connection,
        stmt,
        lease: StatementLease::default(),
    }));
    try_sqlite_prepare_ok(handle)
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_bind(
    handle: *mut u64,
    bindings: RocList<SqliteBindings>,
) -> SqliteHostBindResult {
    let roc_host = roc_host();
    let result = {
        match unsafe { sqlite_stmt_ref(handle) } {
            Ok(statement) => match try_lock_sqlite_statement(statement, roc_host) {
                Ok(mut statement) => {
                    if statement.lease.begin().is_err() {
                        try_sqlite_unit_err(sqlite_statement_busy(roc_host))
                    } else {
                        let result = sqlite_bind_all(&mut statement, bindings.as_slice(), roc_host);
                        if !matches!(result.tag, SqliteHostBindResultTag::Ok) {
                            statement
                                .lease
                                .finish()
                                .expect("newly acquired SQLite statement lease is owned");
                        }
                        result
                    }
                }
                Err(error) => try_sqlite_unit_err(error),
            },
            Err(_) => try_sqlite_unit_err(sqlite_statement_unavailable(roc_host)),
        }
    };
    // A cloned Roc list shares its backing allocation without separately
    // incrementing each element. Recursively release the bindings only when
    // this list owns the final reference to that allocation.
    if bindings.has_one_ref() {
        for binding in bindings.allocation_items() {
            unsafe { (*binding).decref(roc_host) };
        }
    }
    unsafe { bindings.decref(roc_host) };
    release_sqlite_stmt(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_columns(handle: *mut u64) -> SqliteHostColumnsResult {
    let roc_host = roc_host();
    let result = {
        match unsafe { sqlite_stmt_ref(handle) } {
            Ok(statement) => match try_lock_sqlite_statement(statement, roc_host) {
                Ok(statement) => match statement_owned_by_current_handler(&statement, roc_host) {
                    Ok(()) => {
                        let count = unsafe { libsqlite3_sys::sqlite3_column_count(statement.stmt) }
                            .max(0) as usize;
                        // SAFETY: every allocated element is initialized below before return.
                        let list = unsafe { RocList::<RocStr>::allocate(count, roc_host) };
                        for index in 0..count {
                            let name = unsafe {
                                let raw = libsqlite3_sys::sqlite3_column_name(
                                    statement.stmt,
                                    index as c_int,
                                );
                                if raw.is_null() {
                                    RocStr::from_str("", roc_host)
                                } else {
                                    RocStr::from_str(
                                        CStr::from_ptr(raw).to_string_lossy().as_ref(),
                                        roc_host,
                                    )
                                }
                            };
                            unsafe {
                                list.elements.add(index).write(name);
                            }
                        }
                        try_sqlite_columns_ok(list)
                    }
                    Err(error) => try_sqlite_columns_err(error),
                },
                Err(error) => try_sqlite_columns_err(error),
            },
            Err(_) => try_sqlite_columns_err(sqlite_statement_unavailable(roc_host)),
        }
    };
    release_sqlite_stmt(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_column_value(
    handle: *mut u64,
    i: u64,
) -> SqliteHostColumnValueResult {
    let roc_host = roc_host();
    let result = {
        match unsafe { sqlite_stmt_ref(handle) } {
            Ok(statement) => match try_lock_sqlite_statement(statement, roc_host) {
                Ok(statement) => match statement_owned_by_current_handler(&statement, roc_host) {
                    Err(error) => try_sqlite_value_err(error),
                    Ok(()) => {
                        let count = unsafe { libsqlite3_sys::sqlite3_column_count(statement.stmt) }
                            .max(0) as u64;
                        if i >= count {
                            try_sqlite_value_err(sqlite_error(
                                libsqlite3_sys::SQLITE_ERROR,
                                &format!("column index out of range: {} of {}", i, count),
                                roc_host,
                            ))
                        } else {
                            let index = i as c_int;
                            let value = unsafe {
                                match libsqlite3_sys::sqlite3_column_type(statement.stmt, index) {
                                    libsqlite3_sys::SQLITE_INTEGER => sqlite_value_integer(
                                        libsqlite3_sys::sqlite3_column_int64(statement.stmt, index),
                                    ),
                                    libsqlite3_sys::SQLITE_FLOAT => {
                                        sqlite_value_real(libsqlite3_sys::sqlite3_column_double(
                                            statement.stmt,
                                            index,
                                        ))
                                    }
                                    libsqlite3_sys::SQLITE_TEXT => {
                                        let text = libsqlite3_sys::sqlite3_column_text(
                                            statement.stmt,
                                            index,
                                        );
                                        let len = libsqlite3_sys::sqlite3_column_bytes(
                                            statement.stmt,
                                            index,
                                        )
                                        .max(0)
                                            as usize;
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
                                        let blob = libsqlite3_sys::sqlite3_column_blob(
                                            statement.stmt,
                                            index,
                                        )
                                            as *const u8;
                                        let len = libsqlite3_sys::sqlite3_column_bytes(
                                            statement.stmt,
                                            index,
                                        )
                                        .max(0)
                                            as usize;
                                        let slice = if blob.is_null() {
                                            &[][..]
                                        } else {
                                            std::slice::from_raw_parts(blob, len)
                                        };
                                        sqlite_value_bytes(RocListWith::<u8, false>::from_slice(
                                            slice, roc_host,
                                        ))
                                    }
                                    _ => sqlite_value_null(),
                                }
                            };
                            try_sqlite_value_ok(value)
                        }
                    }
                },
                Err(error) => try_sqlite_value_err(error),
            },
            Err(_) => try_sqlite_value_err(sqlite_statement_unavailable(roc_host)),
        }
    };
    release_sqlite_stmt(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_step(handle: *mut u64) -> SqliteHostStepResult {
    let roc_host = roc_host();
    let result = {
        match unsafe { sqlite_stmt_ref(handle) } {
            Ok(statement) => match try_lock_sqlite_statement(statement, roc_host) {
                Ok(statement) => match statement_owned_by_current_handler(&statement, roc_host) {
                    Err(error) => try_sqlite_step_err(error),
                    Ok(()) => {
                        let err = unsafe { libsqlite3_sys::sqlite3_step(statement.stmt) };
                        if err == libsqlite3_sys::SQLITE_ROW {
                            try_sqlite_step_ok(true)
                        } else if err == libsqlite3_sys::SQLITE_DONE {
                            try_sqlite_step_ok(false)
                        } else {
                            try_sqlite_step_err(sqlite_err_from_stmt(&statement, err, roc_host))
                        }
                    }
                },
                Err(error) => try_sqlite_step_err(error),
            },
            Err(_) => try_sqlite_step_err(sqlite_statement_unavailable(roc_host)),
        }
    };
    release_sqlite_stmt(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_reset(handle: *mut u64) -> SqliteHostBindResult {
    let roc_host = roc_host();
    let result = {
        match unsafe { sqlite_stmt_ref(handle) } {
            Ok(statement) => match try_lock_sqlite_statement(statement, roc_host) {
                Ok(mut statement) => match statement_owned_by_current_handler(&statement, roc_host)
                {
                    Err(error) => try_sqlite_unit_err(error),
                    Ok(()) => {
                        let err = unsafe { libsqlite3_sys::sqlite3_reset(statement.stmt) };
                        statement
                            .lease
                            .finish()
                            .expect("validated SQLite statement lease is owned");
                        if err == libsqlite3_sys::SQLITE_OK {
                            try_sqlite_unit_ok()
                        } else {
                            try_sqlite_unit_err(sqlite_err_from_stmt(&statement, err, roc_host))
                        }
                    }
                },
                Err(error) => try_sqlite_unit_err(error),
            },
            Err(_) => try_sqlite_unit_err(sqlite_statement_unavailable(roc_host)),
        }
    };
    release_sqlite_stmt(handle, roc_host);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier};

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

    #[test]
    fn statement_lease_rejects_a_competing_handler_until_finish() {
        let lease = Arc::new(Mutex::new(StatementLease::default()));
        lease.lock().unwrap().begin().unwrap();

        let checked = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let worker_lease = Arc::clone(&lease);
        let worker_checked = Arc::clone(&checked);
        let worker_release = Arc::clone(&release);
        let worker = std::thread::spawn(move || {
            assert_eq!(
                worker_lease.lock().unwrap().validate(),
                Err(StatementLeaseError::Busy)
            );
            assert_eq!(
                worker_lease.lock().unwrap().begin(),
                Err(StatementLeaseError::Busy)
            );
            worker_checked.wait();
            worker_release.wait();
            worker_lease.lock().unwrap().begin().unwrap();
            worker_lease.lock().unwrap().finish().unwrap();
        });

        checked.wait();
        lease.lock().unwrap().finish().unwrap();
        release.wait();
        worker.join().unwrap();
        assert_eq!(
            lease.lock().unwrap().validate(),
            Err(StatementLeaseError::NotStarted)
        );
    }
}
