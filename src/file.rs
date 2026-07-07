use core::ffi::c_void;
use core::mem::ManuallyDrop;
use std::fs;
use std::io::{self, BufRead, BufReader};

use crate::abi::{
    io_err_from_io, path_from_roc_str, roc_host, FileBoolResult, FileBoolResultPayload,
    FileBoolResultTag, FileBytesResult, FileBytesResultPayload, FileBytesResultTag,
    FileDeleteResult, FileDeleteResultPayload, FileDeleteResultTag, FileReaderLineResult,
    FileReaderLineResultPayload, FileReaderLineResultTag, FileReaderOpenResult,
    FileReaderOpenResultPayload, FileReaderOpenResultTag, FileSizeResult, FileSizeResultPayload,
    FileSizeResultTag, FileStrResult, FileStrResultPayload, FileStrResultTag, FileTimeResult,
    FileTimeResultPayload, FileTimeResultTag, FileWriteBytesResult, FileWriteBytesResultPayload,
    FileWriteBytesResultTag, FileWriteUtf8Result, FileWriteUtf8ResultPayload,
    FileWriteUtf8ResultTag,
};
use crate::roc_platform_abi::*;

fn try_file_bytes_ok(value: RocListWith<u8, false>) -> FileBytesResult {
    FileBytesResult {
        payload: FileBytesResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileBytesResultTag::Ok,
    }
}

fn try_file_bytes_err(error: HostIOErr) -> FileBytesResult {
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

fn try_file_reader_err(error: HostIOErr) -> FileReaderOpenResult {
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

fn try_file_reader_line_err(error: HostIOErr) -> FileReaderLineResult {
    FileReaderLineResult {
        payload: FileReaderLineResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileReaderLineResultTag::Err,
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

fn try_file_write_bytes_err(error: HostIOErr) -> FileWriteBytesResult {
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

fn try_file_str_err(error: HostIOErr) -> FileStrResult {
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

fn try_file_write_utf8_err(error: HostIOErr) -> FileWriteUtf8Result {
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

fn try_file_delete_err(error: HostIOErr) -> FileDeleteResult {
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

fn try_file_size_err(error: HostIOErr) -> FileSizeResult {
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

fn try_file_bool_err(error: HostIOErr) -> FileBoolResult {
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

fn try_file_time_err(error: HostIOErr) -> FileTimeResult {
    FileTimeResult {
        payload: FileTimeResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileTimeResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_delete(path: RocStr) -> FileDeleteResult {
    let roc_host = roc_host();
    match fs::remove_file(path_from_roc_str(path, roc_host)) {
        Ok(()) => try_file_delete_ok(),
        Err(error) => try_file_delete_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_bytes(path: RocStr) -> FileBytesResult {
    let roc_host = roc_host();
    match fs::read(path_from_roc_str(path, roc_host)) {
        Ok(bytes) => try_file_bytes_ok(RocListWith::<u8, false>::from_slice(&bytes, roc_host)),
        Err(error) => try_file_bytes_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_utf8(path: RocStr) -> FileStrResult {
    let roc_host = roc_host();
    match fs::read_to_string(path_from_roc_str(path, roc_host)) {
        Ok(content) => try_file_str_ok(RocStr::from_str(&content, roc_host)),
        Err(error) => try_file_str_err(io_err_from_io(&error, roc_host)),
    }
}

const FILE_READER_BOX_ALIGN: usize = core::mem::align_of::<u64>();

fn box_file_reader(reader: BufReader<fs::File>, roc_host: &RocHost) -> *mut u64 {
    let raw: *mut BufReader<fs::File> = Box::into_raw(Box::new(reader));
    let boxed = allocate_box(
        core::mem::size_of::<u64>(),
        FILE_READER_BOX_ALIGN,
        false,
        roc_host,
    );
    unsafe {
        *(boxed as *mut u64) = raw as u64;
    }
    boxed as *mut u64
}

unsafe fn file_reader_ref<'a>(handle: *mut u64) -> &'a mut BufReader<fs::File> {
    &mut *(*handle as *mut BufReader<fs::File>)
}

extern "C" fn drop_file_reader(data_ptr: *mut c_void, _roc_host: *mut RocHost) {
    unsafe {
        let raw = *(data_ptr as *mut u64) as *mut BufReader<fs::File>;
        if !raw.is_null() {
            drop(Box::from_raw(raw));
        }
    }
}

fn release_file_reader(handle: *mut u64, roc_host: &RocHost) {
    decref_box_with(
        handle as RocBox,
        FILE_READER_BOX_ALIGN,
        false,
        Some(drop_file_reader),
        roc_host,
    );
}

#[no_mangle]
pub extern "C" fn hosted_file_open_reader(path: RocStr, capacity: u64) -> FileReaderOpenResult {
    let roc_host = roc_host();
    match fs::File::open(path_from_roc_str(path, roc_host)) {
        Ok(file) => {
            let reader = if capacity == 0 {
                BufReader::new(file)
            } else {
                BufReader::with_capacity(capacity as usize, file)
            };
            try_file_reader_ok(box_file_reader(reader, roc_host))
        }
        Err(error) => try_file_reader_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_line(handle: *mut u64) -> FileReaderLineResult {
    let roc_host = roc_host();
    let result = {
        let reader = unsafe { file_reader_ref(handle) };
        let mut buffer = Vec::new();
        match reader.read_until(b'\n', &mut buffer) {
            Ok(_) => {
                try_file_reader_line_ok(RocListWith::<u8, false>::from_slice(&buffer, roc_host))
            }
            Err(error) => try_file_reader_line_err(io_err_from_io(&error, roc_host)),
        }
    };
    release_file_reader(handle, roc_host);
    result
}

fn file_metadata(path: RocStr, roc_host: &RocHost) -> io::Result<fs::Metadata> {
    fs::metadata(path_from_roc_str(path, roc_host))
}

#[no_mangle]
pub extern "C" fn hosted_file_size_in_bytes(path: RocStr) -> FileSizeResult {
    let roc_host = roc_host();
    match file_metadata(path, roc_host) {
        Ok(metadata) => try_file_size_ok(metadata.len()),
        Err(error) => try_file_size_err(io_err_from_io(&error, roc_host)),
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
        Err(error) => try_file_bool_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_readable(path: RocStr) -> FileBoolResult {
    let roc_host = roc_host();
    match file_permission_bit(path, roc_host, 0o400) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_writable(path: RocStr) -> FileBoolResult {
    let roc_host = roc_host();
    match file_permission_bit(path, roc_host, 0o200) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(io_err_from_io(&error, roc_host)),
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
        Err(error) => try_file_time_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_time_created(path: RocStr) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::created) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_time_modified(path: RocStr) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::modified) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(io_err_from_io(&error, roc_host)),
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
        Err(error) => try_file_write_bytes_err(io_err_from_io(&error, roc_host)),
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
        Err(error) => try_file_write_utf8_err(io_err_from_io(&error, roc_host)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nanos_since_epoch_returns_zero_for_epoch() {
        assert_eq!(nanos_since_epoch(std::time::UNIX_EPOCH).unwrap(), 0);
    }
}
