use core::ffi::c_void;
use core::mem::ManuallyDrop;
use std::collections::VecDeque;
use std::ffi::{c_char, c_int, CStr, CString};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

use crate::abi::{
    roc_host, SqliteHostBeginResult, SqliteHostBeginResultPayload, SqliteHostBeginResultTag,
    SqliteHostColumnsResult, SqliteHostColumnsResultPayload, SqliteHostColumnsResultTag,
    SqliteHostNextRow, SqliteHostNextRowResult, SqliteHostNextRowResultPayload,
    SqliteHostNextRowResultTag, SqliteHostNextRowState, SqliteHostNextRowStatePayload,
    SqliteHostNextRowStateTag, SqliteHostOpenResult, SqliteHostOpenResultPayload,
    SqliteHostOpenResultTag, SqliteHostPrepareResult, SqliteHostPrepareResultPayload,
    SqliteHostPrepareResultTag, SqliteHostStartResult, SqliteHostStartResultPayload,
    SqliteHostStartResultTag, SqliteHostTxnFinishResult, SqliteHostTxnFinishResultPayload,
    SqliteHostTxnFinishResultTag,
};
use crate::host_resource::{
    DeallocRoute, HostResourceHeap, LookupError, ReserveError, ResourceReservation,
};
use crate::roc_platform_abi::*;

type SqliteValue = BytesOrIntegerOrNullOrRealOrString;
type SqliteValueTag = BytesOrIntegerOrNullOrRealOrStringTag;
type SqliteValuePayload = BytesOrIntegerOrNullOrRealOrStringPayload;
type SqliteError = HostSqliteOpenErr;
type SqliteBindings = HostSqliteStartArg1;

const MAX_DATABASES: usize = 16;
const MAX_LOGICAL_STATEMENTS: usize = 256;
const MAX_EXECUTIONS: usize = 128;
const MAX_TRANSACTIONS: usize = 64;
const MAX_CONNECTIONS_PER_DATABASE: usize = 64;
const MAX_CACHED_STATEMENTS_PER_CONNECTION: usize = 256;
const MAX_TIMEOUT_MS: u64 = 10 * 60 * 1_000;
const MAX_SQL_BYTES: usize = 1024 * 1024;

// These private codes are translated into dedicated public Roc error tags.
const HOST_POOL_SATURATED: c_int = -1;
const HOST_QUERY_TIMED_OUT: c_int = -2;
const HOST_TRANSACTION_FINISHED: c_int = -3;
const HOST_RESOURCE_SATURATED: c_int = -4;
const HOST_CONCURRENT_TRANSACTION_USE: c_int = -5;

#[derive(Clone)]
enum SqlitePath {
    #[cfg(unix)]
    Unix(Vec<u8>),
    #[cfg(windows)]
    Windows(Vec<u16>),
}

#[derive(Clone, Copy)]
struct PoolConfig {
    acquire_timeout: Duration,
    busy_timeout_ms: c_int,
    statement_cache_capacity: usize,
    journal_mode: JournalMode,
    synchronous: Synchronous,
}

#[derive(Clone, Copy)]
enum JournalMode {
    Delete,
    Wal,
}

#[derive(Clone, Copy)]
enum Synchronous {
    Full,
    Normal,
}

struct NativeStatement {
    raw: *mut libsqlite3_sys::sqlite3_stmt,
    query: Arc<str>,
}

unsafe impl Send for NativeStatement {}

impl Drop for NativeStatement {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe {
                libsqlite3_sys::sqlite3_finalize(self.raw);
            }
        }
    }
}

struct Connection {
    raw: *mut libsqlite3_sys::sqlite3,
    statements: VecDeque<NativeStatement>,
    statement_cache_capacity: usize,
}

unsafe impl Send for Connection {}

impl Connection {
    fn open(path: &SqlitePath, config: PoolConfig) -> Result<Self, (c_int, String)> {
        let raw = sqlite_open_native(path)?;
        let mut connection = Self {
            raw,
            statements: VecDeque::with_capacity(config.statement_cache_capacity),
            statement_cache_capacity: config.statement_cache_capacity,
        };

        let timeout_error =
            unsafe { libsqlite3_sys::sqlite3_busy_timeout(raw, config.busy_timeout_ms) };
        if timeout_error != libsqlite3_sys::SQLITE_OK {
            return Err((timeout_error, sqlite_errmsg(raw, timeout_error)));
        }

        // These settings are applied to every connection, not just the fixture
        // creator or the first connection in the pool.
        connection.execute_control("PRAGMA foreign_keys = ON;")?;
        let (journal_sql, expected_journal) = match config.journal_mode {
            JournalMode::Delete => ("PRAGMA journal_mode = DELETE;", "delete"),
            JournalMode::Wal => ("PRAGMA journal_mode = WAL;", "wal"),
        };
        connection.execute_control(journal_sql)?;
        let actual_journal = connection.query_control_text("PRAGMA journal_mode;")?;
        if !actual_journal.eq_ignore_ascii_case(expected_journal) {
            return Err((
                libsqlite3_sys::SQLITE_ERROR,
                format!(
                    "SQLite did not activate requested journal mode {expected_journal}; \
                     active mode is {actual_journal}"
                ),
            ));
        }
        connection.execute_control(match config.synchronous {
            Synchronous::Full => "PRAGMA synchronous = FULL;",
            Synchronous::Normal => "PRAGMA synchronous = NORMAL;",
        })?;
        Ok(connection)
    }

    fn execute_control(&mut self, sql: &str) -> Result<(), (c_int, String)> {
        let sql = CString::new(sql).expect("static SQLite control SQL has no nul byte");
        let code = unsafe {
            libsqlite3_sys::sqlite3_exec(
                self.raw,
                sql.as_ptr(),
                None,
                core::ptr::null_mut(),
                core::ptr::null_mut(),
            )
        };
        if code == libsqlite3_sys::SQLITE_OK {
            Ok(())
        } else {
            Err((code, sqlite_errmsg(self.raw, code)))
        }
    }

    fn query_control_text(&mut self, sql: &str) -> Result<String, (c_int, String)> {
        let statement = prepare_native_statement(self.raw, Arc::from(sql))?;
        let code = unsafe { libsqlite3_sys::sqlite3_step(statement.raw) };
        if code != libsqlite3_sys::SQLITE_ROW {
            return Err((code, sqlite_errmsg(self.raw, code)));
        }
        let text = unsafe { libsqlite3_sys::sqlite3_column_text(statement.raw, 0) };
        let len = unsafe { libsqlite3_sys::sqlite3_column_bytes(statement.raw, 0) }.max(0) as usize;
        if text.is_null() {
            Ok(String::new())
        } else {
            Ok(
                String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(text, len) })
                    .into_owned(),
            )
        }
    }

    fn take_statement(&mut self, query: Arc<str>) -> Result<NativeStatement, (c_int, String)> {
        if let Some(index) = self
            .statements
            .iter()
            .position(|statement| statement.query.as_ref() == query.as_ref())
        {
            return Ok(self
                .statements
                .remove(index)
                .expect("cached SQLite statement index exists"));
        }
        prepare_native_statement(self.raw, query)
    }

    fn return_statement(&mut self, statement: NativeStatement) {
        let reset = unsafe { libsqlite3_sys::sqlite3_reset(statement.raw) };
        let cleared = unsafe { libsqlite3_sys::sqlite3_clear_bindings(statement.raw) };
        if reset != libsqlite3_sys::SQLITE_OK || cleared != libsqlite3_sys::SQLITE_OK {
            return;
        }
        if self.statement_cache_capacity == 0 {
            return;
        }
        self.statements.push_front(statement);
        while self.statements.len() > self.statement_cache_capacity {
            self.statements.pop_back();
        }
    }
}

