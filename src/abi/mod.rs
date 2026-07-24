use core::ffi::c_void;
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::roc_platform_abi::*;

// RustGlue assigns numbered names (TryTypeN, IOErrTypeN, ...) to anonymous Roc
// records and result types, and those numbers shift whenever a module is added.
// These aliases are keyed to generated semantic names where possible so effect
// modules can talk about platform concepts rather than glue numbers.
pub(crate) type StdoutUnitResult = HostStdoutLineResult;
pub(crate) type StdoutUnitResultPayload = HostStdoutLineResultPayload;
pub(crate) type StdoutUnitResultTag = HostStdoutLineResultTag;
pub(crate) type StdoutBytesResult = HostStdoutWriteBytesResult;
pub(crate) type StdoutBytesResultPayload = HostStdoutWriteBytesResultPayload;
pub(crate) type StdoutBytesResultTag = HostStdoutWriteBytesResultTag;

pub(crate) type StderrUnitResult = HostStderrLineResult;
pub(crate) type StderrUnitResultPayload = HostStderrLineResultPayload;
pub(crate) type StderrUnitResultTag = HostStderrLineResultTag;
pub(crate) type StderrBytesResult = HostStderrWriteBytesResult;
pub(crate) type StderrBytesResultPayload = HostStderrWriteBytesResultPayload;
pub(crate) type StderrBytesResultTag = HostStderrWriteBytesResultTag;

pub(crate) type DirUnitResult = HostDirCreateResult;
pub(crate) type DirUnitResultPayload = HostDirCreateResultPayload;
pub(crate) type DirUnitResultTag = HostDirCreateResultTag;
pub(crate) type DirListResult = HostDirListResult;
pub(crate) type DirListResultPayload = HostDirListResultPayload;
pub(crate) type DirListResultTag = HostDirListResultTag;
pub(crate) type RawPath = HostDirListOk;

pub(crate) type EnvUnixPathResult = HostEnvCwdUnixResult;
pub(crate) type EnvUnixPathResultPayload = HostEnvCwdUnixResultPayload;
pub(crate) type EnvUnixPathResultTag = HostEnvCwdUnixResultTag;
pub(crate) type EnvWindowsPathResult = HostEnvCwdWindowsResult;
pub(crate) type EnvWindowsPathResultPayload = HostEnvCwdWindowsResultPayload;
pub(crate) type EnvWindowsPathResultTag = HostEnvCwdWindowsResultTag;
pub(crate) type EnvUnitResult = HostEnvSetCwdResult;
pub(crate) type EnvUnitResultPayload = HostEnvSetCwdResultPayload;
pub(crate) type EnvUnitResultTag = HostEnvSetCwdResultTag;

pub(crate) type FileBytesResult = HostFileReadBytesResult;
pub(crate) type FileBytesResultPayload = HostFileReadBytesResultPayload;
pub(crate) type FileBytesResultTag = HostFileReadBytesResultTag;
pub(crate) type FileStrResult = HostFileReadUtf8Result;
pub(crate) type FileStrResultPayload = HostFileReadUtf8ResultPayload;
pub(crate) type FileStrResultTag = HostFileReadUtf8ResultTag;
pub(crate) type FileReaderOpenResult = HostFileOpenReaderResult;
pub(crate) type FileReaderOpenResultPayload = HostFileOpenReaderResultPayload;
pub(crate) type FileReaderOpenResultTag = HostFileOpenReaderResultTag;
pub(crate) type FileReaderLineResult = HostFileReadLineResult;
pub(crate) type FileReaderLineResultPayload = HostFileReadLineResultPayload;
pub(crate) type FileReaderLineResultTag = HostFileReadLineResultTag;
pub(crate) type FileSizeResult = HostFileSizeInBytesResult;
pub(crate) type FileSizeResultPayload = HostFileSizeInBytesResultPayload;
pub(crate) type FileSizeResultTag = HostFileSizeInBytesResultTag;
pub(crate) type FileBoolResult = HostFileIsExecutableResult;
pub(crate) type FileBoolResultPayload = HostFileIsExecutableResultPayload;
pub(crate) type FileBoolResultTag = HostFileIsExecutableResultTag;
pub(crate) type FileTimeResult = HostFileTimeAccessedResult;
pub(crate) type FileTimeResultPayload = HostFileTimeAccessedResultPayload;
pub(crate) type FileTimeResultTag = HostFileTimeAccessedResultTag;
pub(crate) type FileDeleteResult = HostFileDeleteResult;
pub(crate) type FileDeleteResultPayload = HostFileDeleteResultPayload;
pub(crate) type FileDeleteResultTag = HostFileDeleteResultTag;
pub(crate) type FileWriteBytesResult = HostFileWriteBytesResult;
pub(crate) type FileWriteBytesResultPayload = HostFileWriteBytesResultPayload;
pub(crate) type FileWriteBytesResultTag = HostFileWriteBytesResultTag;
pub(crate) type FileWriteUtf8Result = HostFileWriteUtf8Result;
pub(crate) type FileWriteUtf8ResultPayload = HostFileWriteUtf8ResultPayload;
pub(crate) type FileWriteUtf8ResultTag = HostFileWriteUtf8ResultTag;

