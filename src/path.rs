use core::mem::ManuallyDrop;

use crate::abi::{
    io_err_from_io, roc_host, PathInfo, PathTypeResult, PathTypeResultPayload, PathTypeResultTag,
    RawPath,
};
use crate::roc_platform_abi::*;

pub(crate) fn unix_bytes_from_path_buf(
    path: std::path::PathBuf,
    roc_host: &RocHost,
) -> RocListWith<u8, false> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;

        let bytes = path.into_os_string().into_vec();
        RocListWith::<u8, false>::from_slice(&bytes, roc_host)
    }

    #[cfg(not(unix))]
    {
        RocListWith::<u8, false>::from_slice(path.to_string_lossy().as_bytes(), roc_host)
    }
}

pub(crate) fn windows_u16s_from_path_buf(
    path: std::path::PathBuf,
    roc_host: &RocHost,
) -> RocListWith<u16, false> {
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;

        let u16s: Vec<u16> = path.as_os_str().encode_wide().collect();
        RocListWith::<u16, false>::from_slice(&u16s, roc_host)
    }

    #[cfg(not(windows))]
    {
        let u16s: Vec<u16> = path.to_string_lossy().as_ref().encode_utf16().collect();
        RocListWith::<u16, false>::from_slice(&u16s, roc_host)
    }
}

pub(crate) fn raw_path_from_path_buf(path: std::path::PathBuf, roc_host: &RocHost) -> RawPath {
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

fn try_path_type_ok(value: PathInfo) -> PathTypeResult {
    PathTypeResult {
        payload: PathTypeResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: PathTypeResultTag::Ok,
    }
}

fn try_path_type_err(error: HostIOErr) -> PathTypeResult {
    PathTypeResult {
        payload: PathTypeResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: PathTypeResultTag::Err,
    }
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
        Err(error) => try_path_type_err(io_err_from_io(&error, roc_host)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_host() -> RocHost {
        make_roc_host(core::ptr::null_mut())
    }

    #[test]
    fn windows_u16s_from_path_uses_utf16_on_non_windows() {
        let host = test_host();
        let path = std::path::PathBuf::from("abc");

        let encoded = windows_u16s_from_path_buf(path, &host);

        assert_eq!(encoded.as_slice(), &[97, 98, 99]);
        encoded.decref(&host);
    }
}
