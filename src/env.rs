use core::mem::ManuallyDrop;
use std::env as std_env;
use std::ffi::OsString;

use crate::abi::{
    io_err_from_io, roc_host, EnvUnitResult, EnvUnitResultPayload, EnvUnitResultTag,
    EnvUnixPathResult, EnvUnixPathResultPayload, EnvUnixPathResultTag, EnvWindowsPathResult,
    EnvWindowsPathResultPayload, EnvWindowsPathResultTag, RawPath,
};
use crate::os_str::{os_string_from_raw, raw_os_str_from_os_str, validate_env_key, RawOsStr};
use crate::path::{
    path_buf_from_raw_path, raw_path_from_path_buf, unix_bytes_from_path_buf,
    windows_u16s_from_path_buf,
};
use crate::roc_platform_abi::*;

fn try_env_var_ok(value: RawOsStr) -> HostEnvVarResult {
    HostEnvVarResult {
        payload: HostEnvVarResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostEnvVarResultTag::Ok,
    }
}

fn try_env_var_err(error: EnvErrOrVarNotFound) -> HostEnvVarResult {
    HostEnvVarResult {
        payload: HostEnvVarResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostEnvVarResultTag::Err,
    }
}

fn env_var_not_found(name: RawOsStr) -> EnvErrOrVarNotFound {
    EnvErrOrVarNotFound {
        payload: EnvErrOrVarNotFoundPayload {
            var_not_found: ManuallyDrop::new(name),
        },
        tag: EnvErrOrVarNotFoundTag::VarNotFound,
    }
}

fn env_var_env_err(error: IOErr) -> EnvErrOrVarNotFound {
    EnvErrOrVarNotFound {
        payload: EnvErrOrVarNotFoundPayload {
            env_err: ManuallyDrop::new(error),
        },
        tag: EnvErrOrVarNotFoundTag::EnvErr,
    }
}

fn try_env_unit_ok() -> EnvUnitResult {
    EnvUnitResult {
        payload: EnvUnitResultPayload { ok: [] },
        tag: EnvUnitResultTag::Ok,
    }
}

fn try_env_unit_err(error: IOErr) -> EnvUnitResult {
    EnvUnitResult {
        payload: EnvUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: EnvUnitResultTag::Err,
    }
}

fn try_env_unix_path_ok(value: RocListWith<u8, false>) -> EnvUnixPathResult {
    EnvUnixPathResult {
        payload: EnvUnixPathResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: EnvUnixPathResultTag::Ok,
    }
}

fn try_env_unix_path_err(error: IOErr) -> EnvUnixPathResult {
    EnvUnixPathResult {
        payload: EnvUnixPathResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: EnvUnixPathResultTag::Err,
    }
}

fn try_env_windows_path_ok(value: RocListWith<u16, false>) -> EnvWindowsPathResult {
    EnvWindowsPathResult {
        payload: EnvWindowsPathResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: EnvWindowsPathResultTag::Ok,
    }
}

fn try_env_windows_path_err(error: IOErr) -> EnvWindowsPathResult {
    EnvWindowsPathResult {
        payload: EnvWindowsPathResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: EnvWindowsPathResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_is_windows(dummy: RocStr) -> bool {
    let roc_host = roc_host();
    unsafe { dummy.decref(roc_host) };

    cfg!(windows)
}

#[no_mangle]
pub extern "C" fn hosted_env_cwd_unix(dummy: RocStr) -> EnvUnixPathResult {
    let roc_host = roc_host();
    unsafe { dummy.decref(roc_host) };

    match std_env::current_dir() {
        Ok(path) => try_env_unix_path_ok(unix_bytes_from_path_buf(path, roc_host)),
        Err(error) => try_env_unix_path_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_cwd_windows(dummy: RocStr) -> EnvWindowsPathResult {
    let roc_host = roc_host();
    unsafe { dummy.decref(roc_host) };

    match std_env::current_dir() {
        Ok(path) => try_env_windows_path_ok(windows_u16s_from_path_buf(path, roc_host)),
        Err(error) => try_env_windows_path_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_exe_path_unix(dummy: RocStr) -> EnvUnixPathResult {
    let roc_host = roc_host();
    unsafe { dummy.decref(roc_host) };

    match std_env::current_exe() {
        Ok(path) => try_env_unix_path_ok(unix_bytes_from_path_buf(path, roc_host)),
        Err(error) => try_env_unix_path_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_exe_path_windows(dummy: RocStr) -> EnvWindowsPathResult {
    let roc_host = roc_host();
    unsafe { dummy.decref(roc_host) };

    match std_env::current_exe() {
        Ok(path) => try_env_windows_path_ok(windows_u16s_from_path_buf(path, roc_host)),
        Err(error) => try_env_windows_path_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_temp_dir(dummy: RocStr) -> RawPath {
    let roc_host = roc_host();
    unsafe { dummy.decref(roc_host) };

    raw_path_from_path_buf(std_env::temp_dir(), roc_host)
}

#[no_mangle]
pub extern "C" fn hosted_env_var(name: RawOsStr) -> HostEnvVarResult {
    let roc_host = roc_host();
    let key = match os_string_from_raw(name, roc_host) {
        Ok(key) => key,
        Err(error) => {
            return try_env_var_err(env_var_env_err(io_err_from_io(&error, roc_host)));
        }
    };

    if let Err(error) = validate_env_key(key.as_os_str()) {
        return try_env_var_err(env_var_env_err(io_err_from_io(&error, roc_host)));
    }

    match std_env::var_os(&key) {
        Some(value) => try_env_var_ok(raw_os_str_from_os_str(value.as_os_str(), roc_host)),
        None => try_env_var_err(env_var_not_found(raw_os_str_from_os_str(
            key.as_os_str(),
            roc_host,
        ))),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_set_cwd(path: HostEnvSetCwdArgs) -> EnvUnitResult {
    let roc_host = roc_host();
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_env_unit_err(io_err_from_io(&error, roc_host)),
    };
    match std_env::set_current_dir(path) {
        Ok(()) => try_env_unit_ok(),
        Err(error) => try_env_unit_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_dict() -> RocList<HostEnvDict> {
    let roc_host = roc_host();
    let pairs: Vec<(OsString, OsString)> = std_env::vars_os().collect();

    // SAFETY: every allocated element is initialized below before return.
    let list = unsafe { RocList::<HostEnvDict>::allocate(pairs.len(), roc_host) };
    for (index, (key, value)) in pairs.iter().enumerate() {
        unsafe {
            list.elements.add(index).write(HostEnvDict {
                name: raw_os_str_from_os_str(key.as_os_str(), roc_host),
                value: raw_os_str_from_os_str(value.as_os_str(), roc_host),
            });
        }
    }
    list
}

#[no_mangle]
pub extern "C" fn hosted_env_current_arch_os(dummy: RocStr) -> HostEnvCurrentArchOs {
    let roc_host = roc_host();
    unsafe { dummy.decref(roc_host) };

    HostEnvCurrentArchOs {
        arch: RocStr::from_str(std_env::consts::ARCH, roc_host),
        os: RocStr::from_str(std_env::consts::OS, roc_host),
    }
}
