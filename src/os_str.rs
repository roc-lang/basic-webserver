use core::mem::ManuallyDrop;
use std::ffi::{OsStr, OsString};
use std::io;

use crate::roc_platform_abi::{
    RocHost, RocListWith, UnixBytesOrUtf8OrWindowsU16s, UnixBytesOrUtf8OrWindowsU16sPayload,
    UnixBytesOrUtf8OrWindowsU16sTag,
};

pub(crate) type RawOsStr = UnixBytesOrUtf8OrWindowsU16s;
type RawOsStrPayload = UnixBytesOrUtf8OrWindowsU16sPayload;
type RawOsStrTag = UnixBytesOrUtf8OrWindowsU16sTag;

fn unsupported_native_variant(expected: &str, got: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::Unsupported,
        format!("expected {expected} OS string on this platform, got {got}"),
    )
}

fn u8_list(slice: &[u8], roc_host: &RocHost) -> RocListWith<u8, false> {
    // SAFETY: the returned Roc list owns a copy of `slice`.
    unsafe { RocListWith::<u8, false>::from_slice(slice, roc_host) }
}

#[cfg(windows)]
fn u16_list(slice: &[u16], roc_host: &RocHost) -> RocListWith<u16, false> {
    // SAFETY: the returned Roc list owns a copy of `slice`.
    unsafe { RocListWith::<u16, false>::from_slice(slice, roc_host) }
}

/// Consume a Roc native string and convert it without Unicode normalization or
/// replacement. The active platform accepts its native representation and the
/// portable UTF-8 representation; a foreign native representation is rejected.
pub(crate) fn os_string_from_raw(value: RawOsStr, roc_host: &RocHost) -> io::Result<OsString> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;

        match value.tag {
            RawOsStrTag::UnixBytes => unsafe {
                let bytes = ManuallyDrop::into_inner(value.payload.unix_bytes);
                let result = OsString::from_vec(bytes.as_slice().to_vec());
                bytes.decref(roc_host);
                Ok(result)
            },
            RawOsStrTag::Utf8 => unsafe {
                let text = ManuallyDrop::into_inner(value.payload.utf8);
                let result = OsString::from_vec(text.as_str().as_bytes().to_vec());
                text.decref(roc_host);
                Ok(result)
            },
            RawOsStrTag::WindowsU16s => unsafe {
                let units = ManuallyDrop::into_inner(value.payload.windows_u16s);
                units.decref(roc_host);
                Err(unsupported_native_variant("UnixBytes", "WindowsU16s"))
            },
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStringExt;

        match value.tag {
            RawOsStrTag::UnixBytes => unsafe {
                let bytes = ManuallyDrop::into_inner(value.payload.unix_bytes);
                bytes.decref(roc_host);
                Err(unsupported_native_variant("WindowsU16s", "UnixBytes"))
            },
            RawOsStrTag::Utf8 => unsafe {
                let text = ManuallyDrop::into_inner(value.payload.utf8);
                let result = OsString::from(text.as_str());
                text.decref(roc_host);
                Ok(result)
            },
            RawOsStrTag::WindowsU16s => unsafe {
                let units = ManuallyDrop::into_inner(value.payload.windows_u16s);
                let result = OsString::from_wide(units.as_slice());
                units.decref(roc_host);
                Ok(result)
            },
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        match value.tag {
            RawOsStrTag::UnixBytes => unsafe {
                ManuallyDrop::into_inner(value.payload.unix_bytes).decref(roc_host)
            },
            RawOsStrTag::Utf8 => unsafe {
                ManuallyDrop::into_inner(value.payload.utf8).decref(roc_host)
            },
            RawOsStrTag::WindowsU16s => unsafe {
                ManuallyDrop::into_inner(value.payload.windows_u16s).decref(roc_host)
            },
        }

        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "native OS strings are not implemented on this platform",
        ))
    }
}

