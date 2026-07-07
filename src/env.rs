use core::mem::ManuallyDrop;
use std::env as std_env;

use crate::abi::{
    io_err_from_io, roc_host, EnvUnixPathResult, EnvUnixPathResultPayload, EnvUnixPathResultTag,
    EnvVarResult, EnvVarResultPayload, EnvVarResultTag, EnvWindowsPathResult,
    EnvWindowsPathResultPayload, EnvWindowsPathResultTag, RawPath,
};
use crate::path::{raw_path_from_path_buf, unix_bytes_from_path_buf, windows_u16s_from_path_buf};
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

fn try_env_unix_path_ok(value: RocListWith<u8, false>) -> EnvUnixPathResult {
    EnvUnixPathResult {
        payload: EnvUnixPathResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: EnvUnixPathResultTag::Ok,
    }
}

fn try_env_unix_path_err(error: HostIOErr) -> EnvUnixPathResult {
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

fn try_env_windows_path_err(error: HostIOErr) -> EnvWindowsPathResult {
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
    dummy.decref(roc_host);

    cfg!(windows)
}

#[no_mangle]
pub extern "C" fn hosted_env_cwd_unix(dummy: RocStr) -> EnvUnixPathResult {
    let roc_host = roc_host();
    dummy.decref(roc_host);

    match std_env::current_dir() {
        Ok(path) => try_env_unix_path_ok(unix_bytes_from_path_buf(path, roc_host)),
        Err(error) => try_env_unix_path_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_cwd_windows(dummy: RocStr) -> EnvWindowsPathResult {
    let roc_host = roc_host();
    dummy.decref(roc_host);

    match std_env::current_dir() {
        Ok(path) => try_env_windows_path_ok(windows_u16s_from_path_buf(path, roc_host)),
        Err(error) => try_env_windows_path_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_exe_path_unix(dummy: RocStr) -> EnvUnixPathResult {
    let roc_host = roc_host();
    dummy.decref(roc_host);

    match std_env::current_exe() {
        Ok(path) => try_env_unix_path_ok(unix_bytes_from_path_buf(path, roc_host)),
        Err(error) => try_env_unix_path_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_exe_path_windows(dummy: RocStr) -> EnvWindowsPathResult {
    let roc_host = roc_host();
    dummy.decref(roc_host);

    match std_env::current_exe() {
        Ok(path) => try_env_windows_path_ok(windows_u16s_from_path_buf(path, roc_host)),
        Err(error) => try_env_windows_path_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_temp_dir(dummy: RocStr) -> RawPath {
    let roc_host = roc_host();
    dummy.decref(roc_host);

    raw_path_from_path_buf(std_env::temp_dir(), roc_host)
}

#[no_mangle]
pub extern "C" fn hosted_env_var(name: RocStr) -> EnvVarResult {
    let roc_host = roc_host();
    let key = name.as_str().to_owned();
    match std_env::var_os(&key) {
        Some(value) => {
            name.decref(roc_host);
            try_env_str_ok(RocStr::from_str(value.to_string_lossy().as_ref(), roc_host))
        }
        None => try_env_str_err(name),
    }
}
