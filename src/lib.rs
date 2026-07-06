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
use std::cell::RefCell;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::sync::atomic::{AtomicBool, Ordering};

mod http_server;
mod roc_platform_abi;

use crate::roc_platform_abi::*;

// RustGlue assigns numbered names (TryTypeN, IOErrTypeN, ...) to anonymous Roc
// records and result types, and those numbers shift whenever a module is added.
// To stay robust against renumbering we alias against the *semantic* names the
// generator also emits (keyed by module + function name).
type StdoutUnitResult = HostStdoutLineResult;
type StdoutUnitResultPayload = HostStdoutLineResultPayload;
type StdoutUnitResultTag = HostStdoutLineResultTag;
type StdoutBytesResult = HostStdoutWriteBytesResult;
type StdoutBytesResultPayload = HostStdoutWriteBytesResultPayload;
type StdoutBytesResultTag = HostStdoutWriteBytesResultTag;

type StderrUnitResult = HostStderrLineResult;
type StderrUnitResultPayload = HostStderrLineResultPayload;
type StderrUnitResultTag = HostStderrLineResultTag;
type StderrBytesResult = HostStderrWriteBytesResult;
type StderrBytesResultPayload = HostStderrWriteBytesResultPayload;
type StderrBytesResultTag = HostStderrWriteBytesResultTag;

// CORE effect result aliases (see basic-cli/src/lib.rs). Keyed against the
// generated semantic names so they survive glue renumbering.
type Cmd = HostCmdExecExitCodeArgs;
type CmdExitResult = HostCmdExecExitCodeResult;
type CmdExitResultPayload = HostCmdExecExitCodeResultPayload;
type CmdExitResultTag = HostCmdExecExitCodeResultTag;
type CmdOutputResult = HostCmdExecOutputResult;
type CmdOutputResultPayload = HostCmdExecOutputResultPayload;
type CmdOutputResultTag = HostCmdExecOutputResultTag;
type CmdOutputFailureResult = HostCmdExecOutputErrResult;
type CmdOutputFailureResultPayload = HostCmdExecOutputErrResultPayload;
type CmdOutputFailureResultTag = HostCmdExecOutputErrResultTag;
type CmdOutputFailure = HostCmdExecOutputErrOk;
type CmdOutputSuccess = HostCmdExecOutputOk;

type DirUnitResult = HostDirCreateResult;
type DirUnitResultPayload = HostDirCreateResultPayload;
type DirUnitResultTag = HostDirCreateResultTag;
type DirListResult = HostDirListResult;
type DirListResultPayload = HostDirListResultPayload;
type DirListResultTag = HostDirListResultTag;
type RawPath = HostDirListOk;

type EnvCwdResult = HostEnvCwdResult;
type EnvCwdResultPayload = HostEnvCwdResultPayload;
type EnvCwdResultTag = HostEnvCwdResultTag;
type EnvExePathResult = HostEnvExePathResult;
type EnvExePathResultPayload = HostEnvExePathResultPayload;
type EnvExePathResultTag = HostEnvExePathResultTag;
type EnvVarResult = HostEnvVarResult;
type EnvVarResultPayload = HostEnvVarResultPayload;
type EnvVarResultTag = HostEnvVarResultTag;

type FileBytesResult = HostFileReadBytesResult;
type FileBytesResultPayload = HostFileReadBytesResultPayload;
type FileBytesResultTag = HostFileReadBytesResultTag;
type FileStrResult = HostFileReadUtf8Result;
type FileStrResultPayload = HostFileReadUtf8ResultPayload;
type FileStrResultTag = HostFileReadUtf8ResultTag;
type FileSizeResult = HostFileSizeInBytesResult;
type FileSizeResultPayload = HostFileSizeInBytesResultPayload;
type FileSizeResultTag = HostFileSizeInBytesResultTag;
type FileBoolResult = HostFileIsExecutableResult;
type FileBoolResultPayload = HostFileIsExecutableResultPayload;
type FileBoolResultTag = HostFileIsExecutableResultTag;
type FileTimeResult = HostFileTimeAccessedResult;
type FileTimeResultPayload = HostFileTimeAccessedResultPayload;
type FileTimeResultTag = HostFileTimeAccessedResultTag;
type FileDeleteResult = HostFileDeleteResult;
type FileDeleteResultPayload = HostFileDeleteResultPayload;
type FileDeleteResultTag = HostFileDeleteResultTag;
type FileWriteBytesResult = HostFileWriteBytesResult;
type FileWriteBytesResultPayload = HostFileWriteBytesResultPayload;
type FileWriteBytesResultTag = HostFileWriteBytesResultTag;
type FileWriteUtf8Result = HostFileWriteUtf8Result;
type FileWriteUtf8ResultPayload = HostFileWriteUtf8ResultPayload;
type FileWriteUtf8ResultTag = HostFileWriteUtf8ResultTag;

