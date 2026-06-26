//! Roc platform host implementation for basic-webserver, using Roc's
//! direct-symbol host ABI.
//!
//! The app provides two entrypoints (declared in platform/main.roc):
//!   - `roc_init_for_host() -> Try(Box(Model), I32)` — run once at startup.
//!   - `roc_respond_for_host(request, Box(Model)) -> Response` — per request.
//!
//! The host owns the C `main`, calls `roc_init_for_host` once, stores the boxed
//! model, and runs a tokio/hyper server that calls `roc_respond_for_host` for
//! each request. See `http_server.rs`.

#![allow(improper_ctypes_definitions)]

use core::mem::ManuallyDrop;
use std::ffi::{c_char, c_void};
use std::fs;
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};

mod http_server;
mod roc_platform_abi;

use crate::roc_platform_abi::*;

// RustGlue assigns numbered names (TryTypeN, IOErrTypeN, ...) to anonymous Roc
// records and result types, and those numbers shift whenever a module is added.
// To stay robust against renumbering we alias against the *semantic* names the
// generator also emits (keyed by module + function name).
type StdoutUnitResult = StdoutLineResult;
type StdoutUnitResultPayload = StdoutLineResultPayload;
type StdoutUnitResultTag = StdoutLineResultTag;
type StdoutBytesResult = StdoutWriteBytesResult;
type StdoutBytesResultPayload = StdoutWriteBytesResultPayload;
type StdoutBytesResultTag = StdoutWriteBytesResultTag;

type StderrUnitResult = StderrLineResult;
type StderrUnitResultPayload = StderrLineResultPayload;
type StderrUnitResultTag = StderrLineResultTag;
type StderrBytesResult = StderrWriteBytesResult;
type StderrBytesResultPayload = StderrWriteBytesResultPayload;
type StderrBytesResultTag = StderrWriteBytesResultTag;

// CORE effect result aliases (see basic-cli/src/lib.rs). Keyed against the
// generated semantic names so they survive glue renumbering.
type CmdExitResult = CmdHostExecExitCodeResult;
type CmdExitResultPayload = CmdHostExecExitCodeResultPayload;
type CmdExitResultTag = CmdHostExecExitCodeResultTag;
type CmdOutputResult = CmdHostExecOutputResult;
type CmdOutputResultPayload = CmdHostExecOutputResultPayload;
type CmdOutputResultTag = CmdHostExecOutputResultTag;
type CmdOutputFailureResult = CmdHostExecOutputErrResult;
type CmdOutputFailureResultPayload = CmdHostExecOutputErrResultPayload;
type CmdOutputFailureResultTag = CmdHostExecOutputErrResultTag;
type CmdOutputFailure = CmdHostExecOutputErrOk;
type CmdOutputSuccess = CmdHostExecOutputOk;

type DirUnitResult = DirCreateResult;
type DirUnitResultPayload = DirCreateResultPayload;
type DirUnitResultTag = DirCreateResultTag;

type FileBytesResult = FileReadBytesResult;
type FileBytesResultPayload = FileReadBytesResultPayload;
type FileBytesResultTag = FileReadBytesResultTag;
type FileStrResult = FileReadUtf8Result;
type FileStrResultPayload = FileReadUtf8ResultPayload;
type FileStrResultTag = FileReadUtf8ResultTag;
type FileSizeResult = FileSizeInBytesResult;
type FileSizeResultPayload = FileSizeInBytesResultPayload;
type FileSizeResultTag = FileSizeInBytesResultTag;
type FileBoolResult = FileIsExecutableResult;
type FileBoolResultPayload = FileIsExecutableResultPayload;
type FileBoolResultTag = FileIsExecutableResultTag;
type FileTimeResult = FileTimeAccessedResult;
type FileTimeResultPayload = FileTimeAccessedResultPayload;
type FileTimeResultTag = FileTimeAccessedResultTag;

type PathTypeResult = PathHostPathTypeResult;
type PathTypeResultPayload = PathHostPathTypeResultPayload;
type PathTypeResultTag = PathHostPathTypeResultTag;
type PathInfo = PathHostPathTypeOk;