pub(crate) type PathTypeResult = HostPathTypeResult;
pub(crate) type PathTypeResultPayload = HostPathTypeResultPayload;
pub(crate) type PathTypeResultTag = HostPathTypeResultTag;
pub(crate) type PathInfo = HostPathTypeOk;

pub(crate) type SqliteHostPrepareResult = HostSqlitePrepareResult;
pub(crate) type SqliteHostPrepareResultPayload = HostSqlitePrepareResultPayload;
pub(crate) type SqliteHostPrepareResultTag = HostSqlitePrepareResultTag;
pub(crate) type SqliteHostBindResult = HostSqliteBindResult;
pub(crate) type SqliteHostBindResultPayload = HostSqliteBindResultPayload;
pub(crate) type SqliteHostBindResultTag = HostSqliteBindResultTag;
pub(crate) type SqliteHostColumnValueResult = HostSqliteColumnValueResult;
pub(crate) type SqliteHostColumnValueResultPayload = HostSqliteColumnValueResultPayload;
pub(crate) type SqliteHostColumnValueResultTag = HostSqliteColumnValueResultTag;
pub(crate) type SqliteHostStepResult = HostSqliteStepResult;
pub(crate) type SqliteHostStepResultPayload = HostSqliteStepResultPayload;
pub(crate) type SqliteHostStepResultTag = HostSqliteStepResultTag;

pub(crate) type TcpHostConnectResult = HostTcpConnectResult;
pub(crate) type TcpHostConnectResultPayload = HostTcpConnectResultPayload;
pub(crate) type TcpHostConnectResultTag = HostTcpConnectResultTag;
pub(crate) type TcpHostReadUpToResult = HostTcpReadUpToResult;
pub(crate) type TcpHostReadUpToResultPayload = HostTcpReadUpToResultPayload;
pub(crate) type TcpHostReadUpToResultTag = HostTcpReadUpToResultTag;
pub(crate) type TcpHostReadExactlyResult = HostTcpReadExactlyResult;
pub(crate) type TcpHostReadUntilResult = HostTcpReadUntilResult;
pub(crate) type TcpHostWriteResult = HostTcpWriteResult;
pub(crate) type TcpHostWriteResultPayload = HostTcpWriteResultPayload;
pub(crate) type TcpHostWriteResultTag = HostTcpWriteResultTag;

pub(crate) type HostIOErrType = IOErr;
pub(crate) type HostIOErrPayloadType = IOErrPayload;
pub(crate) type HostIOErrTagType = IOErrTag;

pub(crate) type ServerConfig = InitForHostOkConfig;
pub(crate) type ServerRequest = RespondForHostArg0;
pub(crate) type ServerResponse = RespondForHost;
pub(crate) type ServerHeader = RespondForHostArg0Headers;
pub(crate) type ServerShutdownReason = ShutdownForHostArg0;

pub(crate) type BodyReadResult = HostRequestBodyReadResult;
pub(crate) type BodyReadResultPayload = HostRequestBodyReadResultPayload;
pub(crate) type BodyReadResultTag = HostRequestBodyReadResultTag;
pub(crate) type BodyReadAllResult = HostRequestBodyReadAllResult;
pub(crate) type BodyReadAllResultPayload = HostRequestBodyReadAllResultPayload;
pub(crate) type BodyReadAllResultTag = HostRequestBodyReadAllResultTag;
pub(crate) type BodyReadValue = HostRequestBodyReadOk;
pub(crate) type BodyReadValuePayload = HostRequestBodyReadOkPayload;
pub(crate) type BodyReadValueTag = HostRequestBodyReadOkTag;
pub(crate) type BodyReadError = HostRequestBodyReadErr;
pub(crate) type BodyReadErrorPayload = HostRequestBodyReadErrPayload;
pub(crate) type BodyReadErrorTag = HostRequestBodyReadErrTag;
pub(crate) type BodyTooLarge = HostRequestBodyReadErrTooLarge;

static DEBUG_OR_EXPECT_CALLED: AtomicBool = AtomicBool::new(false);
static mut ROC_HOST: *mut RocHost = core::ptr::null_mut();

