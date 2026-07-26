use core::mem::ManuallyDrop;

use crate::abi::{
    io_err_from_io, roc_host, PathInfo, PathTypeResult, PathTypeResultPayload, PathTypeResultTag,
    RawPath,
};
use crate::roc_platform_abi::*;

pub(crate) trait IntoRawPath {
    fn into_raw_path(self) -> RawPath;
}

impl IntoRawPath for RawPath {
    fn into_raw_path(self) -> RawPath {
        self
    }
}

macro_rules! impl_into_raw_path {
    ($($type_name:ty),+ $(,)?) => {
        $(
            impl IntoRawPath for $type_name {
                fn into_raw_path(self) -> RawPath {
                    RawPath {
                        unix_bytes: self.unix_bytes,
                        windows_u16s: self.windows_u16s,
                        is_windows: self.is_windows,
                    }
                }
            }
        )+
    };
}

impl_into_raw_path!(
    HostDirCreateArgs,
    HostDirCreateAllArgs,
    HostDirDeleteAllArgs,
    HostDirDeleteEmptyArgs,
    HostDirListArgs,
    HostFileDeleteArgs,
    HostFileIsExecutableArgs,
    HostFileIsReadableArgs,
    HostFileIsWritableArgs,
    HostFileReadBytesArgs,
    HostFileReadUtf8Args,
    HostFileSizeInBytesArgs,
    HostFileTimeAccessedArgs,
    HostFileTimeCreatedArgs,
    HostFileTimeModifiedArgs,
    HostPathTypeArgs,
);

pub(crate) fn unix_bytes_from_path_buf(
    path: std::path::PathBuf,
    roc_host: &RocHost,
) -> RocListWith<u8, false> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;

        let bytes = path.into_os_string().into_vec();
        unsafe { RocListWith::<u8, false>::from_slice(&bytes, roc_host) }
    }

    #[cfg(not(unix))]
    {
        unsafe { RocListWith::<u8, false>::from_slice(path.to_string_lossy().as_bytes(), roc_host) }
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
        unsafe { RocListWith::<u16, false>::from_slice(&u16s, roc_host) }
    }

    #[cfg(not(windows))]
    {
        let u16s: Vec<u16> = path.to_string_lossy().as_ref().encode_utf16().collect();
        unsafe { RocListWith::<u16, false>::from_slice(&u16s, roc_host) }
    }
}

pub(crate) fn raw_path_from_path_buf(path: std::path::PathBuf, roc_host: &RocHost) -> RawPath {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;

        let bytes = path.into_os_string().into_vec();
        RawPath {
            unix_bytes: unsafe { RocListWith::<u8, false>::from_slice(&bytes, roc_host) },
            windows_u16s: unsafe { RocListWith::<u16, false>::from_slice(&[], roc_host) },
            is_windows: false,
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;

        let u16s: Vec<u16> = path.as_os_str().encode_wide().collect();
        RawPath {
            unix_bytes: unsafe { RocListWith::<u8, false>::from_slice(&[], roc_host) },
            windows_u16s: unsafe { RocListWith::<u16, false>::from_slice(&u16s, roc_host) },
            is_windows: true,
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        let bytes = path.to_string_lossy().as_bytes().to_vec();
        RawPath {
            unix_bytes: unsafe { RocListWith::<u8, false>::from_slice(&bytes, roc_host) },
            windows_u16s: unsafe { RocListWith::<u16, false>::from_slice(&[], roc_host) },
            is_windows: false,
        }
    }
}

fn unsupported_native_path(expected: &str, got: &str) -> std::io::Error {
    std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        format!("expected {expected} path on this platform, got {got}"),
    )
}

/// Convert an owned Roc raw path into a native `PathBuf` without passing
/// through Unicode. Both Roc list fields are consumed on every path.
pub(crate) fn path_buf_from_raw_path(
    path: impl IntoRawPath,
    roc_host: &RocHost,
) -> std::io::Result<std::path::PathBuf> {
    let path = path.into_raw_path();
    let unix_bytes = path.unix_bytes;
    let windows_u16s = path.windows_u16s;

    #[cfg(unix)]
    let result = if path.is_windows {
        Err(unsupported_native_path("Unix", "Windows"))
    } else {
        use std::os::unix::ffi::OsStringExt;
        Ok(std::path::PathBuf::from(std::ffi::OsString::from_vec(
            unix_bytes.as_slice().to_vec(),
        )))
    };

    #[cfg(windows)]
    let result = if path.is_windows {
        use std::os::windows::ffi::OsStringExt;
        Ok(std::path::PathBuf::from(std::ffi::OsString::from_wide(
            windows_u16s.as_slice(),
        )))
    } else {
        Err(unsupported_native_path("Windows", "Unix"))
    };

    #[cfg(not(any(unix, windows)))]
    let result = Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "native paths are not implemented on this platform",
    ));

    unsafe { unix_bytes.decref(roc_host) };
    unsafe { windows_u16s.decref(roc_host) };
    result
}

fn try_path_type_ok(value: PathInfo) -> PathTypeResult {
    PathTypeResult {
        payload: PathTypeResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: PathTypeResultTag::Ok,
    }
}

fn try_path_type_err(error: IOErr) -> PathTypeResult {
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
    let path = match path_buf_from_raw_path(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_path_type_err(io_err_from_io(&error, roc_host)),
    };

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
        unsafe { encoded.decref(&host) };
    }

    #[cfg(unix)]
    #[test]
    fn raw_unix_path_preserves_non_utf8_bytes() {
        use std::os::unix::ffi::OsStrExt;

        let host = test_host();
        let bytes = [b'f', 0x80, b'o'];
        let raw = RawPath {
            unix_bytes: unsafe { RocListWith::from_slice(&bytes, &host) },
            windows_u16s: RocListWith::empty(),
            is_windows: false,
        };

        let path = path_buf_from_raw_path(raw, &host).unwrap();

        assert_eq!(path.as_os_str().as_bytes(), bytes);
    }

    #[cfg(unix)]
    #[test]
    fn raw_windows_path_is_rejected_on_unix() {
        let host = test_host();
        let raw = RawPath {
            unix_bytes: RocListWith::empty(),
            windows_u16s: unsafe { RocListWith::from_slice(&[b'x' as u16], &host) },
            is_windows: true,
        };

        let error = path_buf_from_raw_path(raw, &host).unwrap_err();

        assert_eq!(error.kind(), std::io::ErrorKind::Unsupported);
    }
}