// The init/respond entrypoint and request/response boundary types are anonymous
// (`AnonStructN` / `TryTypeN`) and have NO generated semantic alias, so they are
// referenced by their numbered names. Update this block if the glue renumbers
// them (only happens when the platform's hosted/provides/types change).
pub(crate) type InitForHostResult = TryType102;
pub(crate) type InitForHostResultTag = TryType102Tag;
pub(crate) type RequestToAndFromHost = AnonStruct105;
pub(crate) type ResponseToAndFromHost = AnonStruct107;
pub(crate) type Header = AnonStruct86;

pub(crate) fn decref_response(value: ResponseToAndFromHost, roc_host: &RocHost) {
    decref_anon_struct107(value, roc_host);
}

// ============================================================================
// Host context (RocHost) and the Roc allocator/handler symbols
// ============================================================================

static DEBUG_OR_EXPECT_CALLED: AtomicBool = AtomicBool::new(false);
static mut ROC_HOST: *mut RocHost = core::ptr::null_mut();

fn set_roc_host(roc_host: *mut RocHost) {
    unsafe {
        ROC_HOST = roc_host;
    }
}

fn roc_host_ptr() -> *mut RocHost {
    unsafe {
        if ROC_HOST.is_null() {
            eprintln!("roc host error: RocHost not initialized");
            std::process::exit(1);
        }
        ROC_HOST
    }
}

pub(crate) fn roc_host() -> &'static RocHost {
    unsafe { &*roc_host_ptr() }
}

