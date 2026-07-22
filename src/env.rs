use core::mem::ManuallyDrop;
use std::env as std_env;

use crate::abi::{
    io_err_from_io, roc_host, EnvUnitResult, EnvUnitResultPayload, EnvUnitResultTag,
    EnvUnixPathResult, EnvUnixPathResultPayload, EnvUnixPathResultTag, EnvVarResult,
    EnvVarResultPayload, EnvVarResultTag, EnvWindowsPathResult, EnvWindowsPathResultPayload,
    EnvWindowsPathResultTag, RawPath,
};
use crate::path::{
    path_buf_from_raw_path, raw_path_from_path_buf, unix_bytes_from_path_buf,
    windows_u16s_from_path_buf,
};
use crate::roc_platform_abi::*;

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
pub extern "C" fn hosted_env_var(name: RocStr) -> EnvVarResult {
    let roc_host = roc_host();
    let key = name.as_str().to_owned();
    match std_env::var_os(&key) {
        Some(value) => {
            unsafe { name.decref(roc_host) };
            try_env_str_ok(RocStr::from_str(value.to_string_lossy().as_ref(), roc_host))
        }
        None => try_env_str_err(name),
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
pub extern "C" fn hosted_env_dict(dummy: RocStr) -> RocList<HostEnvDict> {
    let roc_host = roc_host();
    unsafe { dummy.decref(roc_host) };

    let pairs: Vec<(String, String)> = std_env::vars_os()
        .map(|(key, value)| {
            (
                key.to_string_lossy().into_owned(),
                value.to_string_lossy().into_owned(),
            )
        })
        .collect();

    // SAFETY: every allocated element is initialized below before return.
    let list = unsafe { RocList::<HostEnvDict>::allocate(pairs.len(), roc_host) };
    for (index, (key, value)) in pairs.into_iter().enumerate() {
        unsafe {
            list.elements.add(index).write(HostEnvDict {
                key: RocStr::from_str(&key, roc_host),
                value: RocStr::from_str(&value, roc_host),
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