pub(crate) fn set_roc_host(roc_host: *mut RocHost) {
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

pub(crate) fn decref_server_response(value: ServerResponse, roc_host: &RocHost) {
    // SAFETY: `roc_respond_for_host` returned one owned reference for every
    // refcounted field in the response.
    unsafe { value.decref(roc_host) };
}

#[cfg(target_pointer_width = "32")]
unsafe fn write_payload<T, const N: usize>(payload: &mut [u8; N], value: T) {
    debug_assert!(core::mem::size_of::<T>() <= N);
    unsafe { core::ptr::write(payload.as_mut_ptr().cast::<T>(), value) };
}

pub(crate) fn body_read_chunk(bytes: RocListWith<u8, false>) -> BodyReadResult {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut value: BodyReadValue = core::mem::zeroed();
        write_payload(&mut value.payload, bytes);
        value.tag = BodyReadValueTag::Chunk;
        let mut result: BodyReadResult = core::mem::zeroed();
        write_payload(&mut result.payload, value);
        result.tag = BodyReadResultTag::Ok;
        result
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        let value = BodyReadValue {
            payload: BodyReadValuePayload {
                chunk: core::mem::ManuallyDrop::new(bytes),
            },
            tag: BodyReadValueTag::Chunk,
        };
        BodyReadResult {
            payload: BodyReadResultPayload {
                ok: core::mem::ManuallyDrop::new(value),
            },
            tag: BodyReadResultTag::Ok,
        }
    }
}

pub(crate) fn body_read_end() -> BodyReadResult {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut value: BodyReadValue = core::mem::zeroed();
        value.tag = BodyReadValueTag::End;
        let mut result: BodyReadResult = core::mem::zeroed();
        write_payload(&mut result.payload, value);
        result.tag = BodyReadResultTag::Ok;
        result
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        let value = BodyReadValue {
            payload: BodyReadValuePayload { end: [] },
            tag: BodyReadValueTag::End,
        };
        BodyReadResult {
            payload: BodyReadResultPayload {
                ok: core::mem::ManuallyDrop::new(value),
            },
            tag: BodyReadResultTag::Ok,
        }
    }
}

pub(crate) fn body_read_error(error: BodyReadError) -> BodyReadResult {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut result: BodyReadResult = core::mem::zeroed();
        write_payload(&mut result.payload, error);
        result.tag = BodyReadResultTag::Err;
        result
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        BodyReadResult {
            payload: BodyReadResultPayload {
                err: core::mem::ManuallyDrop::new(error),
            },
            tag: BodyReadResultTag::Err,
        }
    }
}

pub(crate) fn body_read_all_ok(bytes: RocListWith<u8, false>) -> BodyReadAllResult {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut result: BodyReadAllResult = core::mem::zeroed();
        write_payload(&mut result.payload, bytes);
        result.tag = BodyReadAllResultTag::Ok;
        result
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        BodyReadAllResult {
            payload: BodyReadAllResultPayload {
                ok: core::mem::ManuallyDrop::new(bytes),
            },
            tag: BodyReadAllResultTag::Ok,
        }
    }
}

pub(crate) fn body_read_all_error(error: BodyReadError) -> BodyReadAllResult {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut result: BodyReadAllResult = core::mem::zeroed();
        write_payload(&mut result.payload, error);
        result.tag = BodyReadAllResultTag::Err;
        result
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        BodyReadAllResult {
            payload: BodyReadAllResultPayload {
                err: core::mem::ManuallyDrop::new(error),
            },
            tag: BodyReadAllResultTag::Err,
        }
    }
}

pub(crate) fn body_error(
    tag: BodyReadErrorTag,
    string: Option<RocStr>,
    too_large: Option<BodyTooLarge>,
) -> BodyReadError {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut error: BodyReadError = core::mem::zeroed();
        if let Some(string) = string {
            write_payload(&mut error.payload, string);
        }
        if let Some(too_large) = too_large {
            write_payload(&mut error.payload, too_large);
        }
        error.tag = tag;
        error
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        let payload = match (string, too_large) {
            (Some(string), None) => BodyReadErrorPayload {
                invalid_body: core::mem::ManuallyDrop::new(string),
            },
            (None, Some(too_large)) => BodyReadErrorPayload {
                too_large: core::mem::ManuallyDrop::new(too_large),
            },
            (None, None) => BodyReadErrorPayload { cancelled: [] },
            (Some(_), Some(_)) => unreachable!("body error has one payload"),
        };
        BodyReadError { payload, tag }
    }
}

pub(crate) fn io_err_other(message: &str, roc_host: &RocHost) -> HostIOErrType {
    HostIOErrType {
        payload: HostIOErrPayloadType {
            other: core::mem::ManuallyDrop::new(RocStr::from_str(message, roc_host)),
        },
        tag: HostIOErrTagType::Other,
    }
}

