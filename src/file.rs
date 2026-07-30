use core::ffi::c_void;
use core::mem::ManuallyDrop;
use std::fs;
use std::io::{self, BufRead, BufReader, Read};
use std::sync::{Mutex, OnceLock};

use crate::abi::{
    io_err_from_io, roc_host, FileBoolResult, FileBoolResultPayload, FileBoolResultTag,
    FileBytesResult, FileBytesResultPayload, FileBytesResultTag, FileDeleteResult,
    FileDeleteResultPayload, FileDeleteResultTag, FileReaderLineResult,
    FileReaderLineResultPayload, FileReaderLineResultTag, FileReaderOpenResult,
    FileReaderOpenResultPayload, FileReaderOpenResultTag, FileSizeResult, FileSizeResultPayload,
    FileSizeResultTag, FileStrResult, FileStrResultPayload, FileStrResultTag, FileTimeResult,
    FileTimeResultPayload, FileTimeResultTag, FileWriteBytesResult, FileWriteBytesResultPayload,
    FileWriteBytesResultTag, FileWriteUtf8Result, FileWriteUtf8ResultPayload,
    FileWriteUtf8ResultTag,
};
use crate::capability::{try_lock, CapabilityLockError};
use crate::host_resource::{
    DeallocRoute, HostResourceHeap, LookupError, ReserveError, ResourceReservation,
};
use crate::path::{path_buf_from_raw_path, IntoRawPath};
use crate::roc_platform_abi::*;
use crate::time::nanos_since_unix_epoch;
#[cfg(unix)]
use crate::time::system_time_from_unix_parts;

const MAX_MATERIALIZED_FILE_BYTES: u64 = 8 * 1024 * 1024;
const MAX_FILE_READER_BUFFER_BYTES: u64 = 1024 * 1024;

fn file_materialization_limit_error(roc_host: &RocHost) -> IOErr {
    crate::abi::io_err_other(
        "file read exceeded the 8 MiB materialization limit; use a buffered reader",
        roc_host,
    )
}

fn read_file_bounded(path: std::path::PathBuf) -> io::Result<Vec<u8>> {
    let file = fs::File::open(path)?;
    let mut bytes = Vec::new();
    file.take(MAX_MATERIALIZED_FILE_BYTES + 1)
        .read_to_end(&mut bytes)?;
    Ok(bytes)
}

fn try_file_bytes_ok(value: RocListWith<u8, false>) -> FileBytesResult {
    FileBytesResult {
        payload: FileBytesResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileBytesResultTag::Ok,
    }
}

fn try_file_bytes_err(error: IOErr) -> FileBytesResult {
    FileBytesResult {
        payload: FileBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileBytesResultTag::Err,
    }
}

fn try_file_reader_ok(handle: *mut u64) -> FileReaderOpenResult {
    FileReaderOpenResult {
        payload: FileReaderOpenResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: FileReaderOpenResultTag::Ok,
    }
}

fn try_file_reader_err(error: IOErr) -> FileReaderOpenResult {
    FileReaderOpenResult {
        payload: FileReaderOpenResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileReaderOpenResultTag::Err,
    }
}

fn try_file_reader_line_ok(value: RocListWith<u8, false>) -> FileReaderLineResult {
    FileReaderLineResult {
        payload: FileReaderLineResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileReaderLineResultTag::Ok,
    }
}

fn try_file_reader_line_err(error: IOErr) -> FileReaderLineResult {
    FileReaderLineResult {
        payload: FileReaderLineResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileReaderLineResultTag::Err,
    }
}

fn try_file_write_bytes_ok() -> FileWriteBytesResult {
    FileWriteBytesResult {
        payload: FileWriteBytesResultPayload { ok: [] },
        tag: FileWriteBytesResultTag::Ok,
    }
}