impl Drop for Connection {
    fn drop(&mut self) {
        // Prepared statements must be finalized before their connection.
        self.statements.clear();
        if !self.raw.is_null() {
            let result = unsafe { libsqlite3_sys::sqlite3_close(self.raw) };
            debug_assert_eq!(result, libsqlite3_sys::SQLITE_OK);
        }
    }
}

struct PoolState {
    available: Vec<Connection>,
    leased: usize,
    high_water: usize,
}

struct DatabasePool {
    config: PoolConfig,
    path: SqlitePath,
    size: usize,
    state: Mutex<PoolState>,
    available: Condvar,
}

impl DatabasePool {
    fn open(
        path: &SqlitePath,
        size: usize,
        config: PoolConfig,
    ) -> Result<Arc<Self>, (c_int, String)> {
        let mut connections = Vec::with_capacity(size);
        for _ in 0..size {
            connections.push(Connection::open(path, config)?);
        }
        Ok(Arc::new(Self {
            config,
            path: path.clone(),
            size,
            state: Mutex::new(PoolState {
                available: connections,
                leased: 0,
                high_water: 0,
            }),
            available: Condvar::new(),
        }))
    }

    fn acquire(&self) -> Result<Connection, PoolAcquireError> {
        let deadline = Instant::now() + self.config.acquire_timeout;
        let mut state = lock_unpoisoned(&self.state);
        loop {
            if let Some(connection) = state.available.pop() {
                state.leased += 1;
                state.high_water = state.high_water.max(state.leased);
                return Ok(connection);
            }

            let now = Instant::now();
            if now >= deadline {
                return Err(PoolAcquireError::Saturated);
            }
            let remaining = deadline.saturating_duration_since(now);
            let (next_state, wait) = self
                .available
                .wait_timeout(state, remaining)
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            state = next_state;
            if wait.timed_out() && state.available.is_empty() {
                return Err(PoolAcquireError::Saturated);
            }
        }
    }

    fn release(&self, connection: Connection) {
        let mut state = lock_unpoisoned(&self.state);
        debug_assert!(state.leased > 0);
        state.leased = state.leased.saturating_sub(1);
        state.available.push(connection);
        drop(state);
        self.available.notify_one();
    }

    fn discard(&self, connection: Connection) {
        drop(connection);
        let replacement = Connection::open(&self.path, self.config).ok();
        let mut state = lock_unpoisoned(&self.state);
        debug_assert!(state.leased > 0);
        state.leased = state.leased.saturating_sub(1);
        if let Some(connection) = replacement {
            state.available.push(connection);
        }
        drop(state);
        self.available.notify_one();
    }
}

impl Drop for DatabasePool {
    fn drop(&mut self) {
        let state = self
            .state
            .get_mut()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        debug_assert_eq!(state.leased, 0);
        debug_assert!(state.available.len() <= self.size);
    }
}

#[derive(Debug)]
enum PoolAcquireError {
    Saturated,
}

#[derive(Clone)]
enum StatementSource {
    Pool(Arc<DatabasePool>),
    Transaction(Arc<TransactionShared>),
}

struct LogicalStatement {
    source: StatementSource,
    query: Arc<str>,
    columns: Arc<[String]>,
}

struct TransactionState {
    connection: Option<Connection>,
    active_execution: Option<u64>,
    next_execution: u64,
    finished: bool,
}

struct TransactionShared {
    pool: Arc<DatabasePool>,
    state: Mutex<TransactionState>,
}

impl Drop for TransactionShared {
    fn drop(&mut self) {
        let state = self
            .state
            .get_mut()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some(mut connection) = state.connection.take() {
            if !state.finished && connection.execute_control("ROLLBACK;").is_err() {
                self.pool.discard(connection);
                return;
            }
            self.pool.release(connection);
        }
    }
}

struct DeadlineState {
    deadline: Instant,
    timed_out: AtomicBool,
}

unsafe extern "C" fn sqlite_progress_deadline(context: *mut c_void) -> c_int {
    let deadline = unsafe { &*(context as *const DeadlineState) };
    if Instant::now() >= deadline.deadline {
        deadline.timed_out.store(true, Ordering::Relaxed);
        1
    } else {
        0
    }
}

enum ExecutionOwner {
    Pool {
        pool: Arc<DatabasePool>,
        connection: Option<Connection>,
    },
    Transaction {
        transaction: Arc<TransactionShared>,
        execution_id: u64,
        connection: *mut libsqlite3_sys::sqlite3,
    },
}

struct Execution {
    owner: ExecutionOwner,
    statement: Option<NativeStatement>,
    deadline: Box<DeadlineState>,
}

unsafe impl Send for Execution {}

impl Execution {
    fn connection(&self) -> *mut libsqlite3_sys::sqlite3 {
        match &self.owner {
            ExecutionOwner::Pool { connection, .. } => {
                connection
                    .as_ref()
                    .expect("live pooled execution owns a connection")
                    .raw
            }
            ExecutionOwner::Transaction { connection, .. } => *connection,
        }
    }

    fn statement(&self) -> *mut libsqlite3_sys::sqlite3_stmt {
        self.statement
            .as_ref()
            .expect("live SQLite execution owns a statement")
            .raw
    }

    fn timed_out(&self) -> bool {
        self.deadline.timed_out.load(Ordering::Relaxed)
    }
}

impl Drop for Execution {
    fn drop(&mut self) {
        let connection_raw = self.connection();
        unsafe {
            libsqlite3_sys::sqlite3_progress_handler(
                connection_raw,
                0,
                None,
                core::ptr::null_mut(),
            );
        }
        let statement = self.statement.take();

        match &mut self.owner {
            ExecutionOwner::Pool { pool, connection } => {
                if let Some(mut connection) = connection.take() {
                    if let Some(statement) = statement {
                        connection.return_statement(statement);
                    }
                    pool.release(connection);
                }
            }
            ExecutionOwner::Transaction {
                transaction,
                execution_id,
                ..
            } => {
                let mut state = lock_unpoisoned(&transaction.state);
                if state.active_execution == Some(*execution_id) {
                    if let (Some(connection), Some(statement)) =
                        (state.connection.as_mut(), statement)
                    {
                        connection.return_statement(statement);
                    }
                    state.active_execution = None;
                }
            }
        }
    }
}

type DatabaseResource = Arc<DatabasePool>;
type StatementResource = LogicalStatement;
type ExecutionResource = Mutex<Execution>;
type TransactionResource = Arc<TransactionShared>;

static SQLITE_DATABASES: OnceLock<HostResourceHeap<DatabaseResource>> = OnceLock::new();
static SQLITE_STATEMENTS: OnceLock<HostResourceHeap<StatementResource>> = OnceLock::new();
static SQLITE_EXECUTIONS: OnceLock<HostResourceHeap<ExecutionResource>> = OnceLock::new();
static SQLITE_TRANSACTIONS: OnceLock<HostResourceHeap<TransactionResource>> = OnceLock::new();

fn sqlite_databases() -> &'static HostResourceHeap<DatabaseResource> {
    SQLITE_DATABASES.get_or_init(|| HostResourceHeap::new(MAX_DATABASES))
}

fn sqlite_statements() -> &'static HostResourceHeap<StatementResource> {
    SQLITE_STATEMENTS.get_or_init(|| HostResourceHeap::new(MAX_LOGICAL_STATEMENTS))
}

fn sqlite_executions() -> &'static HostResourceHeap<ExecutionResource> {
    SQLITE_EXECUTIONS.get_or_init(|| HostResourceHeap::new(MAX_EXECUTIONS))
}

fn sqlite_transactions() -> &'static HostResourceHeap<TransactionResource> {
    SQLITE_TRANSACTIONS.get_or_init(|| HostResourceHeap::new(MAX_TRANSACTIONS))
}