type PathTypeResult = HostPathTypeResult;
type PathTypeResultPayload = HostPathTypeResultPayload;
type PathTypeResultTag = HostPathTypeResultTag;
type PathInfo = HostPathTypeOk;

type SqliteHostPrepareResult = HostSqlitePrepareResult;
type SqliteHostPrepareResultPayload = HostSqlitePrepareResultPayload;
type SqliteHostPrepareResultTag = HostSqlitePrepareResultTag;
type SqliteHostBindResult = HostSqliteBindResult;
type SqliteHostBindResultPayload = HostSqliteBindResultPayload;
type SqliteHostBindResultTag = HostSqliteBindResultTag;
type SqliteHostColumnValueResult = HostSqliteColumnValueResult;
type SqliteHostColumnValueResultPayload = HostSqliteColumnValueResultPayload;
type SqliteHostColumnValueResultTag = HostSqliteColumnValueResultTag;
type SqliteHostStepResult = HostSqliteStepResult;
type SqliteHostStepResultPayload = HostSqliteStepResultPayload;
type SqliteHostStepResultTag = HostSqliteStepResultTag;

type TcpHostConnectResult = HostTcpConnectResult;
type TcpHostConnectResultPayload = HostTcpConnectResultPayload;
type TcpHostConnectResultTag = HostTcpConnectResultTag;
type TcpHostReadUpToResult = HostTcpReadUpToResult;
type TcpHostReadUpToResultPayload = HostTcpReadUpToResultPayload;
type TcpHostReadUpToResultTag = HostTcpReadUpToResultTag;
type TcpHostReadExactlyResult = HostTcpReadExactlyResult;
type TcpHostReadUntilResult = HostTcpReadUntilResult;
type TcpHostWriteResult = HostTcpWriteResult;
type TcpHostWriteResultPayload = HostTcpWriteResultPayload;
type TcpHostWriteResultTag = HostTcpWriteResultTag;

type StdoutIOErr = HostIOErr;
type StdoutIOErrPayload = HostIOErrPayload;
type StdoutIOErrTag = HostIOErrTag;
type StderrIOErr = HostIOErr;
type StderrIOErrPayload = HostIOErrPayload;
type StderrIOErrTag = HostIOErrTag;
type CmdIOErr = HostIOErr;
type CmdIOErrPayload = HostIOErrPayload;
type CmdIOErrTag = HostIOErrTag;
type DirIOErr = HostIOErr;
type DirIOErrPayload = HostIOErrPayload;
type DirIOErrTag = HostIOErrTag;
type EnvIOErr = HostIOErr;
type EnvIOErrPayload = HostIOErrPayload;
type EnvIOErrTag = HostIOErrTag;
type FileIOErr = HostIOErr;
type FileIOErrPayload = HostIOErrPayload;
type FileIOErrTag = HostIOErrTag;
type PathIOErr = HostIOErr;
type PathIOErrPayload = HostIOErrPayload;
type PathIOErrTag = HostIOErrTag;

// The init/respond entrypoint and request/response boundary types are anonymous
// (`AnonStructN` / `TryTypeN`) and have NO generated semantic alias, so they are
// referenced by their numbered names. Update this block if the glue renumbers
// them (only happens when the platform's hosted/provides/types change).
pub(crate) type InitForHostResult = TryType81;
pub(crate) type InitForHostResultTag = TryType81Tag;
pub(crate) type RequestToAndFromHost = AnonStruct85;
pub(crate) type ResponseToAndFromHost = AnonStruct89;
pub(crate) type Header = AnonStruct87;