fn try_file_write_bytes_err(error: IOErr) -> FileWriteBytesResult {
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

fn try_file_str_err(error: IOErr) -> FileStrResult {
    FileStrResult {
        payload: FileStrResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileStrResultTag::Err,
    }
}

fn try_file_write_utf8_ok() -> FileWriteUtf8Result {
    FileWriteUtf8Result {
        payload: FileWriteUtf8ResultPayload { ok: [] },
        tag: FileWriteUtf8ResultTag::Ok,
    }
}

fn try_file_write_utf8_err(error: IOErr) -> FileWriteUtf8Result {
    FileWriteUtf8Result {
        payload: FileWriteUtf8ResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileWriteUtf8ResultTag::Err,
    }
}

fn try_file_delete_ok() -> FileDeleteResult {
    FileDeleteResult {
        payload: FileDeleteResultPayload { ok: [] },
        tag: FileDeleteResultTag::Ok,
    }
}

fn try_file_delete_err(error: IOErr) -> FileDeleteResult {
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

fn try_file_size_err(error: IOErr) -> FileSizeResult {
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

fn try_file_bool_err(error: IOErr) -> FileBoolResult {
    FileBoolResult {
        payload: FileBoolResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileBoolResultTag::Err,
    }
}

fn try_file_time_ok(value: i128) -> FileTimeResult {
    FileTimeResult {
        payload: FileTimeResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileTimeResultTag::Ok,
    }
}

fn try_file_time_err(error: IOErr) -> FileTimeResult {
    FileTimeResult {
        payload: FileTimeResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileTimeResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_delete(path: HostFileDeleteArgs) -> FileDeleteResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_delete_err(io_err_from_io(&error, roc_host)),
    };
    match fs::remove_file(path) {
        Ok(()) => try_file_delete_ok(),
        Err(error) => try_file_delete_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_hard_link(
    original_path: HostFileHardLinkArg0,
    link_path: HostFileHardLinkArg1,
) -> FileWriteUtf8Result {
    let roc_host = roc_host();
    let original_path = match path_buf_from_raw_path(original_path, roc_host) {
        Ok(path) => path,
        Err(error) => {
            // The second hosted argument is also owned even when the first is invalid.
            let _ = path_buf_from_raw_path(link_path, roc_host);
            return try_file_write_utf8_err(io_err_from_io(&error, roc_host));
        }
    };
    let link_path = match path_buf_from_raw_path(link_path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_write_utf8_err(io_err_from_io(&error, roc_host)),
    };

    match fs::hard_link(original_path, link_path) {
        Ok(()) => try_file_write_utf8_ok(),
        Err(error) => try_file_write_utf8_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_rename(
    from: HostFileRenameArg0,
    to: HostFileRenameArg1,
) -> FileWriteUtf8Result {
    let roc_host = roc_host();
    let from = match path_buf_from_raw_path(from, roc_host) {
        Ok(path) => path,
        Err(error) => {
            // The second hosted argument is also owned even when the first is invalid.
            let _ = path_buf_from_raw_path(to, roc_host);
            return try_file_write_utf8_err(io_err_from_io(&error, roc_host));
        }
    };
    let to = match path_buf_from_raw_path(to, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_write_utf8_err(io_err_from_io(&error, roc_host)),
    };

    match fs::rename(from, to) {
        Ok(()) => try_file_write_utf8_ok(),
        Err(error) => try_file_write_utf8_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_bytes(path: HostFileReadBytesArgs) -> FileBytesResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_bytes_err(io_err_from_io(&error, roc_host)),
    };
    match read_file_bounded(path) {
        Ok(bytes) if bytes.len() as u64 <= MAX_MATERIALIZED_FILE_BYTES => {
            try_file_bytes_ok(unsafe {
                // SAFETY: the returned Roc list owns a copy of `bytes`.
                RocListWith::<u8, false>::from_slice(&bytes, roc_host)
            })
        }
        Ok(_) => try_file_bytes_err(file_materialization_limit_error(roc_host)),
        Err(error) => try_file_bytes_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_utf8(path: HostFileReadUtf8Args) -> FileStrResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_str_err(io_err_from_io(&error, roc_host)),
    };
    match read_file_bounded(path) {
        Ok(bytes) if bytes.len() as u64 <= MAX_MATERIALIZED_FILE_BYTES => {
            match String::from_utf8(bytes) {
                Ok(content) => try_file_str_ok(RocStr::from_str(&content, roc_host)),
                Err(error) => try_file_str_err(io_err_from_io(
                    &io::Error::new(io::ErrorKind::InvalidData, error),
                    roc_host,
                )),
            }
        }
        Ok(_) => try_file_str_err(file_materialization_limit_error(roc_host)),
        Err(error) => try_file_str_err(io_err_from_io(&error, roc_host)),
    }
}

const MAX_OPEN_FILE_READERS: usize = 64;

type FileReaderResource = Mutex<BufReader<fs::File>>;

static FILE_READERS: OnceLock<HostResourceHeap<FileReaderResource>> = OnceLock::new();

fn file_readers() -> &'static HostResourceHeap<FileReaderResource> {
    FILE_READERS.get_or_init(|| HostResourceHeap::new(MAX_OPEN_FILE_READERS))
}

fn reserve_file_reader() -> Result<ResourceReservation<'static, FileReaderResource>, ReserveError> {
    file_readers().reserve()
}

unsafe fn file_reader_ref(handle: *mut u64) -> Result<&'static FileReaderResource, LookupError> {
    unsafe { file_readers().get(handle) }
}

fn release_file_reader(handle: *mut u64, roc_host: &RocHost) {
    // SAFETY: hosted arguments transfer one owned Roc reference. Final release
    // routes through the resource heap and closes the file.
    unsafe { decref_box(handle as RocBox, roc_host) };
}

pub(crate) fn route_resource_dealloc(ptr: *mut c_void) -> DeallocRoute {
    match FILE_READERS.get() {
        Some(heap) => heap.route_dealloc(ptr),
        None => DeallocRoute::NotOwned,
    }
}

pub(crate) fn contains_resource_address(ptr: *const c_void) -> bool {
    FILE_READERS
        .get()
        .is_some_and(|heap| heap.contains_address(ptr))
}

pub(crate) fn active_resources() -> usize {
    FILE_READERS.get().map_or(0, HostResourceHeap::active)
}

pub(crate) fn resource_high_water() -> usize {
    FILE_READERS.get().map_or(0, HostResourceHeap::high_water)
}

#[no_mangle]
pub extern "C" fn hosted_file_open_reader(
    path: HostFileOpenReaderArg0,
    capacity: u64,
) -> FileReaderOpenResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_reader_err(io_err_from_io(&error, roc_host)),
    };
    if capacity > MAX_FILE_READER_BUFFER_BYTES {
        return try_file_reader_err(crate::abi::io_err_other(
            "file reader buffer capacity cannot exceed 1 MiB",
            roc_host,
        ));
    }
    let reservation = match reserve_file_reader() {
        Ok(reservation) => reservation,
        Err(ReserveError::Capacity) => {
            return try_file_reader_err(crate::abi::io_err_other(
                "file reader capacity is exhausted",
                roc_host,
            ));
        }
    };
    match fs::File::open(path) {
        Ok(file) => {
            let reader = if capacity == 0 {
                BufReader::new(file)
            } else {
                BufReader::with_capacity(capacity as usize, file)
            };
            try_file_reader_ok(reservation.insert(Mutex::new(reader)))
        }
        Err(error) => try_file_reader_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_line(handle: *mut u64) -> FileReaderLineResult {
    let roc_host = roc_host();
    let result = {
        match unsafe { file_reader_ref(handle) } {
            Ok(reader) => match try_lock(reader) {
                Ok(mut reader) => {
                    let mut buffer = Vec::new();
                    let read = reader
                        .by_ref()
                        .take(MAX_MATERIALIZED_FILE_BYTES + 1)
                        .read_until(b'\n', &mut buffer);
                    match read {
                        Ok(_) if buffer.len() as u64 <= MAX_MATERIALIZED_FILE_BYTES => {
                            try_file_reader_line_ok(unsafe {
                                RocListWith::<u8, false>::from_slice(&buffer, roc_host)
                            })
                        }
                        Ok(_) => {
                            try_file_reader_line_err(file_materialization_limit_error(roc_host))
                        }
                        Err(error) => try_file_reader_line_err(io_err_from_io(&error, roc_host)),
                    }
                }
                Err(CapabilityLockError::Busy) => try_file_reader_line_err(
                    crate::abi::io_err_other("file reader is already in use", roc_host),
                ),
                Err(CapabilityLockError::Poisoned) => try_file_reader_line_err(
                    crate::abi::io_err_other("file reader is unavailable", roc_host),
                ),
            },
            Err(_) => try_file_reader_line_err(crate::abi::io_err_other(
                "file reader handle is stale or invalid",
                roc_host,
            )),
        }
    };
    release_file_reader(handle, roc_host);
    result
}

fn file_metadata(path: impl IntoRawPath, roc_host: &RocHost) -> io::Result<fs::Metadata> {
    fs::metadata(path_buf_from_raw_path(path, roc_host)?)
}

#[no_mangle]
pub extern "C" fn hosted_file_size_in_bytes(path: HostFileSizeInBytesArgs) -> FileSizeResult {
    let roc_host = roc_host();
    match file_metadata(path, roc_host) {
        Ok(metadata) => try_file_size_ok(metadata.len()),
        Err(error) => try_file_size_err(io_err_from_io(&error, roc_host)),
    }
}

fn file_permission_bit(path: impl IntoRawPath, roc_host: &RocHost, bit: u32) -> io::Result<bool> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        let path = path_buf_from_raw_path(path, roc_host)?;
        match bit {
            0o111 => Ok(path.metadata()?.permissions().mode() & bit != 0),
            0o400 => fs::File::open(path).map(|_| true),
            0o200 => fs::OpenOptions::new().write(true).open(path).map(|_| true),
            _ => unreachable!("permission query uses a known access kind"),
        }
    }

    #[cfg(not(unix))]
    {
        let path = path_buf_from_raw_path(path, roc_host)?;
        match bit {
            0o111 => {
                let extension = path
                    .extension()
                    .and_then(std::ffi::OsStr::to_str)
                    .unwrap_or_default();
                Ok(["exe", "com", "bat", "cmd"]
                    .iter()
                    .any(|candidate| extension.eq_ignore_ascii_case(candidate)))
            }
            0o400 => fs::File::open(path).map(|_| true),
            0o200 => fs::OpenOptions::new().write(true).open(path).map(|_| true),
            _ => unreachable!("permission query uses a known access kind"),
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_executable(path: HostFileIsExecutableArgs) -> FileBoolResult {
    let roc_host = roc_host();
    match file_permission_bit(path, roc_host, 0o111) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_readable(path: HostFileIsReadableArgs) -> FileBoolResult {
    let roc_host = roc_host();
    match file_permission_bit(path, roc_host, 0o400) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_writable(path: HostFileIsWritableArgs) -> FileBoolResult {
    let roc_host = roc_host();
    match file_permission_bit(path, roc_host, 0o200) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(io_err_from_io(&error, roc_host)),
    }
}

fn file_time(
    path: impl IntoRawPath,
    roc_host: &RocHost,
    read_time: fn(&fs::Metadata) -> io::Result<std::time::SystemTime>,
) -> io::Result<i128> {
    let metadata = file_metadata(path, roc_host)?;
    read_time(&metadata).and_then(nanos_since_unix_epoch)
}

fn file_created_time(metadata: &fs::Metadata) -> io::Result<std::time::SystemTime> {
    match metadata.created() {
        Ok(time) => Ok(time),
        Err(error) => {
            #[cfg(unix)]
            {
                if error.kind() == io::ErrorKind::Unsupported {
                    use std::os::unix::fs::MetadataExt;

                    return system_time_from_unix_parts(metadata.ctime(), metadata.ctime_nsec());
                }
            }

            Err(error)
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_time_accessed(path: HostFileTimeAccessedArgs) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::accessed) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_time_created(path: HostFileTimeCreatedArgs) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, file_created_time) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_time_modified(path: HostFileTimeModifiedArgs) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::modified) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_write_bytes(
    path: HostFileWriteBytesArg0,
    bytes: RocListWith<u8, false>,
) -> FileWriteBytesResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => {
            unsafe { bytes.decref(roc_host) };
            return try_file_write_bytes_err(io_err_from_io(&error, roc_host));
        }
    };
    let result = fs::write(path, bytes.as_slice());
    unsafe { bytes.decref(roc_host) };

    match result {
        Ok(()) => try_file_write_bytes_ok(),
        Err(error) => try_file_write_bytes_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_write_utf8(
    path: HostFileWriteUtf8Arg0,
    content: RocStr,
) -> FileWriteUtf8Result {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => {
            unsafe { content.decref(roc_host) };
            return try_file_write_utf8_err(io_err_from_io(&error, roc_host));
        }
    };
    let content_string = content.as_str().to_owned();
    unsafe { content.decref(roc_host) };

    match fs::write(path, content_string) {
        Ok(()) => try_file_write_utf8_ok(),
        Err(error) => try_file_write_utf8_err(io_err_from_io(&error, roc_host)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nanos_since_unix_epoch_returns_zero_for_epoch() {
        assert_eq!(nanos_since_unix_epoch(std::time::UNIX_EPOCH).unwrap(), 0);
    }

    #[cfg(unix)]
    #[test]
    fn unix_timestamp_parts_convert_from_epoch() {
        assert_eq!(
            nanos_since_unix_epoch(system_time_from_unix_parts(1, 2).unwrap()).unwrap(),
            1_000_000_002
        );
    }

    #[test]
    fn roc_host_vtable_final_dealloc_releases_file_reader_slot() {
        let baseline = active_resources();
        let file = fs::File::open("Cargo.toml").unwrap();
        let handle = reserve_file_reader()
            .unwrap()
            .insert(Mutex::new(BufReader::new(file)));
        assert_eq!(active_resources(), baseline + 1);
        assert_eq!(
            (handle as usize) % core::mem::align_of::<u64>(),
            0,
            "Box(U64) payload must have its generated ABI alignment"
        );

        let mut host = make_roc_host(core::ptr::null_mut());
        host.roc_dealloc = crate::abi::routed_roc_dealloc;
        // SAFETY: the reservation returned one owned Roc Box reference.
        unsafe { decref_box(handle as RocBox, &host) };
        assert_eq!(active_resources(), baseline);
    }
}