pub(crate) fn io_err_from_io(error: &io::Error, roc_host: &RocHost) -> HostIOErrType {
    match error.kind() {
        io::ErrorKind::AlreadyExists => HostIOErrType {
            payload: HostIOErrPayloadType { already_exists: [] },
            tag: HostIOErrTagType::AlreadyExists,
        },
        io::ErrorKind::BrokenPipe => HostIOErrType {
            payload: HostIOErrPayloadType { broken_pipe: [] },
            tag: HostIOErrTagType::BrokenPipe,
        },
        io::ErrorKind::Interrupted => HostIOErrType {
            payload: HostIOErrPayloadType { interrupted: [] },
            tag: HostIOErrTagType::Interrupted,
        },
        io::ErrorKind::NotFound => HostIOErrType {
            payload: HostIOErrPayloadType { not_found: [] },
            tag: HostIOErrTagType::NotFound,
        },
        io::ErrorKind::OutOfMemory => HostIOErrType {
            payload: HostIOErrPayloadType { out_of_memory: [] },
            tag: HostIOErrTagType::OutOfMemory,
        },
        io::ErrorKind::PermissionDenied => HostIOErrType {
            payload: HostIOErrPayloadType {
                permission_denied: [],
            },
            tag: HostIOErrTagType::PermissionDenied,
        },
        io::ErrorKind::Unsupported => HostIOErrType {
            payload: HostIOErrPayloadType { unsupported: [] },
            tag: HostIOErrTagType::Unsupported,
        },
        _ => io_err_other(&error.to_string(), roc_host),
    }
}

/// Commands expose `IOErr` directly, so RustGlue emits a distinct nominal type
/// from the `IOErr` nested in File/Dir/etc. effect errors.
pub(crate) fn cmd_io_err_other(message: &str, roc_host: &RocHost) -> HostIOErr {
    HostIOErr {
        payload: HostIOErrPayload {
            other: core::mem::ManuallyDrop::new(RocStr::from_str(message, roc_host)),
        },
        tag: HostIOErrTag::Other,
    }
}

pub(crate) fn cmd_io_err_from_io(error: &io::Error, roc_host: &RocHost) -> HostIOErr {
    match error.kind() {
        io::ErrorKind::AlreadyExists => HostIOErr {
            payload: HostIOErrPayload { already_exists: [] },
            tag: HostIOErrTag::AlreadyExists,
        },
        io::ErrorKind::BrokenPipe => HostIOErr {
            payload: HostIOErrPayload { broken_pipe: [] },
            tag: HostIOErrTag::BrokenPipe,
        },
        io::ErrorKind::Interrupted => HostIOErr {
            payload: HostIOErrPayload { interrupted: [] },
            tag: HostIOErrTag::Interrupted,
        },
        io::ErrorKind::NotFound => HostIOErr {
            payload: HostIOErrPayload { not_found: [] },
            tag: HostIOErrTag::NotFound,
        },
        io::ErrorKind::OutOfMemory => HostIOErr {
            payload: HostIOErrPayload { out_of_memory: [] },
            tag: HostIOErrTag::OutOfMemory,
        },
        io::ErrorKind::PermissionDenied => HostIOErr {
            payload: HostIOErrPayload {
                permission_denied: [],
            },
            tag: HostIOErrTag::PermissionDenied,
        },
        io::ErrorKind::Unsupported => HostIOErr {
            payload: HostIOErrPayload { unsupported: [] },
            tag: HostIOErrTag::Unsupported,
        },
        _ => cmd_io_err_other(&error.to_string(), roc_host),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_host() -> RocHost {
        make_roc_host(core::ptr::null_mut())
    }

    #[test]
    fn io_err_maps_known_error_kinds_to_tags() {
        let host = test_host();

        let cases = [
            (
                io::ErrorKind::AlreadyExists,
                HostIOErrTagType::AlreadyExists,
            ),
            (io::ErrorKind::BrokenPipe, HostIOErrTagType::BrokenPipe),
            (io::ErrorKind::Interrupted, HostIOErrTagType::Interrupted),
            (io::ErrorKind::NotFound, HostIOErrTagType::NotFound),
            (io::ErrorKind::OutOfMemory, HostIOErrTagType::OutOfMemory),
            (
                io::ErrorKind::PermissionDenied,
                HostIOErrTagType::PermissionDenied,
            ),
            (io::ErrorKind::Unsupported, HostIOErrTagType::Unsupported),
        ];

        for (kind, expected) in cases {
            let error = io::Error::from(kind);
            assert_eq!(io_err_from_io(&error, &host).tag, expected);
        }
    }

    #[test]
    fn lifecycle_result_constructors_match_generated_tags() {
        let end = body_read_end();
        assert_eq!(end.tag, BodyReadResultTag::Ok);
        assert_eq!(end.payload_ok().tag, BodyReadValueTag::End);
    }
}