pub(crate) fn decref_response(value: ResponseToAndFromHost, roc_host: &RocHost) {
    decref_anon_struct89(value, roc_host);
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
    env_io_err_from_io,
    env_io_err_other,
    EnvIOErr,
    EnvIOErrTag,
    EnvIOErrPayload
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

fn try_dir_list_ok(value: RocList<RawPath>) -> DirListResult {
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

fn try_env_cwd_err(error: EnvIOErr) -> EnvCwdResult {
    EnvCwdResult {
        payload: EnvCwdResultPayload {
            err: ManuallyDrop::new(error),
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

fn try_env_exe_path_err(error: EnvIOErr) -> EnvExePathResult {
    EnvExePathResult {
        payload: EnvExePathResultPayload {
            err: ManuallyDrop::new(error),
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
            let entries: Vec<std::path::PathBuf> = read_dir
                .filter_map(|entry| entry.ok().map(|entry| entry.path()))
                .collect();
            let list = RocList::<RawPath>::allocate(entries.len(), roc_host);
            for (index, entry) in entries.into_iter().enumerate() {
                unsafe {
                    list.elements
                        .add(index)
                        .write(raw_path_from_path_buf(entry, roc_host));
                }
            }
            try_dir_list_ok(list)
        }
        Err(error) => try_dir_list_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_cwd(_dummy: RocStr) -> EnvCwdResult {
    let roc_host = roc_host();
    _dummy.decref(roc_host);

    match std::env::current_dir() {
        Ok(path) => try_env_cwd_ok(RocStr::from_str(path.to_string_lossy().as_ref(), roc_host)),
        Err(error) => try_env_cwd_err(env_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_exe_path(_dummy: RocStr) -> EnvExePathResult {
    let roc_host = roc_host();
    _dummy.decref(roc_host);

    match std::env::current_exe() {
        Ok(path) => {
            try_env_exe_path_ok(RocStr::from_str(path.to_string_lossy().as_ref(), roc_host))
        }
        Err(error) => try_env_exe_path_err(env_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_temp_dir(_dummy: RocStr) -> RocStr {
    let roc_host = roc_host();
    _dummy.decref(roc_host);

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

fn raw_path_from_path_buf(path: std::path::PathBuf, roc_host: &RocHost) -> RawPath {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;

        let bytes = path.into_os_string().into_vec();
        RawPath {
            unix_bytes: RocListWith::<u8, false>::from_slice(&bytes, roc_host),
            windows_u16s: RocListWith::<u16, false>::from_slice(&[], roc_host),
            is_windows: false,
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;

        let u16s: Vec<u16> = path.as_os_str().encode_wide().collect();
        RawPath {
            unix_bytes: RocListWith::<u8, false>::from_slice(&[], roc_host),
            windows_u16s: RocListWith::<u16, false>::from_slice(&u16s, roc_host),
            is_windows: true,
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        let bytes = path.to_string_lossy().as_bytes().to_vec();
        RawPath {
            unix_bytes: RocListWith::<u8, false>::from_slice(&bytes, roc_host),
            windows_u16s: RocListWith::<u16, false>::from_slice(&[], roc_host),
            is_windows: false,
        }
    }
}

fn path_buf_from_raw_path(path: HostPathTypeArgs, roc_host: &RocHost) -> std::path::PathBuf {
    let unix_bytes = path.unix_bytes;
    let windows_u16s = path.windows_u16s;

    let path_buf = if path.is_windows {
        #[cfg(windows)]
        {
            use std::os::windows::ffi::OsStringExt;

            let os_string = std::ffi::OsString::from_wide(windows_u16s.as_slice());
            std::path::PathBuf::from(os_string)
        }

        #[cfg(not(windows))]
        {
            std::path::PathBuf::from(String::from_utf16_lossy(windows_u16s.as_slice()))
        }
    } else {
        #[cfg(unix)]
        {
            use std::os::unix::ffi::OsStringExt;

            let os_string = std::ffi::OsString::from_vec(unix_bytes.as_slice().to_vec());
            std::path::PathBuf::from(os_string)
        }

        #[cfg(not(unix))]
        {
            std::path::PathBuf::from(String::from_utf8_lossy(unix_bytes.as_slice()).into_owned())
        }
    };

    unix_bytes.decref(roc_host);
    windows_u16s.decref(roc_host);
    path_buf
}

#[no_mangle]
pub extern "C" fn hosted_path_type(path: HostPathTypeArgs) -> PathTypeResult {
    let roc_host = roc_host();
    let path = path_buf_from_raw_path(path, roc_host);

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
// SQLite
//
// The generated glue represents `Sqlite.Stmt` (a `Box(U64)`) as `*mut u64`: a
// boxed u64 whose value we use to stash a raw `*mut SqliteStatement`. The box is
// allocated/refcounted with the generated `allocate_box`/`decref_box_with`
// helpers; teardown (running `sqlite3_finalize`) happens in `drop_sqlite_stmt`
// when the last reference is released. Each host fn that takes a handle calls
// `release_sqlite_stmt` before returning to balance the incref Roc performs when
// the value stays live.
// ============================================================================

// Generated value/error/binding types (see src/roc_platform_abi.rs).
type SqliteValue = BytesOrIntegerOrNullOrRealOrString;
type SqliteValueTag = BytesOrIntegerOrNullOrRealOrStringTag;
type SqliteValuePayload = BytesOrIntegerOrNullOrRealOrStringPayload;
type SqliteError = HostSqlitePrepareErr;
type SqliteBindings = AnonStruct46;

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
    static SQLITE_CONNECTIONS: RefCell<Vec<(CString, *mut libsqlite3_sys::sqlite3)>> =
        const { RefCell::new(Vec::new()) };
}

fn box_sqlite_stmt(stmt: SqliteStatement, roc_host: &RocHost) -> *mut u64 {
    let raw: *mut SqliteStatement = Box::into_raw(Box::new(stmt));
    let boxed = allocate_box(
        core::mem::size_of::<u64>(),
        SQLITE_STMT_BOX_ALIGN,
        false,
        roc_host,
    );
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
    decref_box_with(
        handle as RocBox,
        SQLITE_STMT_BOX_ALIGN,
        // The boxed payload is a raw `u64` (a pointer to our SqliteStatement),
        // not a Roc-refcounted value — this must match the `false` passed to
        // `allocate_box` in `box_sqlite_stmt`, independent of the teardown callback.
        false,
        Some(drop_sqlite_stmt),
        roc_host,
    );
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

fn sqlite_get_connection(path: &str) -> Result<*mut libsqlite3_sys::sqlite3, (c_int, String)> {
    SQLITE_CONNECTIONS.with(|cell| {
        for (conn_path, connection) in cell.borrow().iter() {
            if conn_path.as_bytes() == path.as_bytes() {
                return Ok(*connection);
            }
        }

        let cpath = CString::new(path).map_err(|_| {
            (
                libsqlite3_sys::SQLITE_ERROR,
                "database path contained an interior nul byte".to_string(),
            )
        })?;
        let mut connection: *mut libsqlite3_sys::sqlite3 = core::ptr::null_mut();
        let flags = libsqlite3_sys::SQLITE_OPEN_CREATE
            | libsqlite3_sys::SQLITE_OPEN_READWRITE
            | libsqlite3_sys::SQLITE_OPEN_NOMUTEX;
        let err = unsafe {
            libsqlite3_sys::sqlite3_open_v2(
                cpath.as_ptr(),
                &mut connection,
                flags,
                core::ptr::null(),
            )
        };
        if err != libsqlite3_sys::SQLITE_OK {
            let message = sqlite_errmsg(connection, err);
            return Err((err, message));
        }

        cell.borrow_mut().push((cpath, connection));
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
        payload: SqliteHostBindResultPayload {
            ok: ManuallyDrop::new(()),
        },
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

#[no_mangle]
pub extern "C" fn hosted_sqlite_prepare(path: RocStr, query: RocStr) -> SqliteHostPrepareResult {
    let roc_host = roc_host();
    let path_string = path.as_str().to_owned();
    let query_string = query.as_str().to_owned();
    path.decref(roc_host);
    query.decref(roc_host);

    let connection = match sqlite_get_connection(&path_string) {
        Ok(connection) => connection,
        Err((code, message)) => {
            return try_sqlite_prepare_err(sqlite_error(code, &message, roc_host));
        }
    };

    let mut stmt: *mut libsqlite3_sys::sqlite3_stmt = core::ptr::null_mut();
    let err = unsafe {
        libsqlite3_sys::sqlite3_prepare_v2(
            connection,
            query_string.as_ptr() as *const c_char,
            query_string.len() as c_int,
            &mut stmt,
            core::ptr::null_mut(),
        )
    };
    if err != libsqlite3_sys::SQLITE_OK {
        let message = sqlite_errmsg(connection, err);
        return try_sqlite_prepare_err(sqlite_error(err, &message, roc_host));
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
        decref_anon_struct46(*binding, roc_host);
    }
    bindings.decref(roc_host);
    release_sqlite_stmt(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_sqlite_columns(handle: *mut u64) -> RocList<RocStr> {
    let roc_host = roc_host();
    let stmt = unsafe { sqlite_stmt_ref(handle) };
    let count = unsafe { libsqlite3_sys::sqlite3_column_count(stmt.stmt) }.max(0) as usize;
    let list = RocList::<RocStr>::allocate(count, roc_host);
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

// ============================================================================
// TCP
//
// `Tcp.Stream` (a `Box(U64)`) is represented by the generated glue as `*mut u64`:
// a boxed u64 holding a raw `*mut BufReader<TcpStream>`. The box is refcounted
// with `allocate_box`/`decref_box_with`; closing the socket happens in
// `drop_tcp_stream` when the last reference is released. Each host fn that takes
// a handle calls `release_tcp_stream` before returning to balance the incref Roc
// performs when the stream stays live.
//
// Errors cross the boundary as a `RocStr` carrying either "ErrorKind::<Variant>"
// (mapped back to a tag union in Tcp.roc) or "UnexpectedEof"; the Roc side parses
// them into `ConnectErr`/`StreamErr`.
// ----------------------------------------------------------------------------

const TCP_STREAM_BOX_ALIGN: usize = core::mem::align_of::<u64>();

fn box_tcp_stream(stream: BufReader<TcpStream>, roc_host: &RocHost) -> *mut u64 {
    let raw: *mut BufReader<TcpStream> = Box::into_raw(Box::new(stream));
    let boxed = allocate_box(
        core::mem::size_of::<u64>(),
        TCP_STREAM_BOX_ALIGN,
        false,
        roc_host,
    );
    unsafe {
        *(boxed as *mut u64) = raw as u64;
    }
    boxed as *mut u64
}

unsafe fn tcp_stream_ref<'a>(handle: *mut u64) -> &'a mut BufReader<TcpStream> {
    &mut *(*handle as *mut BufReader<TcpStream>)
}

extern "C" fn drop_tcp_stream(data_ptr: *mut c_void, _roc_host: *mut RocHost) {
    unsafe {
        let raw = *(data_ptr as *mut u64) as *mut BufReader<TcpStream>;
        if !raw.is_null() {
            drop(Box::from_raw(raw));
        }
    }
}

fn release_tcp_stream(handle: *mut u64, roc_host: &RocHost) {
    decref_box_with(
        handle as RocBox,
        TCP_STREAM_BOX_ALIGN,
        // The boxed payload is a raw `u64` (a pointer to our BufReader), not a
        // Roc-refcounted value — must match the `false` passed to `allocate_box`.
        false,
        Some(drop_tcp_stream),
        roc_host,
    );
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
        io::ErrorKind::OutOfMemory => "ErrorKind::OutOfMemory".to_string(),
        io::ErrorKind::BrokenPipe => "ErrorKind::BrokenPipe".to_string(),
        other => format!("{:?}", other),
    };
    RocStr::from_str(&message, roc_host)
}

// `BufRead::read_until` ported from `roc_file::read_until`, accumulating into a
// plain Vec (the delimiter is included as the last byte when found).
fn tcp_read_until_impl(stream: &mut BufReader<TcpStream>, delim: u8) -> io::Result<Vec<u8>> {
    let mut buffer = Vec::new();
    loop {
        let (done, used) = {
            let available = match stream.fill_buf() {
                Ok(n) => n,
                Err(ref e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e),
            };
            match available.iter().position(|&b| b == delim) {
                Some(i) => {
                    buffer.extend_from_slice(&available[..=i]);
                    (true, i + 1)
                }
                None => {
                    buffer.extend_from_slice(available);
                    (false, available.len())
                }
            }
        };
        stream.consume(used);
        if done || used == 0 {
            return Ok(buffer);
        }
    }
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
        payload: TcpHostWriteResultPayload {
            ok: ManuallyDrop::new(()),
        },
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

#[no_mangle]
pub extern "C" fn hosted_tcp_connect(host: RocStr, port: u16) -> TcpHostConnectResult {
    let roc_host = roc_host();
    let host_string = host.as_str().to_owned();
    host.decref(roc_host);

    match TcpStream::connect((host_string.as_str(), port)) {
        Ok(stream) => {
            let handle = box_tcp_stream(BufReader::new(stream), roc_host);
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
        let stream = unsafe { tcp_stream_ref(handle) };
        let mut chunk = stream.take(bytes_to_read);
        match chunk.fill_buf() {
            Ok(received) => {
                let received = received.to_vec();
                stream.consume(received.len());
                try_tcp_read_ok(RocListWith::<u8, false>::from_slice(&received, roc_host))
            }
            Err(err) => try_tcp_read_err(to_tcp_stream_err(err, roc_host)),
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
        let stream = unsafe { tcp_stream_ref(handle) };
        let mut buffer = Vec::with_capacity(bytes_to_read as usize);
        let mut chunk = stream.take(bytes_to_read);
        match chunk.read_to_end(&mut buffer) {
            Ok(read) => {
                if (read as u64) < bytes_to_read {
                    try_tcp_read_err(RocStr::from_str("UnexpectedEof", roc_host))
                } else {
                    try_tcp_read_ok(RocListWith::<u8, false>::from_slice(&buffer, roc_host))
                }
            }
            Err(err) => try_tcp_read_err(to_tcp_stream_err(err, roc_host)),
        }
    };
    release_tcp_stream(handle, roc_host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_tcp_read_until(handle: *mut u64, byte: u8) -> TcpHostReadUntilResult {
    let roc_host = roc_host();
    let result = {
        let stream = unsafe { tcp_stream_ref(handle) };
        match tcp_read_until_impl(stream, byte) {
            Ok(buffer) => try_tcp_read_ok(RocListWith::<u8, false>::from_slice(&buffer, roc_host)),
            Err(err) => try_tcp_read_err(to_tcp_stream_err(err, roc_host)),
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
        let stream = unsafe { tcp_stream_ref(handle) };
        match stream.get_mut().write_all(msg.as_slice()) {
            Ok(()) => try_tcp_write_ok(),
            Err(err) => try_tcp_write_err(to_tcp_stream_err(err, roc_host)),
        }
    };
    msg.decref(roc_host);
    release_tcp_stream(handle, roc_host);
    result
}

// ============================================================================
// HTTP (outbound)
//
// A single host effect, `hosted_http_send_request`, takes a fully-marshalled
// request record and returns a response record. Requests run on a thread-local
// current-thread tokio runtime driving a hyper client over a rustls (ring)
// TLS connector seeded with the system's native root certificates.
//
// This runs on a `spawn_blocking` thread (the server calls `respond!` there),
// so building a nested current-thread runtime here does not conflict with the
// server's multi-thread runtime.
//
// Transport failures are surfaced to Roc as reserved status+body sentinels
// (matching the checks in Http.roc's `send!`):
//   * 408 + "Timeout"        -> request exceeded its timeout
//   * 500 + "NetworkError"   -> could not initialise the TLS connector
//   * 500 + "BadBody"        -> response body could not be collected
//   * 500 + "OTHER ERROR\n…" -> any other transport/build error (detail follows)
// ----------------------------------------------------------------------------

// The generated glue names the response/header records by anonymous-struct
// number; alias them to stable semantic names (the response also has the
// generator's stable `HostHttpSendRequest` alias).
type HttpResponse = HostHttpSendRequest;
type HttpHeader = AnonStruct36;

thread_local! {
    static TOKIO_RUNTIME: tokio::runtime::Runtime = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .expect("failed to build tokio runtime");
}

// Numeric method tags must match `to_host_method` in platform/InternalHttp.roc.
fn as_hyper_method(method: u8, method_ext: &str) -> Option<hyper::Method> {
    match method {
        0 => Some(hyper::Method::CONNECT),
        1 => Some(hyper::Method::DELETE),
        2 => hyper::Method::from_bytes(method_ext.as_bytes()).ok(),
        3 => Some(hyper::Method::GET),
        4 => Some(hyper::Method::HEAD),
        5 => Some(hyper::Method::OPTIONS),
        6 => Some(hyper::Method::PATCH),
        7 => Some(hyper::Method::POST),
        8 => Some(hyper::Method::PUT),
        9 => Some(hyper::Method::TRACE),
        _ => None,
    }
}

fn http_sentinel_response(status: u16, body: &[u8], roc_host: &RocHost) -> HttpResponse {
    HttpResponse {
        body: RocListWith::<u8, false>::from_slice(body, roc_host),
        headers: RocList::empty(),
        status,
    }
}

fn build_hyper_request(
    args: &HostHttpSendRequestArgs,
) -> Result<hyper::Request<http_body_util::Full<bytes::Bytes>>, String> {
    let method = as_hyper_method(args.method, args.method_ext.as_str())
        .ok_or_else(|| "invalid HTTP method".to_string())?;
    let mut builder = hyper::Request::builder()
        .method(method)
        .uri(args.uri.as_str());

    // Default to text/plain unless the caller already set a Content-Type.
    let mut has_content_type = false;
    for header in args.headers.as_slice() {
        builder = builder.header(header._0.as_str(), header._1.as_str());
        if header._0.as_str().eq_ignore_ascii_case("Content-Type") {
            has_content_type = true;
        }
    }
    if !has_content_type {
        builder = builder.header("Content-Type", "text/plain");
    }

    let body = http_body_util::Full::new(bytes::Bytes::from(args.body.as_slice().to_vec()));
    builder.body(body).map_err(|err| err.to_string())
}

fn build_roc_headers(pairs: &[(String, String)], roc_host: &RocHost) -> RocList<HttpHeader> {
    let list = RocList::<HttpHeader>::allocate(pairs.len(), roc_host);
    for (index, (name, value)) in pairs.iter().enumerate() {
        let header = HttpHeader {
            _0: RocStr::from_str(name, roc_host),
            _1: RocStr::from_str(value, roc_host),
        };
        unsafe {
            list.elements.add(index).write(header);
        }
    }
    list
}

async fn async_send_request(
    request: hyper::Request<http_body_util::Full<bytes::Bytes>>,
    roc_host: &RocHost,
) -> HttpResponse {
    use http_body_util::BodyExt;
    use hyper_rustls::HttpsConnectorBuilder;
    use hyper_util::client::legacy::Client;
    use hyper_util::rt::TokioExecutor;

    let https = match HttpsConnectorBuilder::new().with_native_roots() {
        Ok(builder) => builder.https_or_http().enable_http1().build(),
        Err(_) => return http_sentinel_response(500, b"NetworkError", roc_host),
    };

    let client: Client<_, http_body_util::Full<bytes::Bytes>> =
        Client::builder(TokioExecutor::new()).build(https);

    match client.request(request).await {
        Ok(response) => {
            let status = response.status().as_u16();
            let pairs: Vec<(String, String)> = response
                .headers()
                .iter()
                .map(|(name, value)| {
                    (
                        name.as_str().to_string(),
                        value.to_str().unwrap_or_default().to_string(),
                    )
                })
                .collect();

            match response.into_body().collect().await {
                Ok(collected) => {
                    let bytes = collected.to_bytes();
                    HttpResponse {
                        body: RocListWith::<u8, false>::from_slice(&bytes, roc_host),
                        headers: build_roc_headers(&pairs, roc_host),
                        status,
                    }
                }
                Err(_) => http_sentinel_response(500, b"BadBody", roc_host),
            }
        }
        Err(err) => {
            let detail = format!("OTHER ERROR\n{}", err);
            http_sentinel_response(500, detail.as_bytes(), roc_host)
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_http_send_request(args: HostHttpSendRequestArgs) -> HttpResponse {
    let roc_host = roc_host();
    let timeout_ms = args.timeout_ms;

    // Build the hyper request from the borrowed args, then release the owned
    // Roc values (the request has copied everything it needs).
    let request_result = build_hyper_request(&args);
    args.body.decref(roc_host);
    for header in args.headers.as_slice() {
        decref_anon_struct36(*header, roc_host);
    }
    args.headers.decref(roc_host);
    args.method_ext.decref(roc_host);
    args.uri.decref(roc_host);

    let request = match request_result {
        Ok(request) => request,
        Err(err) => {
            return http_sentinel_response(
                500,
                format!("OTHER ERROR\n{}", err).as_bytes(),
                roc_host,
            )
        }
    };

    TOKIO_RUNTIME.with(|rt| {
        if timeout_ms > 0 {
            rt.block_on(async {
                match tokio::time::timeout(
                    std::time::Duration::from_millis(timeout_ms),
                    async_send_request(request, roc_host),
                )
                .await
                {
                    Ok(response) => response,
                    Err(_) => http_sentinel_response(408, b"Timeout", roc_host),
                }
            })
        } else {
            rt.block_on(async_send_request(request, roc_host))
        }
    })
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
