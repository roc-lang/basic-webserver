//! Protocol-neutral admission limits for inbound request metadata.
//!
//! Hyper must decode enough protocol structure to construct a `Request`, but
//! neither native routing nor Roc should observe metadata beyond the public
//! server budget. The connection builder applies the hard parser envelope
//! defined here; `RequestMetadataLimits::admit` then applies the application's
//! exact limits before route selection.

use crate::request_target::RequestMetadata;

const DECODED_HEADER_FIELD_OVERHEAD: usize = 32;

/// Hyper's HTTP/1 parser cannot represent a longer URI.
pub(crate) const HARD_MAX_TARGET_BYTES: usize = u16::MAX as usize - 1;
pub(crate) const HARD_MAX_HEADER_LIST_BYTES: usize = 1024 * 1024;
pub(crate) const HARD_MAX_HEADER_FIELDS: usize = 1024;

/// HTTP/1's parser buffer also contains the method, version, separators, and
/// terminating CRLF. Header wire bytes are no larger than their decoded
/// accounting because each field receives 32 bytes of accounting overhead.
pub(crate) const HTTP1_MAX_HEAD_BYTES: usize =
    HARD_MAX_TARGET_BYTES + HARD_MAX_HEADER_LIST_BYTES + 8 * 1024;

/// HTTP/2's SETTINGS limit includes pseudo-fields, while the public header
/// budget applies only to ordinary fields exposed through `Request.headers`.
/// Target bytes have their own public budget; the remaining fixed allowance
/// bounds method, scheme, authority, pseudo-field overhead, and framing.
const HTTP2_PSEUDO_FIELD_ALLOWANCE_BYTES: usize = 8 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct RequestMetadataLimits {
    max_target_bytes: usize,
    max_header_list_bytes: usize,
    max_header_fields: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum RequestMetadataRejection {
    TargetTooLong {
        limit: usize,
    },
    HeadersTooLarge {
        byte_limit: usize,
        field_limit: usize,
    },
}

impl RequestMetadataLimits {
    pub(crate) fn new(
        max_target_bytes: u32,
        max_header_list_bytes: u32,
        max_header_fields: u16,
    ) -> Result<Self, String> {
        let max_target_bytes = max_target_bytes as usize;
        let max_header_list_bytes = max_header_list_bytes as usize;
        let max_header_fields = max_header_fields as usize;

        if max_target_bytes == 0 {
            return Err("request target byte limit must be non-zero".to_owned());
        }
        if max_target_bytes > HARD_MAX_TARGET_BYTES {
            return Err(format!(
                "request target byte limit cannot exceed {HARD_MAX_TARGET_BYTES}"
            ));
        }
        if max_header_list_bytes == 0 {
            return Err("request header byte limit must be non-zero".to_owned());
        }
        if max_header_list_bytes > HARD_MAX_HEADER_LIST_BYTES {
            return Err(format!(
                "request header byte limit cannot exceed {HARD_MAX_HEADER_LIST_BYTES}"
            ));
        }
        if max_header_fields == 0 {
            return Err("request header field limit must be non-zero".to_owned());
        }
        if max_header_fields > HARD_MAX_HEADER_FIELDS {
            return Err(format!(
                "request header field limit cannot exceed {HARD_MAX_HEADER_FIELDS}"
            ));
        }

        Ok(Self {
            max_target_bytes,
            max_header_list_bytes,
            max_header_fields,
        })
    }

    pub(crate) fn admit_parts(
        &self,
        parts: &hyper::http::request::Parts,
        metadata: RequestMetadata,
    ) -> Result<(), RequestMetadataRejection> {
        if metadata.normalized_target_len(&parts.uri) > self.max_target_bytes {
            return Err(RequestMetadataRejection::TargetTooLong {
                limit: self.max_target_bytes,
            });
        }

        if parts.headers.len() > self.max_header_fields
            || decoded_header_list_bytes(&parts.headers) > self.max_header_list_bytes
        {
            return Err(RequestMetadataRejection::HeadersTooLarge {
                byte_limit: self.max_header_list_bytes,
                field_limit: self.max_header_fields,
            });
        }

        Ok(())
    }

    pub(crate) fn max_header_fields(&self) -> usize {
        self.max_header_fields
    }

    /// h2 treats SETTINGS_MAX_HEADER_LIST_SIZE as exclusive while the platform
    /// contract is inclusive, hence the final byte. This independently bounds
    /// HPACK expansion before the exact ordinary-field check runs.
    pub(crate) fn http2_max_header_list_size(&self) -> u32 {
        let limit = self.max_header_list_bytes
            + self.max_target_bytes
            + HTTP2_PSEUDO_FIELD_ALLOWANCE_BYTES
            + 1;
        limit
            .try_into()
            .expect("validated request metadata limits fit HTTP/2 settings")
    }
}

fn decoded_header_list_bytes(headers: &hyper::HeaderMap) -> usize {
    headers.iter().fold(0usize, |total, (name, value)| {
        total.saturating_add(
            name.as_str().len() + value.as_bytes().len() + DECODED_HEADER_FIELD_OVERHEAD,
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_nonzero_limits_and_hard_maxima() {
        assert!(RequestMetadataLimits::new(1, 1, 1).is_ok());
        assert!(RequestMetadataLimits::new(
            HARD_MAX_TARGET_BYTES as u32,
            HARD_MAX_HEADER_LIST_BYTES as u32,
            HARD_MAX_HEADER_FIELDS as u16,
        )
        .is_ok());

        assert!(RequestMetadataLimits::new(0, 1, 1).is_err());
        assert!(RequestMetadataLimits::new(1, 0, 1).is_err());
        assert!(RequestMetadataLimits::new(1, 1, 0).is_err());
        assert!(RequestMetadataLimits::new(HARD_MAX_TARGET_BYTES as u32 + 1, 1, 1).is_err());
        assert!(RequestMetadataLimits::new(1, HARD_MAX_HEADER_LIST_BYTES as u32 + 1, 1).is_err());
        assert!(RequestMetadataLimits::new(1, 1, HARD_MAX_HEADER_FIELDS as u16 + 1).is_err());
    }

    #[test]
    fn target_limit_is_inclusive() {
        let limits = RequestMetadataLimits::new(4, 1024, 8).unwrap();
        let exact = hyper::Request::builder()
            .version(hyper::Version::HTTP_10)
            .uri("/abc")
            .body(())
            .unwrap();
        let over = hyper::Request::builder()
            .version(hyper::Version::HTTP_10)
            .uri("/abcd")
            .body(())
            .unwrap();

        let (exact_parts, _) = exact.into_parts();
        let exact_metadata = RequestMetadata::validate_parts(&exact_parts).unwrap();
        let (over_parts, _) = over.into_parts();
        let over_metadata = RequestMetadata::validate_parts(&over_parts).unwrap();

        assert_eq!(limits.admit_parts(&exact_parts, exact_metadata), Ok(()));
        assert_eq!(
            limits.admit_parts(&over_parts, over_metadata),
            Err(RequestMetadataRejection::TargetTooLong { limit: 4 })
        );
    }

    #[test]
    fn decoded_header_limit_is_inclusive_and_counts_repeated_fields() {
        let one_field_bytes = 1 + 3 + DECODED_HEADER_FIELD_OVERHEAD;
        let limits = RequestMetadataLimits::new(32, (one_field_bytes * 2) as u32, 2).unwrap();
        let exact = hyper::Request::builder()
            .version(hyper::Version::HTTP_10)
            .uri("/")
            .header("x", "one")
            .header("x", "two")
            .body(())
            .unwrap();
        let over_bytes = hyper::Request::builder()
            .version(hyper::Version::HTTP_10)
            .uri("/")
            .header("x", "one")
            .header("x", "tool")
            .body(())
            .unwrap();
        let over_fields = hyper::Request::builder()
            .version(hyper::Version::HTTP_10)
            .uri("/")
            .header("x", "")
            .header("y", "")
            .header("z", "")
            .body(())
            .unwrap();

        let (exact_parts, _) = exact.into_parts();
        let exact_metadata = RequestMetadata::validate_parts(&exact_parts).unwrap();
        let (over_bytes_parts, _) = over_bytes.into_parts();
        let over_bytes_metadata = RequestMetadata::validate_parts(&over_bytes_parts).unwrap();
        let (over_fields_parts, _) = over_fields.into_parts();
        let over_fields_metadata = RequestMetadata::validate_parts(&over_fields_parts).unwrap();

        assert_eq!(limits.admit_parts(&exact_parts, exact_metadata), Ok(()));
        assert!(matches!(
            limits.admit_parts(&over_bytes_parts, over_bytes_metadata),
            Err(RequestMetadataRejection::HeadersTooLarge { .. })
        ));
        assert!(matches!(
            limits.admit_parts(&over_fields_parts, over_fields_metadata),
            Err(RequestMetadataRejection::HeadersTooLarge { .. })
        ));
    }
}