unsafe fn sqlite_db_ref(handle: *mut u64) -> Result<&'static DatabaseResource, LookupError> {
    unsafe { sqlite_databases().get(handle) }
}

unsafe fn sqlite_stmt_ref(handle: *mut u64) -> Result<&'static StatementResource, LookupError> {
    unsafe { sqlite_statements().get(handle) }
}

unsafe fn sqlite_exec_ref(handle: *mut u64) -> Result<&'static ExecutionResource, LookupError> {
    unsafe { sqlite_executions().get(handle) }
}

unsafe fn sqlite_txn_ref(handle: *mut u64) -> Result<&'static TransactionResource, LookupError> {
    unsafe { sqlite_transactions().get(handle) }
}

fn release_resource_handle(handle: *mut u64, roc_host: &RocHost) {
    unsafe { decref_box(handle as RocBox, roc_host) };
}

pub(crate) fn route_resource_dealloc(ptr: *mut c_void) -> DeallocRoute {
    for route in [
        SQLITE_DATABASES.get().map(|heap| heap.route_dealloc(ptr)),
        SQLITE_STATEMENTS.get().map(|heap| heap.route_dealloc(ptr)),
        SQLITE_EXECUTIONS.get().map(|heap| heap.route_dealloc(ptr)),
        SQLITE_TRANSACTIONS
            .get()
            .map(|heap| heap.route_dealloc(ptr)),
    ]
    .into_iter()
    .flatten()
    {
        if route != DeallocRoute::NotOwned {
            return route;
        }
    }
    DeallocRoute::NotOwned
}

pub(crate) fn contains_resource_address(ptr: *const c_void) -> bool {
    SQLITE_DATABASES
        .get()
        .is_some_and(|heap| heap.contains_address(ptr))
        || SQLITE_STATEMENTS
            .get()
            .is_some_and(|heap| heap.contains_address(ptr))
        || SQLITE_EXECUTIONS
            .get()
            .is_some_and(|heap| heap.contains_address(ptr))
        || SQLITE_TRANSACTIONS
            .get()
            .is_some_and(|heap| heap.contains_address(ptr))
}

pub(crate) fn active_resources() -> usize {
    SQLITE_DATABASES.get().map_or(0, HostResourceHeap::active)
        + SQLITE_STATEMENTS.get().map_or(0, HostResourceHeap::active)
        + SQLITE_EXECUTIONS.get().map_or(0, HostResourceHeap::active)
        + SQLITE_TRANSACTIONS
            .get()
            .map_or(0, HostResourceHeap::active)
}

pub(crate) fn resource_high_water() -> usize {
    SQLITE_DATABASES
        .get()
        .map_or(0, HostResourceHeap::high_water)
        + SQLITE_STATEMENTS
            .get()
            .map_or(0, HostResourceHeap::high_water)
        + SQLITE_EXECUTIONS
            .get()
            .map_or(0, HostResourceHeap::high_water)
        + SQLITE_TRANSACTIONS
            .get()
            .map_or(0, HostResourceHeap::high_water)
}

fn lock_unpoisoned<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

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

fn sqlite_error_from_connection(
    connection: *mut libsqlite3_sys::sqlite3,
    code: c_int,
    roc_host: &RocHost,
) -> SqliteError {
    sqlite_error(code, &sqlite_errmsg(connection, code), roc_host)
}

fn sqlite_resource_unavailable(kind: &str, roc_host: &RocHost) -> SqliteError {
    sqlite_error(
        libsqlite3_sys::SQLITE_MISUSE,
        &format!("SQLite {kind} is unavailable"),
        roc_host,
    )
}

fn sqlite_path_from_raw(
    path: HostSqliteOpenArg0,
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
                "received a Windows SQLite path on a non-Windows host".to_owned(),
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
                "received a Unix SQLite path on a non-Unix host".to_owned(),
            ))
        }
    };
    unsafe { path.decref(roc_host) };
    result
}

#[cfg(windows)]
unsafe extern "C" {
    fn sqlite3_open16(filename: *const c_void, pp_db: *mut *mut libsqlite3_sys::sqlite3) -> c_int;
}

fn sqlite_open_native(path: &SqlitePath) -> Result<*mut libsqlite3_sys::sqlite3, (c_int, String)> {
    let mut connection = core::ptr::null_mut();
    let code = match path {
        #[cfg(unix)]
        SqlitePath::Unix(path) => {
            let path = CString::new(path.as_slice()).map_err(|_| {
                (
                    libsqlite3_sys::SQLITE_CANTOPEN,
                    "SQLite path contained an interior nul byte".to_owned(),
                )
            })?;
            let flags = libsqlite3_sys::SQLITE_OPEN_CREATE
                | libsqlite3_sys::SQLITE_OPEN_READWRITE
                | libsqlite3_sys::SQLITE_OPEN_NOMUTEX;
            unsafe {
                libsqlite3_sys::sqlite3_open_v2(
                    path.as_ptr(),
                    &mut connection,
                    flags,
                    core::ptr::null(),
                )
            }
        }
        #[cfg(windows)]
        SqlitePath::Windows(path) => {
            let mut terminated = path.clone();
            terminated.push(0);
            unsafe { sqlite3_open16(terminated.as_ptr() as *const c_void, &mut connection) }
        }
    };
    if code == libsqlite3_sys::SQLITE_OK {
        Ok(connection)
    } else {
        let message = sqlite_errmsg(connection, code);
        if !connection.is_null() {
            unsafe {
                libsqlite3_sys::sqlite3_close(connection);
            }
        }
        Err((code, message))
    }
}

fn prepare_native_statement(
    connection: *mut libsqlite3_sys::sqlite3,
    query: Arc<str>,
) -> Result<NativeStatement, (c_int, String)> {
    if query.len() > MAX_SQL_BYTES {
        return Err((
            libsqlite3_sys::SQLITE_TOOBIG,
            format!("SQLite SQL text exceeds the {MAX_SQL_BYTES}-byte limit"),
        ));
    }
    let mut statement = core::ptr::null_mut();
    let mut tail = core::ptr::null();
    let query_start = query.as_ptr() as *const c_char;
    let code = unsafe {
        libsqlite3_sys::sqlite3_prepare_v2(
            connection,
            query_start,
            query.len() as c_int,
            &mut statement,
            &mut tail,
        )
    };
    if code != libsqlite3_sys::SQLITE_OK {
        if !statement.is_null() {
            unsafe {
                libsqlite3_sys::sqlite3_finalize(statement);
            }
        }
        return Err((code, sqlite_errmsg(connection, code)));
    }
    if statement.is_null() {
        return Err((
            libsqlite3_sys::SQLITE_ERROR,
            "query did not contain a SQL statement".to_owned(),
        ));
    }
    if !tail.is_null() {
        let tail_offset = unsafe { tail.offset_from(query_start) };
        if tail_offset >= 0 {
            let tail_index = tail_offset as usize;
            if tail_index <= query.len()
                && query.as_bytes()[tail_index..]
                    .iter()
                    .any(|byte| !byte.is_ascii_whitespace())
            {
                unsafe {
                    libsqlite3_sys::sqlite3_finalize(statement);
                }
                return Err((
                    libsqlite3_sys::SQLITE_ERROR,
                    "query contained more than one SQL statement".to_owned(),
                ));
            }
        }
    }
    Ok(NativeStatement {
        raw: statement,
        query,
    })
}

