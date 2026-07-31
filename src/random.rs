use core::mem::ManuallyDrop;
use std::io;

use crate::abi::{
    io_err_from_io, roc_host, RandomBytesError, RandomBytesErrorPayload, RandomBytesErrorTag,
    RandomBytesResult, RandomBytesResultPayload, RandomBytesResultTag, RandomBytesTooMany,
};
use crate::roc_platform_abi::{RocHost, RocListWith};

const MAX_RANDOM_BYTES: u64 = 64 * 1024;

enum RandomFailure {
    EntropyUnavailable(io::Error),
    TooManyBytes,
}

fn random_bytes_with(
    requested: u64,
    roc_host: &RocHost,
    fill: impl FnOnce(&mut [u8]) -> io::Result<()>,
) -> Result<RocListWith<u8, false>, RandomFailure> {
    if requested > MAX_RANDOM_BYTES {
        return Err(RandomFailure::TooManyBytes);
    }
    if requested == 0 {
        return Ok(RocListWith::empty());
    }

    let length = requested as usize;
    // SAFETY: the limit above fits usize on every supported target. The
    // allocation is initialized before a slice is formed, and it is either
    // returned as an owned Roc list or released on failure.
    let bytes = unsafe {
        let bytes = RocListWith::<u8, false>::allocate(length, roc_host);
        core::ptr::write_bytes(bytes.elements, 0, length);
        bytes
    };
    let destination = unsafe { core::slice::from_raw_parts_mut(bytes.elements, length) };

    match fill(destination) {
        Ok(()) => Ok(bytes),
        Err(error) => {
            // Do not expose or log a partially filled destination.
            unsafe { bytes.decref(roc_host) };
            Err(RandomFailure::EntropyUnavailable(error))
        }
    }
}

fn random_error(failure: RandomFailure, requested: u64, roc_host: &RocHost) -> RandomBytesError {
    let (tag, entropy, too_many) = match failure {
        RandomFailure::EntropyUnavailable(error) => (
            RandomBytesErrorTag::EntropyUnavailable,
            Some(io_err_from_io(&error, roc_host)),
            None,
        ),
        RandomFailure::TooManyBytes => (
            RandomBytesErrorTag::TooManyBytes,
            None,
            Some(RandomBytesTooMany {
                max: MAX_RANDOM_BYTES,
                requested,
            }),
        ),
    };

    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut value: RandomBytesError = core::mem::zeroed();
        match (entropy, too_many) {
            (Some(error), None) => {
                core::ptr::write(value.payload.as_mut_ptr().cast(), error);
            }
            (None, Some(limit)) => {
                core::ptr::write(value.payload.as_mut_ptr().cast(), limit);
            }
            _ => unreachable!("random error payload does not match its tag"),
        }
        value.tag = tag;
        value
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        let payload = match (entropy, too_many) {
            (Some(error), None) => RandomBytesErrorPayload {
                entropy_unavailable: ManuallyDrop::new(error),
            },
            (None, Some(limit)) => RandomBytesErrorPayload {
                too_many_bytes: ManuallyDrop::new(limit),
            },
            _ => unreachable!("random error payload does not match its tag"),
        };
        RandomBytesError { payload, tag }
    }
}

fn random_ok(bytes: RocListWith<u8, false>) -> RandomBytesResult {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut result: RandomBytesResult = core::mem::zeroed();
        core::ptr::write(result.payload.as_mut_ptr().cast(), bytes);
        result.tag = RandomBytesResultTag::Ok;
        result
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        RandomBytesResult {
            payload: RandomBytesResultPayload {
                ok: ManuallyDrop::new(bytes),
            },
            tag: RandomBytesResultTag::Ok,
        }
    }
}

fn random_err(error: RandomBytesError) -> RandomBytesResult {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut result: RandomBytesResult = core::mem::zeroed();
        core::ptr::write(result.payload.as_mut_ptr().cast(), error);
        result.tag = RandomBytesResultTag::Err;
        result
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        RandomBytesResult {
            payload: RandomBytesResultPayload {
                err: ManuallyDrop::new(error),
            },
            tag: RandomBytesResultTag::Err,
        }
    }
}