/// Copy an operating-system string into Roc's exact native representation.
pub(crate) fn raw_os_str_from_os_str(value: &OsStr, roc_host: &RocHost) -> RawOsStr {
    if let Some(text) = value.to_str() {
        return RawOsStr {
            payload: RawOsStrPayload {
                utf8: ManuallyDrop::new(crate::roc_platform_abi::RocStr::from_str(text, roc_host)),
            },
            tag: RawOsStrTag::Utf8,
        };
    }

    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;

        RawOsStr {
            payload: RawOsStrPayload {
                unix_bytes: ManuallyDrop::new(u8_list(value.as_bytes(), roc_host)),
            },
            tag: RawOsStrTag::UnixBytes,
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;

        let units: Vec<u16> = value.encode_wide().collect();
        RawOsStr {
            payload: RawOsStrPayload {
                windows_u16s: ManuallyDrop::new(u16_list(&units, roc_host)),
            },
            tag: RawOsStrTag::WindowsU16s,
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        RawOsStr {
            payload: RawOsStrPayload {
                utf8: ManuallyDrop::new(crate::roc_platform_abi::RocStr::from_str(
                    value.to_string_lossy().as_ref(),
                    roc_host,
                )),
            },
            tag: RawOsStrTag::Utf8,
        }
    }
}

pub(crate) fn validate_env_key(key: &OsStr) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;

        let bytes = key.as_bytes();
        if bytes.is_empty() || bytes.contains(&0) || bytes.contains(&b'=') {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "environment variable names cannot be empty or contain nul bytes or '='",
            ));
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;

        let units: Vec<u16> = key.encode_wide().collect();
        if units.is_empty() || units.contains(&0) || units.contains(&(b'=' as u16)) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "environment variable names cannot be empty or contain nul code units or '='",
            ));
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_host() -> RocHost {
        crate::roc_platform_abi::make_roc_host(core::ptr::null_mut())
    }

    #[test]
    fn rejects_invalid_environment_names() {
        assert!(validate_env_key(OsStr::new("")).is_err());
        assert!(validate_env_key(OsStr::new("A=B")).is_err());
        assert!(validate_env_key(OsStr::new("A\0B")).is_err());
        assert!(validate_env_key(OsStr::new("VALID_NAME")).is_ok());
    }

    #[cfg(unix)]
    #[test]
    fn unix_bytes_roundtrip_without_unicode_conversion() {
        use std::os::unix::ffi::OsStrExt;

        let roc_host = test_host();
        let raw = RawOsStr {
            payload: RawOsStrPayload {
                unix_bytes: ManuallyDrop::new(u8_list(&[97, 255, 98], &roc_host)),
            },
            tag: RawOsStrTag::UnixBytes,
        };

        let native = os_string_from_raw(raw, &roc_host).unwrap();
        assert_eq!(native.as_os_str().as_bytes(), &[97, 255, 98]);

        let copied = raw_os_str_from_os_str(native.as_os_str(), &roc_host);
        assert_eq!(copied.tag, RawOsStrTag::UnixBytes);
        unsafe {
            let bytes = ManuallyDrop::into_inner(copied.payload.unix_bytes);
            assert_eq!(bytes.as_slice(), &[97, 255, 98]);
            bytes.decref(&roc_host);
        }
    }

    #[cfg(unix)]
    #[test]
    fn unix_unicode_values_use_the_canonical_utf8_variant() {
        let roc_host = test_host();
        let copied = raw_os_str_from_os_str(OsStr::new("PATH"), &roc_host);
        assert_eq!(copied.tag, RawOsStrTag::Utf8);
        unsafe {
            let text = ManuallyDrop::into_inner(copied.payload.utf8);
            assert_eq!(text.as_str(), "PATH");
            text.decref(&roc_host);
        }
    }

    #[cfg(unix)]
    #[test]
    fn unix_rejects_windows_units() {
        let roc_host = test_host();
        let raw = RawOsStr {
            payload: RawOsStrPayload {
                windows_u16s: ManuallyDrop::new(unsafe {
                    RocListWith::<u16, false>::from_slice(&[97, 0xD800], &roc_host)
                }),
            },
            tag: RawOsStrTag::WindowsU16s,
        };

        let error = os_string_from_raw(raw, &roc_host).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Unsupported);
    }

    #[cfg(windows)]
    #[test]
    fn windows_units_roundtrip_without_unicode_conversion() {
        use std::os::windows::ffi::{OsStrExt, OsStringExt};

        let roc_host = test_host();
        let raw = RawOsStr {
            payload: RawOsStrPayload {
                windows_u16s: ManuallyDrop::new(u16_list(&[97, 0xD800, 98], &roc_host)),
            },
            tag: RawOsStrTag::WindowsU16s,
        };

        let native = os_string_from_raw(raw, &roc_host).unwrap();
        assert_eq!(native.encode_wide().collect::<Vec<_>>(), [97, 0xD800, 98]);

        let with_unpaired_surrogate = OsString::from_wide(&[97, 0xD800, 98]);
        let copied = raw_os_str_from_os_str(with_unpaired_surrogate.as_os_str(), &roc_host);
        assert_eq!(copied.tag, RawOsStrTag::WindowsU16s);
        unsafe {
            let units = ManuallyDrop::into_inner(copied.payload.windows_u16s);
            assert_eq!(units.as_slice(), &[97, 0xD800, 98]);
            units.decref(&roc_host);
        }
    }

    #[cfg(windows)]
    #[test]
    fn windows_unicode_values_use_the_canonical_utf8_variant() {
        let roc_host = test_host();
        let copied = raw_os_str_from_os_str(OsStr::new("PATH"), &roc_host);
        assert_eq!(copied.tag, RawOsStrTag::Utf8);
        unsafe {
            let text = ManuallyDrop::into_inner(copied.payload.utf8);
            assert_eq!(text.as_str(), "PATH");
            text.decref(&roc_host);
        }
    }

    #[cfg(windows)]
    #[test]
    fn windows_rejects_unix_bytes() {
        let roc_host = test_host();
        let raw = RawOsStr {
            payload: RawOsStrPayload {
                unix_bytes: ManuallyDrop::new(u8_list(&[97, 255], &roc_host)),
            },
            tag: RawOsStrTag::UnixBytes,
        };

        let error = os_string_from_raw(raw, &roc_host).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Unsupported);
    }
}