#[no_mangle]
pub extern "C" fn roc_alloc(length: usize, alignment: usize) -> *mut c_void {
    DefaultAllocators::roc_alloc(roc_host_ptr(), length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dealloc(ptr: *mut c_void, alignment: usize) {
    DefaultAllocators::roc_dealloc(roc_host_ptr(), ptr, alignment);
}

#[no_mangle]
pub extern "C" fn roc_realloc(
    ptr: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> *mut c_void {
    DefaultAllocators::roc_realloc(roc_host_ptr(), ptr, new_length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dbg(bytes: *const u8, len: usize) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    DefaultHandlers::roc_dbg(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_expect_failed(bytes: *const u8, len: usize) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    DefaultHandlers::roc_expect_failed(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_crashed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_crashed(roc_host_ptr(), bytes, len);
}

// ============================================================================
// IOErr conversion (std::io::ErrorKind -> generated Roc IOErr tag union)
// ============================================================================

macro_rules! define_common_io_err {
    ($from_io:ident, $other:ident, $ty:ident, $tag:ident, $payload:ident) => {
        fn $other(message: &str, roc_host: &RocHost) -> $ty {
            $ty {
                payload: $payload {
                    other: ManuallyDrop::new(RocStr::from_str(message, roc_host)),
                },
                tag: $tag::Other,
            }
        }

        fn $from_io(error: &io::Error, roc_host: &RocHost) -> $ty {
            match error.kind() {
                io::ErrorKind::AlreadyExists => $ty {
                    payload: $payload { already_exists: [] },
                    tag: $tag::AlreadyExists,
                },
                io::ErrorKind::BrokenPipe => $ty {
                    payload: $payload { broken_pipe: [] },
                    tag: $tag::BrokenPipe,
                },
                io::ErrorKind::Interrupted => $ty {
                    payload: $payload { interrupted: [] },
                    tag: $tag::Interrupted,
                },
                io::ErrorKind::NotFound => $ty {
                    payload: $payload { not_found: [] },
                    tag: $tag::NotFound,
                },
                io::ErrorKind::OutOfMemory => $ty {
                    payload: $payload { out_of_memory: [] },
                    tag: $tag::OutOfMemory,
                },
                io::ErrorKind::PermissionDenied => $ty {
                    payload: $payload {
                        permission_denied: [],
                    },
                    tag: $tag::PermissionDenied,
                },
                io::ErrorKind::Unsupported => $ty {
                    payload: $payload { unsupported: [] },
                    tag: $tag::Unsupported,
                },
                _ => $other(&error.to_string(), roc_host),
            }
        }
    };
}

define_common_io_err!(
    stdout_io_err_from_io,
    stdout_io_err_other,
    StdoutIOErr,
    StdoutIOErrTag,
    StdoutIOErrPayload
);
define_common_io_err!(
    stderr_io_err_from_io,
    stderr_io_err_other,
    StderrIOErr,
    StderrIOErrTag,
    StderrIOErrPayload
);
define_common_io_err!(
    cmd_io_err_from_io,
    cmd_io_err_other,
    CmdIOErr,
    CmdIOErrTag,
    CmdIOErrPayload
);
define_common_io_err!(
    dir_io_err_from_io,
    dir_io_err_other,
    DirIOErr,
    DirIOErrTag,
    DirIOErrPayload
);
define_common_io_err!(
    file_io_err_from_io,
    file_io_err_other,
    FileIOErr,
    FileIOErrTag,
    FileIOErrPayload
);
define_common_io_err!(
    path_io_err_from_io,
    path_io_err_other,
    PathIOErr,
    PathIOErrTag,
    PathIOErrPayload
);

// ============================================================================
// Stdout / Stderr hosted functions
// ============================================================================

fn try_stdout_unit_ok() -> StdoutUnitResult {
    StdoutUnitResult {
        payload: StdoutUnitResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: StdoutUnitResultTag::Ok,
    }
}

fn try_stdout_unit_err(error: StdoutIOErr) -> StdoutUnitResult {
    StdoutUnitResult {
        payload: StdoutUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StdoutUnitResultTag::Err,
    }
}

fn try_stdout_bytes_ok() -> StdoutBytesResult {
    StdoutBytesResult {
        payload: StdoutBytesResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: StdoutBytesResultTag::Ok,
    }
}

fn try_stdout_bytes_err(error: StdoutIOErr) -> StdoutBytesResult {
    StdoutBytesResult {
        payload: StdoutBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StdoutBytesResultTag::Err,
    }
}

fn try_stderr_unit_ok() -> StderrUnitResult {
    StderrUnitResult {
        payload: StderrUnitResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: StderrUnitResultTag::Ok,
    }
}

fn try_stderr_unit_err(error: StderrIOErr) -> StderrUnitResult {
    StderrUnitResult {
        payload: StderrUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StderrUnitResultTag::Err,
    }
}

fn try_stderr_bytes_ok() -> StderrBytesResult {
    StderrBytesResult {
        payload: StderrBytesResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: StderrBytesResultTag::Ok,
    }
}

fn try_stderr_bytes_err(error: StderrIOErr) -> StderrBytesResult {
    StderrBytesResult {
        payload: StderrBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StderrBytesResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_line(message: RocStr) -> StdoutUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        writeln!(stdout, "{}", message.as_str())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(stdout_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_write(message: RocStr) -> StdoutUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        write!(stdout, "{}", message.as_str()).and_then(|()| stdout.flush())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(stdout_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_write_bytes(bytes: RocListWith<u8, false>) -> StdoutBytesResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        stdout
            .write_all(bytes.as_slice())
            .and_then(|()| stdout.flush())
    };
    bytes.decref(roc_host);

    match result {
        Ok(()) => try_stdout_bytes_ok(),
        Err(error) => try_stdout_bytes_err(stdout_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_line(message: RocStr) -> StderrUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        writeln!(stderr, "{}", message.as_str())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(stderr_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write(message: RocStr) -> StderrUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        write!(stderr, "{}", message.as_str()).and_then(|()| stderr.flush())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(stderr_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write_bytes(bytes: RocListWith<u8, false>) -> StderrBytesResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        stderr
            .write_all(bytes.as_slice())
            .and_then(|()| stderr.flush())
    };
    bytes.decref(roc_host);

    match result {
        Ok(()) => try_stderr_bytes_ok(),
        Err(error) => try_stderr_bytes_err(stderr_io_err_from_io(&error, roc_host)),
    }
}

// ============================================================================
// CORE effects: Cmd / Dir / Env / File / Path / Utc
// (adapted from basic-cli/src/lib.rs)
// ============================================================================

fn decref_roc_str_list(list: &RocList<RocStr>, roc_host: &RocHost) {
    for item in list.as_slice() {
        item.decref(roc_host);
    }
    list.decref(roc_host);
}

fn decref_host_cmd_arg(cmd: &Cmd, roc_host: &RocHost) {
    decref_roc_str_list(&cmd.args, roc_host);
    decref_roc_str_list(&cmd.envs, roc_host);
    cmd.program.decref(roc_host);
}

fn cmd_to_std(cmd: &Cmd) -> std::process::Command {
    let mut std_cmd = std::process::Command::new(cmd.program.as_str());

    for arg in cmd.args.as_slice() {
        std_cmd.arg(arg.as_str());
    }

    if cmd.clear_envs {
        std_cmd.env_clear();
    }

    for chunk in cmd.envs.as_slice().chunks(2) {
        if let [key, value] = chunk {
            std_cmd.env(key.as_str(), value.as_str());
        }
    }

    std_cmd
}

fn try_cmd_exit_ok(value: i32) -> CmdExitResult {
    CmdExitResult {
        payload: CmdExitResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: CmdExitResultTag::Ok,
    }
}

fn try_cmd_exit_err(error: CmdIOErr) -> CmdExitResult {
    CmdExitResult {
        payload: CmdExitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: CmdExitResultTag::Err,
    }
}

fn try_cmd_output_ok(value: CmdOutputSuccess) -> CmdOutputResult {
    CmdOutputResult {
        payload: CmdOutputResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: CmdOutputResultTag::Ok,
    }
}

fn try_cmd_output_err(error: CmdOutputFailureResult) -> CmdOutputResult {
    CmdOutputResult {
        payload: CmdOutputResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: CmdOutputResultTag::Err,
    }
}

fn try_cmd_output_failure_ok(value: CmdOutputFailure) -> CmdOutputFailureResult {
    CmdOutputFailureResult {
        payload: CmdOutputFailureResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: CmdOutputFailureResultTag::Ok,
    }
}

fn try_cmd_output_failure_err(error: CmdIOErr) -> CmdOutputFailureResult {
    CmdOutputFailureResult {
        payload: CmdOutputFailureResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: CmdOutputFailureResultTag::Err,
    }
}

fn try_dir_unit_ok() -> DirUnitResult {
    DirUnitResult {
        payload: DirUnitResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: DirUnitResultTag::Ok,
    }
}

fn try_dir_unit_err(error: DirIOErr) -> DirUnitResult {
    DirUnitResult {
        payload: DirUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: DirUnitResultTag::Err,
    }
}

fn try_dir_list_ok(value: RocList<RocStr>) -> DirListResult {
    DirListResult {
        payload: DirListResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: DirListResultTag::Ok,
    }
}

fn try_dir_list_err(error: DirIOErr) -> DirListResult {
    DirListResult {
        payload: DirListResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: DirListResultTag::Err,
    }
}

fn try_env_str_ok(value: RocStr) -> EnvVarResult {
    EnvVarResult {
        payload: EnvVarResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: EnvVarResultTag::Ok,
    }
}

fn try_env_str_err(error: RocStr) -> EnvVarResult {
    EnvVarResult {
        payload: EnvVarResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: EnvVarResultTag::Err,
    }
}

fn try_env_cwd_ok(value: RocStr) -> EnvCwdResult {
    EnvCwdResult {
        payload: EnvCwdResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: EnvCwdResultTag::Ok,
    }
}

fn try_env_cwd_err() -> EnvCwdResult {
    EnvCwdResult {
        payload: EnvCwdResultPayload {
            err: ManuallyDrop::new(core::ptr::null_mut()),
        },
        tag: EnvCwdResultTag::Err,
    }
}

fn try_env_exe_path_ok(value: RocStr) -> EnvExePathResult {
    EnvExePathResult {
        payload: EnvExePathResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: EnvExePathResultTag::Ok,
    }
}

fn try_env_exe_path_err() -> EnvExePathResult {
    EnvExePathResult {
        payload: EnvExePathResultPayload {
            err: ManuallyDrop::new(core::ptr::null_mut()),
        },
        tag: EnvExePathResultTag::Err,
    }
}

fn try_file_bytes_ok(value: RocListWith<u8, false>) -> FileBytesResult {
    FileBytesResult {
        payload: FileBytesResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileBytesResultTag::Ok,
    }
}

fn try_file_bytes_err(error: FileIOErr) -> FileBytesResult {
    FileBytesResult {
        payload: FileBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileBytesResultTag::Err,
    }
}

fn try_file_write_bytes_ok() -> FileWriteBytesResult {
    FileWriteBytesResult {
        payload: FileWriteBytesResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: FileWriteBytesResultTag::Ok,
    }
}

fn try_file_write_bytes_err(error: FileIOErr) -> FileWriteBytesResult {
    FileWriteBytesResult {
        payload: FileWriteBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileWriteBytesResultTag::Err,
    }
}

fn try_file_str_ok(value: RocStr) -> FileStrResult {
    FileStrResult {
        payload: FileStrResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileStrResultTag::Ok,
    }
}

fn try_file_str_err(error: FileIOErr) -> FileStrResult {
    FileStrResult {
        payload: FileStrResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileStrResultTag::Err,
    }
}

fn try_file_write_utf8_ok() -> FileWriteUtf8Result {
    FileWriteUtf8Result {
        payload: FileWriteUtf8ResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: FileWriteUtf8ResultTag::Ok,
    }
}

fn try_file_write_utf8_err(error: FileIOErr) -> FileWriteUtf8Result {
    FileWriteUtf8Result {
        payload: FileWriteUtf8ResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileWriteUtf8ResultTag::Err,
    }
}

fn try_file_delete_ok() -> FileDeleteResult {
    FileDeleteResult {
        payload: FileDeleteResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: FileDeleteResultTag::Ok,
    }
}

fn try_file_delete_err(error: FileIOErr) -> FileDeleteResult {
    FileDeleteResult {
        payload: FileDeleteResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileDeleteResultTag::Err,
    }
}

fn try_file_size_ok(value: u64) -> FileSizeResult {
    FileSizeResult {
        payload: FileSizeResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileSizeResultTag::Ok,
    }
}

fn try_file_size_err(error: FileIOErr) -> FileSizeResult {
    FileSizeResult {
        payload: FileSizeResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileSizeResultTag::Err,
    }
}

fn try_file_bool_ok(value: bool) -> FileBoolResult {
    FileBoolResult {
        payload: FileBoolResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileBoolResultTag::Ok,
    }
}

fn try_file_bool_err(error: FileIOErr) -> FileBoolResult {
    FileBoolResult {
        payload: FileBoolResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileBoolResultTag::Err,
    }
}

fn try_file_time_ok(value: u128) -> FileTimeResult {
    FileTimeResult {
        payload: FileTimeResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileTimeResultTag::Ok,
    }
}

fn try_file_time_err(error: FileIOErr) -> FileTimeResult {
    FileTimeResult {
        payload: FileTimeResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileTimeResultTag::Err,
    }
}

fn try_path_type_ok(value: PathInfo) -> PathTypeResult {
    PathTypeResult {
        payload: PathTypeResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: PathTypeResultTag::Ok,
    }
}

fn try_path_type_err(error: PathIOErr) -> PathTypeResult {
    PathTypeResult {
        payload: PathTypeResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: PathTypeResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_exit_code(cmd: Cmd) -> CmdExitResult {
    let roc_host = roc_host();
    let mut std_cmd = cmd_to_std(&cmd);
    decref_host_cmd_arg(&cmd, roc_host);

    match std_cmd.status() {
        Ok(status) => match status.code() {
            Some(code) => try_cmd_exit_ok(code),
            None => try_cmd_exit_err(cmd_io_err_other("Process was killed by signal", roc_host)),
        },
        Err(error) => try_cmd_exit_err(cmd_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_output(cmd: Cmd) -> CmdOutputResult {
    let roc_host = roc_host();
    let mut std_cmd = cmd_to_std(&cmd);
    decref_host_cmd_arg(&cmd, roc_host);

    match std_cmd.output() {
        Ok(output) => {
            let stdout_bytes = RocListWith::<u8, false>::from_slice(&output.stdout, roc_host);
            let stderr_bytes = RocListWith::<u8, false>::from_slice(&output.stderr, roc_host);

            match output.status.code() {
                Some(0) => try_cmd_output_ok(CmdOutputSuccess {
                    stderr_bytes,
                    stdout_bytes,
                }),
                Some(exit_code) => {
                    try_cmd_output_err(try_cmd_output_failure_ok(CmdOutputFailure {
                        stderr_bytes,
                        stdout_bytes,
                        exit_code,
                    }))
                }
                None => {
                    stdout_bytes.decref(roc_host);
                    stderr_bytes.decref(roc_host);
                    try_cmd_output_err(try_cmd_output_failure_err(cmd_io_err_other(
                        "Process was killed by signal",
                        roc_host,
                    )))
                }
            }
        }
        Err(error) => try_cmd_output_err(try_cmd_output_failure_err(cmd_io_err_from_io(
            &error, roc_host,
        ))),
    }
}

fn path_from_roc_str(path: RocStr, roc_host: &RocHost) -> String {
    let path_string = path.as_str().to_owned();
    path.decref(roc_host);
    path_string
}

#[no_mangle]
pub extern "C" fn hosted_dir_create(path: RocStr) -> DirUnitResult {
    let roc_host = roc_host();
    match fs::create_dir(path_from_roc_str(path, roc_host)) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_create_all(path: RocStr) -> DirUnitResult {
    let roc_host = roc_host();
    match fs::create_dir_all(path_from_roc_str(path, roc_host)) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_delete_all(path: RocStr) -> DirUnitResult {
    let roc_host = roc_host();
    match fs::remove_dir_all(path_from_roc_str(path, roc_host)) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_delete_empty(path: RocStr) -> DirUnitResult {
    let roc_host = roc_host();
    match fs::remove_dir(path_from_roc_str(path, roc_host)) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_list(path: RocStr) -> DirListResult {
    let roc_host = roc_host();
    match fs::read_dir(path_from_roc_str(path, roc_host)) {
        Ok(read_dir) => {
            let entries: Vec<String> = read_dir
                .filter_map(|entry| {
                    entry
                        .ok()
                        .map(|entry| entry.path().to_string_lossy().into_owned())
                })
                .collect();
            let list = RocList::<RocStr>::allocate(entries.len(), roc_host);
            for (index, entry) in entries.iter().enumerate() {
                unsafe {
                    list.elements
                        .add(index)
                        .write(RocStr::from_str(entry, roc_host));
                }
            }
            try_dir_list_ok(list)
        }
        Err(error) => try_dir_list_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_cwd() -> EnvCwdResult {
    let roc_host = roc_host();
    match std::env::current_dir() {
        Ok(path) => try_env_cwd_ok(RocStr::from_str(path.to_string_lossy().as_ref(), roc_host)),
        Err(_) => try_env_cwd_err(),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_exe_path() -> EnvExePathResult {
    let roc_host = roc_host();
    match std::env::current_exe() {
        Ok(path) => {
            try_env_exe_path_ok(RocStr::from_str(path.to_string_lossy().as_ref(), roc_host))
        }
        Err(_) => try_env_exe_path_err(),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_temp_dir() -> RocStr {
    let roc_host = roc_host();
    RocStr::from_str(std::env::temp_dir().to_string_lossy().as_ref(), roc_host)
}

#[no_mangle]
pub extern "C" fn hosted_env_var(name: RocStr) -> EnvVarResult {
    let roc_host = roc_host();
    let key = name.as_str().to_owned();
    match std::env::var_os(&key) {
        Some(value) => {
            name.decref(roc_host);
            try_env_str_ok(RocStr::from_str(value.to_string_lossy().as_ref(), roc_host))
        }
        None => try_env_str_err(name),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_delete(path: RocStr) -> FileDeleteResult {
    let roc_host = roc_host();
    match fs::remove_file(path_from_roc_str(path, roc_host)) {
        Ok(()) => try_file_delete_ok(),
        Err(error) => try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_bytes(path: RocStr) -> FileBytesResult {
    let roc_host = roc_host();
    match fs::read(path_from_roc_str(path, roc_host)) {
        Ok(bytes) => try_file_bytes_ok(RocListWith::<u8, false>::from_slice(&bytes, roc_host)),
        Err(error) => try_file_bytes_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_utf8(path: RocStr) -> FileStrResult {
    let roc_host = roc_host();
    match fs::read_to_string(path_from_roc_str(path, roc_host)) {
        Ok(content) => try_file_str_ok(RocStr::from_str(&content, roc_host)),
        Err(error) => try_file_str_err(file_io_err_from_io(&error, roc_host)),
    }
}

fn file_metadata(path: RocStr, roc_host: &RocHost) -> io::Result<fs::Metadata> {
    fs::metadata(path_from_roc_str(path, roc_host))
}

#[no_mangle]
pub extern "C" fn hosted_file_size_in_bytes(path: RocStr) -> FileSizeResult {
    let roc_host = roc_host();
    match file_metadata(path, roc_host) {
        Ok(metadata) => try_file_size_ok(metadata.len()),
        Err(error) => try_file_size_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[cfg(not(unix))]
fn unsupported_file_permission_error() -> io::Error {
    io::Error::new(
        io::ErrorKind::Unsupported,
        "file permission checks are not implemented on this platform",
    )
}

fn file_permission_bit(path: RocStr, roc_host: &RocHost, bit: u32) -> io::Result<bool> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        let metadata = file_metadata(path, roc_host)?;
        Ok(metadata.permissions().mode() & bit != 0)
    }

    #[cfg(not(unix))]
    {
        let _ = path_from_roc_str(path, roc_host);
        let _ = bit;
        Err(unsupported_file_permission_error())
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_executable(path: RocStr) -> FileBoolResult {
    let roc_host = roc_host();
    match file_permission_bit(path, roc_host, 0o111) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_readable(path: RocStr) -> FileBoolResult {
    let roc_host = roc_host();
    match file_permission_bit(path, roc_host, 0o400) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_writable(path: RocStr) -> FileBoolResult {
    let roc_host = roc_host();
    match file_permission_bit(path, roc_host, 0o200) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(file_io_err_from_io(&error, roc_host)),
    }
}

fn nanos_since_epoch(time: std::time::SystemTime) -> io::Result<u128> {
    time.duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .map_err(|error| io::Error::new(io::ErrorKind::Other, error.to_string()))
}

fn file_time(
    path: RocStr,
    roc_host: &RocHost,
    read_time: fn(&fs::Metadata) -> io::Result<std::time::SystemTime>,
) -> io::Result<u128> {
    let metadata = file_metadata(path, roc_host)?;
    read_time(&metadata).and_then(nanos_since_epoch)
}

#[no_mangle]
pub extern "C" fn hosted_file_time_accessed(path: RocStr) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::accessed) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_time_created(path: RocStr) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::created) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_time_modified(path: RocStr) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::modified) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_write_bytes(
    path: RocStr,
    bytes: RocListWith<u8, false>,
) -> FileWriteBytesResult {
    let roc_host = roc_host();
    let path_string = path_from_roc_str(path, roc_host);
    let result = fs::write(path_string, bytes.as_slice());
    bytes.decref(roc_host);

    match result {
        Ok(()) => try_file_write_bytes_ok(),
        Err(error) => try_file_write_bytes_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_write_utf8(path: RocStr, content: RocStr) -> FileWriteUtf8Result {
    let roc_host = roc_host();
    let path_string = path_from_roc_str(path, roc_host);
    let content_string = content.as_str().to_owned();
    content.decref(roc_host);

    match fs::write(path_string, content_string) {
        Ok(()) => try_file_write_utf8_ok(),
        Err(error) => try_file_write_utf8_err(file_io_err_from_io(&error, roc_host)),
    }
}

fn path_buf_from_roc_bytes(
    bytes: RocListWith<u8, false>,
    roc_host: &RocHost,
) -> std::path::PathBuf {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;

        let path = std::ffi::OsStr::from_bytes(bytes.as_slice()).to_owned();
        bytes.decref(roc_host);
        std::path::PathBuf::from(path)
    }

    #[cfg(not(unix))]
    {
        let path = String::from_utf8_lossy(bytes.as_slice()).into_owned();
        bytes.decref(roc_host);
        std::path::PathBuf::from(path)
    }
}

#[no_mangle]
pub extern "C" fn hosted_path_type(path: RocListWith<u8, false>) -> PathTypeResult {
    let roc_host = roc_host();
    let path = path_buf_from_roc_bytes(path, roc_host);

    match path.symlink_metadata() {
        Ok(metadata) => {
            let file_type = metadata.file_type();
            try_path_type_ok(PathInfo {
                is_dir: metadata.is_dir(),
                is_file: metadata.is_file(),
                is_sym_link: file_type.is_symlink(),
            })
        }
        Err(error) => try_path_type_err(path_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_utc_now() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("time went backwards")
        .as_nanos()
}

// ============================================================================
// C entrypoint
// ============================================================================

#[cfg(not(test))]
#[no_mangle]
pub extern "C" fn main(_argc: i32, _argv: *const *const c_char) -> i32 {
    rust_main()
}

pub fn rust_main() -> i32 {
    // Leak the RocHost so the pointer stashed in ROC_HOST stays valid for the
    // whole life of the (long-running) server.
    let roc_host: &'static mut RocHost = Box::leak(Box::new(make_roc_host(core::ptr::null_mut())));
    set_roc_host(roc_host);

    http_server::start()
}