fn hosted_random_bytes_with(
    requested: u64,
    fill: impl FnOnce(&mut [u8]) -> io::Result<()>,
) -> RandomBytesResult {
    let roc_host = roc_host();
    match random_bytes_with(requested, roc_host, fill) {
        Ok(bytes) => random_ok(bytes),
        Err(failure) => random_err(random_error(failure, requested, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_random_bytes(requested: u64) -> RandomBytesResult {
    hosted_random_bytes_with(requested, |destination| {
        getrandom::fill(destination).map_err(io::Error::from)
    })
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicBool, Ordering};

    use super::*;
    use crate::roc_platform_abi::IOErrTag;

    fn initialize() {
        crate::abi::initialize_test_roc_host();
    }

    fn take_ok(result: RandomBytesResult) -> Vec<u8> {
        assert_eq!(result.tag, RandomBytesResultTag::Ok);
        let bytes = result.payload_ok();
        let owned = bytes.as_slice().to_vec();
        unsafe { result.decref(roc_host()) };
        owned
    }

    #[test]
    fn zero_bytes_succeeds_without_calling_the_os_source() {
        initialize();
        let called = AtomicBool::new(false);
        let result = hosted_random_bytes_with(0, |_| {
            called.store(true, Ordering::Relaxed);
            Ok(())
        });

        assert!(take_ok(result).is_empty());
        assert!(!called.load(Ordering::Relaxed));
    }

    #[test]
    fn injected_source_fills_representative_lengths_exactly() {
        initialize();
        for length in [1, 31, 32, 33, MAX_RANDOM_BYTES] {
            let result = hosted_random_bytes_with(length, |destination| {
                for (index, byte) in destination.iter_mut().enumerate() {
                    *byte = (index % 251) as u8;
                }
                Ok(())
            });
            let bytes = take_ok(result);

            assert_eq!(bytes.len(), length as usize);
            assert!(bytes
                .iter()
                .enumerate()
                .all(|(index, byte)| *byte == (index % 251) as u8));
        }
    }

    #[test]
    fn oversized_request_fails_before_source_or_allocation() {
        initialize();
        let called = AtomicBool::new(false);
        let requested = MAX_RANDOM_BYTES + 1;
        let result = hosted_random_bytes_with(requested, |_| {
            called.store(true, Ordering::Relaxed);
            Ok(())
        });

        assert_eq!(result.tag, RandomBytesResultTag::Err);
        let error = result.payload_err();
        assert_eq!(error.tag, RandomBytesErrorTag::TooManyBytes);
        let limit = error.payload_too_many_bytes();
        assert_eq!(limit.requested, requested);
        assert_eq!(limit.max, MAX_RANDOM_BYTES);
        assert!(!called.load(Ordering::Relaxed));
        unsafe { result.decref(roc_host()) };
    }

    #[test]
    fn injected_entropy_failure_is_typed_and_does_not_return_bytes() {
        initialize();
        let result = hosted_random_bytes_with(32, |destination| {
            destination.fill(0xA5);
            Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "injected entropy failure",
            ))
        });

        assert_eq!(result.tag, RandomBytesResultTag::Err);
        let error = result.payload_err();
        assert_eq!(error.tag, RandomBytesErrorTag::EntropyUnavailable);
        assert_eq!(
            error.payload_entropy_unavailable().tag,
            IOErrTag::PermissionDenied
        );
        unsafe { result.decref(roc_host()) };
    }

    #[test]
    fn native_source_returns_exact_length() {
        initialize();
        assert_eq!(take_ok(hosted_random_bytes(32)).len(), 32);
    }

    #[test]
    fn native_source_is_safe_under_concurrent_calls() {
        initialize();
        let threads: Vec<_> = (0..16)
            .map(|_| {
                std::thread::spawn(|| {
                    for _ in 0..100 {
                        if take_ok(hosted_random_bytes(32)).len() != 32 {
                            return false;
                        }
                    }
                    true
                })
            })
            .collect();

        assert!(threads
            .into_iter()
            .all(|thread| thread.join().expect("random worker panicked")));
    }
}