fn statement_columns(statement: *mut libsqlite3_sys::sqlite3_stmt) -> Vec<String> {
    let count = unsafe { libsqlite3_sys::sqlite3_column_count(statement) }.max(0) as usize;
    (0..count)
        .map(|index| {
            let name = unsafe { libsqlite3_sys::sqlite3_column_name(statement, index as c_int) };
            if name.is_null() {
                String::new()
            } else {
                unsafe { CStr::from_ptr(name) }
                    .to_string_lossy()
                    .into_owned()
            }
        })
        .collect()
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

unsafe fn sqlite_column_materialized_size(
    stmt: *mut libsqlite3_sys::sqlite3_stmt,
    index: c_int,
) -> u64 {
    let value_storage = core::mem::size_of::<SqliteValue>() as u64;
    let variable_storage = match unsafe { libsqlite3_sys::sqlite3_column_type(stmt, index) } {
        libsqlite3_sys::SQLITE_TEXT => unsafe {
            let text = libsqlite3_sys::sqlite3_column_text(stmt, index);
            let len = libsqlite3_sys::sqlite3_column_bytes(stmt, index).max(0) as usize;
            if text.is_null() {
                0
            } else {
                let bytes = std::slice::from_raw_parts(text, len);
                if std::str::from_utf8(bytes).is_ok() {
                    len as u64
                } else {
                    (len as u64).saturating_mul(3)
                }
            }
        },
        libsqlite3_sys::SQLITE_BLOB => unsafe {
            libsqlite3_sys::sqlite3_column_bytes(stmt, index).max(0) as u64
        },
        _ => 0,
    };
    value_storage.saturating_add(variable_storage)
}

unsafe fn materialize_sqlite_column(
    stmt: *mut libsqlite3_sys::sqlite3_stmt,
    index: c_int,
    roc_host: &RocHost,
) -> SqliteValue {
    match unsafe { libsqlite3_sys::sqlite3_column_type(stmt, index) } {
        libsqlite3_sys::SQLITE_INTEGER => {
            sqlite_value_integer(unsafe { libsqlite3_sys::sqlite3_column_int64(stmt, index) })
        }
        libsqlite3_sys::SQLITE_FLOAT => {
            sqlite_value_real(unsafe { libsqlite3_sys::sqlite3_column_double(stmt, index) })
        }
        libsqlite3_sys::SQLITE_TEXT => {
            let text = unsafe { libsqlite3_sys::sqlite3_column_text(stmt, index) };
            let len = unsafe { libsqlite3_sys::sqlite3_column_bytes(stmt, index) }.max(0) as usize;
            let slice = if text.is_null() {
                &[][..]
            } else {
                unsafe { std::slice::from_raw_parts(text, len) }
            };
            sqlite_value_string(RocStr::from_str(
                String::from_utf8_lossy(slice).as_ref(),
                roc_host,
            ))
        }
        libsqlite3_sys::SQLITE_BLOB => {
            let blob = unsafe { libsqlite3_sys::sqlite3_column_blob(stmt, index) } as *const u8;
            let len = unsafe { libsqlite3_sys::sqlite3_column_bytes(stmt, index) }.max(0) as usize;
            let slice = if blob.is_null() {
                &[][..]
            } else {
                unsafe { std::slice::from_raw_parts(blob, len) }
            };
            sqlite_value_bytes(RocListWith::<u8, false>::from_slice(slice, roc_host))
        }
        _ => sqlite_value_null(),
    }
}

fn try_sqlite_open_ok(handle: *mut u64) -> SqliteHostOpenResult {
    SqliteHostOpenResult {
        payload: SqliteHostOpenResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: SqliteHostOpenResultTag::Ok,
    }
}

fn try_sqlite_open_err(error: SqliteError) -> SqliteHostOpenResult {
    SqliteHostOpenResult {
        payload: SqliteHostOpenResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostOpenResultTag::Err,
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

fn try_sqlite_start_ok(handle: *mut u64) -> SqliteHostStartResult {
    SqliteHostStartResult {
        payload: SqliteHostStartResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: SqliteHostStartResultTag::Ok,
    }
}

fn try_sqlite_start_err(error: SqliteError) -> SqliteHostStartResult {
    SqliteHostStartResult {
        payload: SqliteHostStartResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostStartResultTag::Err,
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

fn try_sqlite_next_ok(state: SqliteHostNextRowState) -> SqliteHostNextRowResult {
    SqliteHostNextRowResult {
        payload: SqliteHostNextRowResultPayload {
            ok: ManuallyDrop::new(state),
        },
        tag: SqliteHostNextRowResultTag::Ok,
    }
}

fn try_sqlite_next_err(error: SqliteError) -> SqliteHostNextRowResult {
    SqliteHostNextRowResult {
        payload: SqliteHostNextRowResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostNextRowResultTag::Err,
    }
}

fn try_sqlite_begin_ok(handle: *mut u64) -> SqliteHostBeginResult {
    SqliteHostBeginResult {
        payload: SqliteHostBeginResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: SqliteHostBeginResultTag::Ok,
    }
}

fn try_sqlite_begin_err(error: SqliteError) -> SqliteHostBeginResult {
    SqliteHostBeginResult {
        payload: SqliteHostBeginResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostBeginResultTag::Err,
    }
}

fn try_sqlite_finish_ok() -> SqliteHostTxnFinishResult {
    SqliteHostTxnFinishResult {
        payload: SqliteHostTxnFinishResultPayload { ok: [] },
        tag: SqliteHostTxnFinishResultTag::Ok,
    }
}

fn try_sqlite_finish_err(error: SqliteError) -> SqliteHostTxnFinishResult {
    SqliteHostTxnFinishResult {
        payload: SqliteHostTxnFinishResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: SqliteHostTxnFinishResultTag::Err,
    }
}

fn sqlite_next_done() -> SqliteHostNextRowResult {
    try_sqlite_next_ok(SqliteHostNextRowState {
        payload: SqliteHostNextRowStatePayload { done: [] },
        tag: SqliteHostNextRowStateTag::Done,
    })
}

fn sqlite_next_result_too_large() -> SqliteHostNextRowResult {
    try_sqlite_next_ok(SqliteHostNextRowState {
        payload: SqliteHostNextRowStatePayload {
            result_too_large: [],
        },
        tag: SqliteHostNextRowStateTag::ResultTooLarge,
    })
}

fn sqlite_next_row_limit_exceeded() -> SqliteHostNextRowResult {
    try_sqlite_next_ok(SqliteHostNextRowState {
        payload: SqliteHostNextRowStatePayload {
            row_limit_exceeded: [],
        },
        tag: SqliteHostNextRowStateTag::RowLimitExceeded,
    })
}

fn sqlite_next_row(values: RocList<SqliteValue>, bytes: u64) -> SqliteHostNextRowResult {
    try_sqlite_next_ok(SqliteHostNextRowState {
        payload: SqliteHostNextRowStatePayload {
            row: ManuallyDrop::new(SqliteHostNextRow { bytes, values }),
        },
        tag: SqliteHostNextRowStateTag::Row,
    })
}

unsafe fn sqlite_bind_one(
    stmt: *mut libsqlite3_sys::sqlite3_stmt,
    index: c_int,
    value: &SqliteValue,
) -> c_int {
    match value.tag {
        SqliteValueTag::Integer => unsafe {
            libsqlite3_sys::sqlite3_bind_int64(stmt, index, *value.payload.integer)
        },
        SqliteValueTag::Real => unsafe {
            libsqlite3_sys::sqlite3_bind_double(stmt, index, *value.payload.real)
        },
        SqliteValueTag::String => unsafe {
            let text = value.payload.string.as_str();
            libsqlite3_sys::sqlite3_bind_text64(
                stmt,
                index,
                text.as_ptr() as *const c_char,
                text.len() as u64,
                sqlite_transient(),
                libsqlite3_sys::SQLITE_UTF8 as u8,
            )
        },
        SqliteValueTag::Bytes => unsafe {
            let bytes = value.payload.bytes.as_slice();
            libsqlite3_sys::sqlite3_bind_blob64(
                stmt,
                index,
                bytes.as_ptr() as *const c_void,
                bytes.len() as u64,
                sqlite_transient(),
            )
        },
        SqliteValueTag::Null => unsafe { libsqlite3_sys::sqlite3_bind_null(stmt, index) },
    }
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
    statement: *mut libsqlite3_sys::sqlite3_stmt,
    bindings: &[SqliteBindings],
    roc_host: &RocHost,
) -> Result<(), SqliteError> {
    if let Some(name) = first_duplicate_name(bindings.iter().map(|binding| binding.name.as_str())) {
        return Err(sqlite_error(
            libsqlite3_sys::SQLITE_ERROR,
            &format!("duplicate binding: {name}"),
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
            unsafe { libsqlite3_sys::sqlite3_bind_parameter_index(statement, name.as_ptr()) };
        if parameter_index == 0 {
            return Err(sqlite_error(
                libsqlite3_sys::SQLITE_ERROR,
                &format!("unknown parameter: {}", binding.name.as_str()),
                roc_host,
            ));
        }
    }

    let parameter_count = unsafe { libsqlite3_sys::sqlite3_bind_parameter_count(statement) };
    for parameter_index in 1..=parameter_count {
        let parameter_name =
            unsafe { libsqlite3_sys::sqlite3_bind_parameter_name(statement, parameter_index) };
        if parameter_name.is_null() {
            return Err(sqlite_error(
                libsqlite3_sys::SQLITE_ERROR,
                &format!("positional parameter at index {parameter_index} cannot be bound by name"),
                roc_host,
            ));
        }
        let parameter_name = unsafe { CStr::from_ptr(parameter_name) };
        if !bindings
            .iter()
            .any(|binding| binding.name.as_str().as_bytes() == parameter_name.to_bytes())
        {
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

fn sqlite_bind_all(
    connection: *mut libsqlite3_sys::sqlite3,
    statement: *mut libsqlite3_sys::sqlite3_stmt,
    bindings: &[SqliteBindings],
    roc_host: &RocHost,
) -> Result<(), SqliteError> {
    sqlite_validate_bindings(statement, bindings, roc_host)?;
    let cleared = unsafe { libsqlite3_sys::sqlite3_clear_bindings(statement) };
    if cleared != libsqlite3_sys::SQLITE_OK {
        return Err(sqlite_error_from_connection(connection, cleared, roc_host));
    }
    for binding in bindings {
        let name = CString::new(binding.name.as_str()).map_err(|_| {
            sqlite_error(
                libsqlite3_sys::SQLITE_ERROR,
                "binding name contained an interior nul byte",
                roc_host,
            )
        })?;
        let index =
            unsafe { libsqlite3_sys::sqlite3_bind_parameter_index(statement, name.as_ptr()) };
        let code = unsafe { sqlite_bind_one(statement, index, &binding.value) };
        if code != libsqlite3_sys::SQLITE_OK {
            return Err(sqlite_error_from_connection(connection, code, roc_host));
        }
    }
    Ok(())
}

fn release_bindings(bindings: &RocList<SqliteBindings>, roc_host: &RocHost) {
    if bindings.has_one_ref() {
        for binding in bindings.allocation_items() {
            unsafe {
                (*binding).decref(roc_host);
            }
        }
    }
    unsafe {
        bindings.decref(roc_host);
    }
}

fn validate_pool_config(
    max_connections: u64,
    acquire_timeout_ms: u64,
    busy_timeout_ms: u64,
    max_cached_statements: u64,
    journal_mode: i64,
    synchronous: i64,
) -> Result<(usize, PoolConfig), &'static str> {
    if !(1..=MAX_CONNECTIONS_PER_DATABASE as u64).contains(&max_connections) {
        return Err("max_connections must be between 1 and 64");
    }
    if acquire_timeout_ms == 0 || acquire_timeout_ms > MAX_TIMEOUT_MS {
        return Err("acquire_timeout_ms must be between 1 and 600000");
    }
    if busy_timeout_ms > MAX_TIMEOUT_MS || busy_timeout_ms > c_int::MAX as u64 {
        return Err("busy_timeout_ms must be at most 600000");
    }
    if max_cached_statements > MAX_CACHED_STATEMENTS_PER_CONNECTION as u64 {
        return Err("max_cached_statements_per_connection must be at most 256");
    }
    let journal_mode = match journal_mode {
        0 => JournalMode::Delete,
        1 => JournalMode::Wal,
        _ => return Err("unknown SQLite journal mode"),
    };
    let synchronous = match synchronous {
        0 => Synchronous::Full,
        1 => Synchronous::Normal,
        _ => return Err("unknown SQLite synchronous mode"),
    };
    Ok((
        max_connections as usize,
        PoolConfig {
            acquire_timeout: Duration::from_millis(acquire_timeout_ms),
            busy_timeout_ms: busy_timeout_ms as c_int,
            statement_cache_capacity: max_cached_statements as usize,
            journal_mode,
            synchronous,
        },
    ))
}

fn reserve_or_error<'a, T>(
    heap: &'a HostResourceHeap<T>,
    kind: &str,
    roc_host: &RocHost,
) -> Result<ResourceReservation<'a, T>, SqliteError> {
    heap.reserve().map_err(|ReserveError::Capacity| {
        sqlite_error(
            HOST_RESOURCE_SATURATED,
            &format!("SQLite {kind} capacity is exhausted"),
            roc_host,
        )
    })
}

fn prepare_columns(
    source: &StatementSource,
    query: Arc<str>,
) -> Result<Vec<String>, (c_int, String)> {
    match source {
        StatementSource::Pool(pool) => {
            let mut connection = pool.acquire().map_err(|PoolAcquireError::Saturated| {
                (
                    HOST_POOL_SATURATED,
                    "SQLite connection pool is saturated".to_owned(),
                )
            })?;
            let statement = match connection.take_statement(query) {
                Ok(statement) => statement,
                Err(error) => {
                    pool.release(connection);
                    return Err(error);
                }
            };
            let columns = statement_columns(statement.raw);
            connection.return_statement(statement);
            pool.release(connection);
            Ok(columns)
        }
        StatementSource::Transaction(transaction) => {
            let mut state = lock_unpoisoned(&transaction.state);
            if state.finished || state.connection.is_none() {
                return Err((
                    HOST_TRANSACTION_FINISHED,
                    "SQLite transaction has finished".to_owned(),
                ));
            }
            if state.active_execution.is_some() {
                return Err((
                    HOST_CONCURRENT_TRANSACTION_USE,
                    "SQLite transaction already has an active execution".to_owned(),
                ));
            }
            let statement = state
                .connection
                .as_mut()
                .expect("unfinished transaction owns a connection")
                .take_statement(query)?;
            let columns = statement_columns(statement.raw);
            state
                .connection
                .as_mut()
                .expect("unfinished transaction owns a connection")
                .return_statement(statement);
            Ok(columns)
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_open(
    path: HostSqliteOpenArg0,
    max_connections: u64,
    acquire_timeout_ms: u64,
    busy_timeout_ms: u64,
    max_cached_statements: u64,
    journal_mode: i64,
    synchronous: i64,
) -> SqliteHostOpenResult {
    let roc_host = roc_host();
    let path = match sqlite_path_from_raw(path, roc_host) {
        Ok(path) => path,
        Err((code, message)) => {
            return try_sqlite_open_err(sqlite_error(code, &message, roc_host));
        }
    };
    let (size, config) = match validate_pool_config(
        max_connections,
        acquire_timeout_ms,
        busy_timeout_ms,
        max_cached_statements,
        journal_mode,
        synchronous,
    ) {
        Ok(config) => config,
        Err(message) => {
            return try_sqlite_open_err(sqlite_error(
                libsqlite3_sys::SQLITE_MISUSE,
                message,
                roc_host,
            ));
        }
    };
    let reservation = match reserve_or_error(sqlite_databases(), "database", roc_host) {
        Ok(reservation) => reservation,
        Err(error) => return try_sqlite_open_err(error),
    };
    match DatabasePool::open(&path, size, config) {
        Ok(pool) => try_sqlite_open_ok(reservation.insert(pool)),
        Err((code, message)) => try_sqlite_open_err(sqlite_error(code, &message, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_prepare(
    database_handle: *mut u64,
    query: RocStr,
) -> SqliteHostPrepareResult {
    let roc_host = roc_host();
    let query_string: Arc<str> = Arc::from(query.as_str());
    unsafe {
        query.decref(roc_host);
    }
    hosted_sqlite_prepare_inner(database_handle, query_string, roc_host)
}

fn hosted_sqlite_prepare_inner(
    database_handle: *mut u64,
    query: Arc<str>,
    roc_host: &RocHost,
) -> SqliteHostPrepareResult {
    let source = match unsafe { sqlite_db_ref(database_handle) } {
        Ok(pool) => StatementSource::Pool(Arc::clone(pool)),
        Err(_) => {
            release_resource_handle(database_handle, roc_host);
            return try_sqlite_prepare_err(sqlite_resource_unavailable("database", roc_host));
        }
    };
    release_resource_handle(database_handle, roc_host);
    prepare_logical_statement(source, query, roc_host)
}

fn prepare_logical_statement(
    source: StatementSource,
    query: Arc<str>,
    roc_host: &RocHost,
) -> SqliteHostPrepareResult {
    let reservation = match reserve_or_error(sqlite_statements(), "statement", roc_host) {
        Ok(reservation) => reservation,
        Err(error) => return try_sqlite_prepare_err(error),
    };
    let columns = match prepare_columns(&source, Arc::clone(&query)) {
        Ok(columns) => columns,
        Err((code, message)) => {
            return try_sqlite_prepare_err(sqlite_error(code, &message, roc_host));
        }
    };
    try_sqlite_prepare_ok(reservation.insert(LogicalStatement {
        source,
        query,
        columns: columns.into(),
    }))
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_columns(handle: *mut u64) -> SqliteHostColumnsResult {
    let roc_host = roc_host();
    let columns = match unsafe { sqlite_stmt_ref(handle) } {
        Ok(statement) => Arc::clone(&statement.columns),
        Err(_) => {
            release_resource_handle(handle, roc_host);
            return try_sqlite_columns_err(sqlite_resource_unavailable("statement", roc_host));
        }
    };
    release_resource_handle(handle, roc_host);
    let roc_columns: Vec<_> = columns
        .iter()
        .map(|name| RocStr::from_str(name, roc_host))
        .collect();
    try_sqlite_columns_ok(unsafe { RocList::from_slice(&roc_columns, roc_host) })
}

fn configure_deadline(
    connection: *mut libsqlite3_sys::sqlite3,
    timeout_ms: u64,
) -> Result<Box<DeadlineState>, &'static str> {
    if timeout_ms == 0 || timeout_ms > MAX_TIMEOUT_MS {
        return Err("query timeout_ms must be between 1 and 600000");
    }
    let deadline = Box::new(DeadlineState {
        deadline: Instant::now() + Duration::from_millis(timeout_ms),
        timed_out: AtomicBool::new(false),
    });
    unsafe {
        libsqlite3_sys::sqlite3_progress_handler(
            connection,
            1_000,
            Some(sqlite_progress_deadline),
            (&*deadline as *const DeadlineState).cast_mut().cast(),
        );
    }
    Ok(deadline)
}

fn start_pooled_execution(
    pool: Arc<DatabasePool>,
    query: Arc<str>,
    bindings: &[SqliteBindings],
    timeout_ms: u64,
    roc_host: &RocHost,
) -> Result<Execution, SqliteError> {
    let mut connection = pool.acquire().map_err(|PoolAcquireError::Saturated| {
        sqlite_error(
            HOST_POOL_SATURATED,
            "SQLite connection pool is saturated",
            roc_host,
        )
    })?;
    let statement = match connection.take_statement(query) {
        Ok(statement) => statement,
        Err((code, message)) => {
            pool.release(connection);
            return Err(sqlite_error(code, &message, roc_host));
        }
    };
    if let Err(error) = sqlite_bind_all(connection.raw, statement.raw, bindings, roc_host) {
        connection.return_statement(statement);
        pool.release(connection);
        return Err(error);
    }
    let deadline = match configure_deadline(connection.raw, timeout_ms) {
        Ok(deadline) => deadline,
        Err(message) => {
            connection.return_statement(statement);
            pool.release(connection);
            return Err(sqlite_error(
                libsqlite3_sys::SQLITE_MISUSE,
                message,
                roc_host,
            ));
        }
    };
    Ok(Execution {
        owner: ExecutionOwner::Pool {
            pool,
            connection: Some(connection),
        },
        statement: Some(statement),
        deadline,
    })
}

fn start_transaction_execution(
    transaction: Arc<TransactionShared>,
    query: Arc<str>,
    bindings: &[SqliteBindings],
    timeout_ms: u64,
    roc_host: &RocHost,
) -> Result<Execution, SqliteError> {
    let mut state = lock_unpoisoned(&transaction.state);
    if state.finished || state.connection.is_none() {
        return Err(sqlite_error(
            HOST_TRANSACTION_FINISHED,
            "SQLite transaction has finished",
            roc_host,
        ));
    }
    if state.active_execution.is_some() {
        return Err(sqlite_error(
            HOST_CONCURRENT_TRANSACTION_USE,
            "SQLite transaction already has an active execution",
            roc_host,
        ));
    }
    let connection = state
        .connection
        .as_mut()
        .expect("unfinished transaction owns a connection");
    let statement = connection
        .take_statement(query)
        .map_err(|(code, message)| sqlite_error(code, &message, roc_host))?;
    if let Err(error) = sqlite_bind_all(connection.raw, statement.raw, bindings, roc_host) {
        connection.return_statement(statement);
        return Err(error);
    }
    let connection_raw = connection.raw;
    let deadline = match configure_deadline(connection_raw, timeout_ms) {
        Ok(deadline) => deadline,
        Err(message) => {
            connection.return_statement(statement);
            return Err(sqlite_error(
                libsqlite3_sys::SQLITE_MISUSE,
                message,
                roc_host,
            ));
        }
    };
    let execution_id = state.next_execution;
    state.next_execution = state.next_execution.wrapping_add(1).max(1);
    state.active_execution = Some(execution_id);
    drop(state);
    Ok(Execution {
        owner: ExecutionOwner::Transaction {
            transaction,
            execution_id,
            connection: connection_raw,
        },
        statement: Some(statement),
        deadline,
    })
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_start(
    statement_handle: *mut u64,
    bindings: RocList<SqliteBindings>,
    timeout_ms: u64,
) -> SqliteHostStartResult {
    let roc_host = roc_host();
    let (source, query) = match unsafe { sqlite_stmt_ref(statement_handle) } {
        Ok(statement) => (statement.source.clone(), Arc::clone(&statement.query)),
        Err(_) => {
            release_resource_handle(statement_handle, roc_host);
            release_bindings(&bindings, roc_host);
            return try_sqlite_start_err(sqlite_resource_unavailable("statement", roc_host));
        }
    };
    release_resource_handle(statement_handle, roc_host);

    let reservation = match reserve_or_error(sqlite_executions(), "execution", roc_host) {
        Ok(reservation) => reservation,
        Err(error) => {
            release_bindings(&bindings, roc_host);
            return try_sqlite_start_err(error);
        }
    };
    let execution = match source {
        StatementSource::Pool(pool) => {
            start_pooled_execution(pool, query, bindings.as_slice(), timeout_ms, roc_host)
        }
        StatementSource::Transaction(transaction) => start_transaction_execution(
            transaction,
            query,
            bindings.as_slice(),
            timeout_ms,
            roc_host,
        ),
    };
    release_bindings(&bindings, roc_host);
    match execution {
        Ok(execution) => try_sqlite_start_ok(reservation.insert(Mutex::new(execution))),
        Err(error) => try_sqlite_start_err(error),
    }
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_next_row(
    handle: *mut u64,
    max_bytes: u64,
    allow_row: bool,
) -> SqliteHostNextRowResult {
    let roc_host = roc_host();
    let result = match unsafe { sqlite_exec_ref(handle) } {
        Ok(execution) => {
            let execution = lock_unpoisoned(execution);
            let step = unsafe { libsqlite3_sys::sqlite3_step(execution.statement()) };
            if step == libsqlite3_sys::SQLITE_DONE {
                sqlite_next_done()
            } else if step != libsqlite3_sys::SQLITE_ROW {
                if step == libsqlite3_sys::SQLITE_INTERRUPT && execution.timed_out() {
                    try_sqlite_next_err(sqlite_error(
                        HOST_QUERY_TIMED_OUT,
                        "SQLite query deadline exceeded",
                        roc_host,
                    ))
                } else {
                    try_sqlite_next_err(sqlite_error_from_connection(
                        execution.connection(),
                        step,
                        roc_host,
                    ))
                }
            } else if !allow_row {
                sqlite_next_row_limit_exceeded()
            } else {
                let statement = execution.statement();
                let count =
                    unsafe { libsqlite3_sys::sqlite3_column_count(statement) }.max(0) as usize;
                let mut bytes = 0_u64;
                for index in 0..count {
                    bytes = bytes.saturating_add(unsafe {
                        sqlite_column_materialized_size(statement, index as c_int)
                    });
                }
                if bytes > max_bytes {
                    sqlite_next_result_too_large()
                } else {
                    let mut values = Vec::with_capacity(count);
                    for index in 0..count {
                        values.push(unsafe {
                            materialize_sqlite_column(statement, index as c_int, roc_host)
                        });
                    }
                    sqlite_next_row(unsafe { RocList::from_slice(&values, roc_host) }, bytes)
                }
            }
        }
        Err(_) => try_sqlite_next_err(sqlite_resource_unavailable("execution", roc_host)),
    };
    release_resource_handle(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_begin(
    database_handle: *mut u64,
    mode: i64,
) -> SqliteHostBeginResult {
    let roc_host = roc_host();
    let pool = match unsafe { sqlite_db_ref(database_handle) } {
        Ok(pool) => Arc::clone(pool),
        Err(_) => {
            release_resource_handle(database_handle, roc_host);
            return try_sqlite_begin_err(sqlite_resource_unavailable("database", roc_host));
        }
    };
    release_resource_handle(database_handle, roc_host);
    let reservation = match reserve_or_error(sqlite_transactions(), "transaction", roc_host) {
        Ok(reservation) => reservation,
        Err(error) => return try_sqlite_begin_err(error),
    };
    let mut connection = match pool.acquire() {
        Ok(connection) => connection,
        Err(PoolAcquireError::Saturated) => {
            return try_sqlite_begin_err(sqlite_error(
                HOST_POOL_SATURATED,
                "SQLite connection pool is saturated",
                roc_host,
            ));
        }
    };
    let begin_sql = match mode {
        0 => "BEGIN DEFERRED;",
        1 => "BEGIN IMMEDIATE;",
        2 => "BEGIN EXCLUSIVE;",
        _ => {
            pool.release(connection);
            return try_sqlite_begin_err(sqlite_error(
                libsqlite3_sys::SQLITE_MISUSE,
                "unknown SQLite transaction mode",
                roc_host,
            ));
        }
    };
    if let Err((code, message)) = connection.execute_control(begin_sql) {
        pool.release(connection);
        return try_sqlite_begin_err(sqlite_error(code, &message, roc_host));
    }
    let transaction = Arc::new(TransactionShared {
        pool,
        state: Mutex::new(TransactionState {
            connection: Some(connection),
            active_execution: None,
            next_execution: 1,
            finished: false,
        }),
    });
    try_sqlite_begin_ok(reservation.insert(transaction))
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_txn_prepare(
    transaction_handle: *mut u64,
    query: RocStr,
) -> SqliteHostPrepareResult {
    let roc_host = roc_host();
    let query_string: Arc<str> = Arc::from(query.as_str());
    unsafe {
        query.decref(roc_host);
    }
    let transaction = match unsafe { sqlite_txn_ref(transaction_handle) } {
        Ok(transaction) => Arc::clone(transaction),
        Err(_) => {
            release_resource_handle(transaction_handle, roc_host);
            return try_sqlite_prepare_err(sqlite_resource_unavailable("transaction", roc_host));
        }
    };
    release_resource_handle(transaction_handle, roc_host);
    prepare_logical_statement(
        StatementSource::Transaction(transaction),
        query_string,
        roc_host,
    )
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_txn_finish(
    transaction_handle: *mut u64,
    commit: bool,
) -> SqliteHostTxnFinishResult {
    let roc_host = roc_host();
    let transaction = match unsafe { sqlite_txn_ref(transaction_handle) } {
        Ok(transaction) => Arc::clone(transaction),
        Err(_) => {
            release_resource_handle(transaction_handle, roc_host);
            return try_sqlite_finish_err(sqlite_resource_unavailable("transaction", roc_host));
        }
    };
    release_resource_handle(transaction_handle, roc_host);

    let mut state = lock_unpoisoned(&transaction.state);
    if state.finished || state.connection.is_none() {
        return try_sqlite_finish_err(sqlite_error(
            HOST_TRANSACTION_FINISHED,
            "SQLite transaction has finished",
            roc_host,
        ));
    }
    if state.active_execution.is_some() {
        return try_sqlite_finish_err(sqlite_error(
            HOST_CONCURRENT_TRANSACTION_USE,
            "SQLite transaction still has an active execution",
            roc_host,
        ));
    }
    let sql = if commit { "COMMIT;" } else { "ROLLBACK;" };
    let connection = state
        .connection
        .as_mut()
        .expect("unfinished transaction owns a connection");
    if let Err((code, message)) = connection.execute_control(sql) {
        return try_sqlite_finish_err(sqlite_error(code, &message, roc_host));
    }
    state.finished = true;
    let connection = state
        .connection
        .take()
        .expect("finished transaction returns its connection");
    drop(state);
    transaction.pool.release(connection);
    try_sqlite_finish_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::AtomicU64;

    static NEXT_TEST_DATABASE: AtomicU64 = AtomicU64::new(1);

    struct TestDatabase {
        path: PathBuf,
        sqlite_path: SqlitePath,
    }

    impl TestDatabase {
        fn new(name: &str) -> Self {
            let id = NEXT_TEST_DATABASE.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "basic-webserver-sqlite-{name}-{}-{id}.db",
                std::process::id()
            ));
            remove_database_files(&path);
            Self {
                sqlite_path: path_to_sqlite(&path),
                path,
            }
        }
    }

    impl Drop for TestDatabase {
        fn drop(&mut self) {
            remove_database_files(&self.path);
        }
    }

    #[cfg(unix)]
    fn path_to_sqlite(path: &Path) -> SqlitePath {
        use std::os::unix::ffi::OsStrExt;
        SqlitePath::Unix(path.as_os_str().as_bytes().to_vec())
    }

    #[cfg(windows)]
    fn path_to_sqlite(path: &Path) -> SqlitePath {
        use std::os::windows::ffi::OsStrExt;
        SqlitePath::Windows(path.as_os_str().encode_wide().collect())
    }

    fn remove_database_files(path: &Path) {
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}-wal", path.display()));
        let _ = std::fs::remove_file(format!("{}-shm", path.display()));
    }

    fn test_config(cache_capacity: usize) -> PoolConfig {
        PoolConfig {
            acquire_timeout: Duration::from_millis(10),
            busy_timeout_ms: 10,
            statement_cache_capacity: cache_capacity,
            journal_mode: JournalMode::Wal,
            synchronous: Synchronous::Normal,
        }
    }

    fn scalar_i64(connection: &mut Connection, sql: &str) -> i64 {
        let statement = connection
            .take_statement(Arc::from(sql))
            .expect("test query prepares");
        assert_eq!(
            unsafe { libsqlite3_sys::sqlite3_step(statement.raw) },
            libsqlite3_sys::SQLITE_ROW
        );
        let value = unsafe { libsqlite3_sys::sqlite3_column_int64(statement.raw, 0) };
        connection.return_statement(statement);
        value
    }

    #[test]
    fn duplicate_binding_names_are_detected() {
        assert_eq!(
            first_duplicate_name([":one", ":two", ":one", ":three"]),
            Some(":one")
        );
        assert_eq!(first_duplicate_name([":one", ":two", ":three"]), None);
    }

    #[test]
    fn pool_saturation_is_bounded_and_recovery_returns_the_connection() {
        let database = TestDatabase::new("pool");
        let pool = DatabasePool::open(&database.sqlite_path, 1, test_config(2)).unwrap();
        let connection = pool.acquire().unwrap();
        assert!(matches!(pool.acquire(), Err(PoolAcquireError::Saturated)));
        pool.release(connection);
        let connection = pool.acquire().expect("released connection is reusable");
        pool.release(connection);
    }

    #[test]
    fn returned_native_statements_are_reused_per_connection() {
        let database = TestDatabase::new("cache");
        let pool = DatabasePool::open(&database.sqlite_path, 1, test_config(2)).unwrap();
        let mut connection = pool.acquire().unwrap();
        let query: Arc<str> = Arc::from("SELECT 42;");
        let statement = connection.take_statement(Arc::clone(&query)).unwrap();
        let original = statement.raw;
        connection.return_statement(statement);
        let reused = connection.take_statement(query).unwrap();
        assert_eq!(reused.raw, original);
        connection.return_statement(reused);
        pool.release(connection);
    }

    #[test]
    fn statement_cache_and_sql_text_are_bounded() {
        let database = TestDatabase::new("cache-bounds");
        let pool = DatabasePool::open(&database.sqlite_path, 1, test_config(1)).unwrap();
        let mut connection = pool.acquire().unwrap();
        let first = connection.take_statement(Arc::from("SELECT 1;")).unwrap();
        connection.return_statement(first);
        let second = connection.take_statement(Arc::from("SELECT 2;")).unwrap();
        connection.return_statement(second);
        assert_eq!(connection.statements.len(), 1);
        let oversized: Arc<str> = Arc::from(" ".repeat(MAX_SQL_BYTES + 1));
        let error = match connection.take_statement(oversized) {
            Ok(_) => panic!("oversized SQL should be rejected"),
            Err(error) => error,
        };
        assert_eq!(error.0, libsqlite3_sys::SQLITE_TOOBIG);
        pool.release(connection);
    }

    #[test]
    fn every_connection_receives_the_configured_safety_settings() {
        let database = TestDatabase::new("connection-settings");
        let mut config = test_config(0);
        config.synchronous = Synchronous::Full;
        let pool = DatabasePool::open(&database.sqlite_path, 2, config).unwrap();
        let mut first = pool.acquire().unwrap();
        let mut second = pool.acquire().unwrap();
        assert_eq!(scalar_i64(&mut first, "PRAGMA foreign_keys;"), 1);
        assert_eq!(scalar_i64(&mut first, "PRAGMA synchronous;"), 2);
        assert_eq!(scalar_i64(&mut second, "PRAGMA foreign_keys;"), 1);
        assert_eq!(scalar_i64(&mut second, "PRAGMA synchronous;"), 2);
        pool.release(first);
        pool.release(second);
    }

    #[test]
    fn execution_drop_resets_statement_and_releases_pool_lease() {
        let database = TestDatabase::new("execution-drop");
        let pool = DatabasePool::open(&database.sqlite_path, 1, test_config(2)).unwrap();
        let mut connection = pool.acquire().unwrap();
        let query: Arc<str> = Arc::from("SELECT 1;");
        let statement = connection.take_statement(Arc::clone(&query)).unwrap();
        let original = statement.raw;
        let deadline = configure_deadline(connection.raw, 1_000).unwrap();
        let execution = Execution {
            owner: ExecutionOwner::Pool {
                pool: Arc::clone(&pool),
                connection: Some(connection),
            },
            statement: Some(statement),
            deadline,
        };
        drop(execution);

        let mut connection = pool.acquire().expect("execution drop releases lease");
        let statement = connection.take_statement(query).unwrap();
        assert_eq!(statement.raw, original);
        connection.return_statement(statement);
        pool.release(connection);
    }

    #[test]
    fn unfinished_transaction_rolls_back_when_its_last_capability_drops() {
        let database = TestDatabase::new("rollback");
        let pool = DatabasePool::open(&database.sqlite_path, 1, test_config(2)).unwrap();
        let mut connection = pool.acquire().unwrap();
        connection
            .execute_control("CREATE TABLE changes(value INTEGER NOT NULL);")
            .unwrap();
        connection.execute_control("BEGIN IMMEDIATE;").unwrap();
        connection
            .execute_control("INSERT INTO changes VALUES (1);")
            .unwrap();
        let transaction = TransactionShared {
            pool: Arc::clone(&pool),
            state: Mutex::new(TransactionState {
                connection: Some(connection),
                active_execution: None,
                next_execution: 1,
                finished: false,
            }),
        };
        drop(transaction);

        let mut connection = pool.acquire().expect("rollback returns transaction lease");
        assert_eq!(
            scalar_i64(&mut connection, "SELECT count(*) FROM changes;"),
            0
        );
        pool.release(connection);
    }

    #[test]
    fn progress_handler_interrupts_queries_at_their_deadline() {
        let database = TestDatabase::new("deadline");
        let pool = DatabasePool::open(&database.sqlite_path, 1, test_config(0)).unwrap();
        let mut connection = pool.acquire().unwrap();
        let query: Arc<str> = Arc::from(
            "WITH RECURSIVE count(x) AS \
             (VALUES(0) UNION ALL SELECT x + 1 FROM count WHERE x < 100000000) \
             SELECT sum(x) FROM count;",
        );
        let statement = connection.take_statement(query).unwrap();
        let deadline = Box::new(DeadlineState {
            deadline: Instant::now(),
            timed_out: AtomicBool::new(false),
        });
        unsafe {
            libsqlite3_sys::sqlite3_progress_handler(
                connection.raw,
                1,
                Some(sqlite_progress_deadline),
                (&*deadline as *const DeadlineState).cast_mut().cast(),
            );
        }
        assert_eq!(
            unsafe { libsqlite3_sys::sqlite3_step(statement.raw) },
            libsqlite3_sys::SQLITE_INTERRUPT
        );
        assert!(deadline.timed_out.load(Ordering::Relaxed));
        unsafe {
            libsqlite3_sys::sqlite3_progress_handler(
                connection.raw,
                0,
                None,
                core::ptr::null_mut(),
            );
        }
        connection.return_statement(statement);
        pool.release(connection);
    }
}
