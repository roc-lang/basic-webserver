use core::mem::ManuallyDrop;
use std::fs;

use crate::abi::{
    io_err_from_io, roc_host, DirListResult, DirListResultPayload, DirListResultTag, DirUnitResult,
    DirUnitResultPayload, DirUnitResultTag, RawPath,
};
use crate::path::{path_buf_from_raw_path, raw_path_from_path_buf};
use crate::roc_platform_abi::*;

fn try_dir_unit_ok() -> DirUnitResult {
    DirUnitResult {
        payload: DirUnitResultPayload { ok: [] },
        tag: DirUnitResultTag::Ok,
    }
}

fn try_dir_unit_err(error: IOErr) -> DirUnitResult {
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

fn try_dir_list_err(error: IOErr) -> DirListResult {
    DirListResult {
        payload: DirListResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: DirListResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_create(path: HostDirCreateArgs) -> DirUnitResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_unit_err(io_err_from_io(&error, roc_host)),
    };
    match fs::create_dir(path) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_create_all(path: HostDirCreateAllArgs) -> DirUnitResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_unit_err(io_err_from_io(&error, roc_host)),
    };
    match fs::create_dir_all(path) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_delete_all(path: HostDirDeleteAllArgs) -> DirUnitResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_unit_err(io_err_from_io(&error, roc_host)),
    };
    match fs::remove_dir_all(path) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_delete_empty(path: HostDirDeleteEmptyArgs) -> DirUnitResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_unit_err(io_err_from_io(&error, roc_host)),
    };
    match fs::remove_dir(path) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_list(path: HostDirListArgs) -> DirListResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_list_err(io_err_from_io(&error, roc_host)),
    };
    match fs::read_dir(path) {
        Ok(read_dir) => {
            let entries: Vec<std::path::PathBuf> = read_dir
                .filter_map(|entry| entry.ok().map(|entry| entry.path()))
                .collect();
            // SAFETY: every allocated element is initialized below before the
            // list is returned to Roc.
            let list = unsafe { RocList::<RawPath>::allocate(entries.len(), roc_host) };
            for (index, entry) in entries.into_iter().enumerate() {
                unsafe {
                    list.elements
                        .add(index)
                        .write(raw_path_from_path_buf(entry, roc_host));
                }
            }
            try_dir_list_ok(list)
        }
        Err(error) => try_dir_list_err(io_err_from_io(&error, roc_host)),
    }
}
