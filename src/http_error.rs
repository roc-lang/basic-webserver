//! Typed internal classification for outbound HTTP transport failures.
//!
//! Classification uses concrete error types, public Hyper predicates, and
//! `io::ErrorKind`. Display strings are retained only as user-facing detail;
//! they never decide an error category.

use std::error::Error;
use std::fmt;
use std::io;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct Endpoint {
    pub(crate) host: String,
    pub(crate) port: u16,
}

impl Endpoint {
    pub(crate) fn from_uri(uri: &hyper::Uri) -> Option<Self> {
        let host = uri.host()?.to_string();
        let default_port = match uri.scheme_str() {
            Some("http") => 80,
            Some("https") => 443,
            _ => return None,
        };
        let port = uri.port_u16().unwrap_or(default_port);
        Some(Self { host, port })
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ConnectReason {
    AddressNotAvailable,
    ConnectionAborted,
    ConnectionRefused,
    ConnectionReset,
    NetworkUnreachable,
    HostUnreachable,
    PermissionDenied,
    TimedOut,
    Other,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum TransportError {
    Timeout,
    Saturated,
    ResponseTooLarge {
        limit_bytes: u64,
        received_at_least: u64,
    },
    DnsFailed {
        host: String,
        detail: String,
    },
    ConnectFailed {
        host: String,
        port: u16,
        reason: ConnectReason,
        detail: String,
    },
    TlsFailed {
        host: String,
        detail: String,
    },
    ConnectionClosed,
    ExchangeFailed {
        detail: String,
    },
    ResponseBodyFailed {
        detail: String,
    },
    InvalidResponse {
        detail: String,
    },
    Cancelled,
    Other {
        detail: String,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Connecting,
    Exchanging,
    ReadingResponseBody,
}

/// Marker for a future custom resolver. The default Hyper resolver exposes its
/// failures as `io::Error`, so `NotFound` is also treated as DNS failure.
#[derive(Debug)]
pub(crate) struct DnsError {
    detail: String,
}

impl DnsError {
    pub(crate) fn new(detail: impl Into<String>) -> Self {
        Self {
            detail: detail.into(),
        }
    }
}

impl fmt::Display for DnsError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.detail)
    }
}

impl Error for DnsError {}

fn find_source<'a, T: Error + 'static>(error: &'a (dyn Error + 'static)) -> Option<&'a T> {
    let mut current = Some(error);
    while let Some(source) = current {
        if let Some(found) = source.downcast_ref::<T>() {
            return Some(found);
        }
        // std::io::Error's Error::source implementation can skip the immediate
        // custom payload and expose that payload's own source instead. Inspect
        // get_ref explicitly so a rustls::Error wrapped with io::Error::other
        // remains discoverable by concrete type.
        if let Some(io_error) = source.downcast_ref::<io::Error>() {
            if let Some(inner) = io_error.get_ref() {
                if let Some(found) = find_source::<T>(inner) {
                    return Some(found);
                }
            }
        }
        current = source.source();
    }
    None
}

fn find_hyper_error<'a>(error: &'a (dyn Error + 'static)) -> Option<&'a hyper::Error> {
    find_source(error)
}

fn diagnostic(error: &(dyn Error + 'static)) -> String {
    let mut current = error;
    while let Some(source) = current.source() {
        current = source;
    }
    current.to_string()
}

fn connect_reason(kind: io::ErrorKind) -> ConnectReason {
    match kind {
        io::ErrorKind::ConnectionRefused => ConnectReason::ConnectionRefused,
        io::ErrorKind::ConnectionReset => ConnectReason::ConnectionReset,
        io::ErrorKind::ConnectionAborted => ConnectReason::ConnectionAborted,
        io::ErrorKind::AddrInUse | io::ErrorKind::AddrNotAvailable => {
            ConnectReason::AddressNotAvailable
        }
        io::ErrorKind::NetworkUnreachable => ConnectReason::NetworkUnreachable,
        io::ErrorKind::HostUnreachable => ConnectReason::HostUnreachable,
        io::ErrorKind::PermissionDenied => ConnectReason::PermissionDenied,
        io::ErrorKind::TimedOut => ConnectReason::TimedOut,
        _ => ConnectReason::Other,
    }
}

fn is_closed_io(kind: io::ErrorKind) -> bool {
    matches!(
        kind,
        io::ErrorKind::BrokenPipe
            | io::ErrorKind::ConnectionAborted
            | io::ErrorKind::ConnectionReset
            | io::ErrorKind::NotConnected
            | io::ErrorKind::UnexpectedEof
    )
}

fn classify(error: &(dyn Error + 'static), endpoint: &Endpoint, phase: Phase) -> TransportError {
    let hyper_error = find_hyper_error(error);
    let io_error = find_source::<io::Error>(error);

    // Cancellation and timeout are independent of the transport phase and
    // take precedence over errors they may wrap.
    if hyper_error.is_some_and(hyper::Error::is_canceled)
        || io_error.is_some_and(|error| error.kind() == io::ErrorKind::Interrupted)
    {
        return TransportError::Cancelled;
    }
    if hyper_error.is_some_and(hyper::Error::is_timeout)
        || (phase != Phase::Connecting
            && io_error.is_some_and(|error| error.kind() == io::ErrorKind::TimedOut))
    {
        return TransportError::Timeout;
    }

    if let Some(error) = find_source::<rustls::Error>(error) {
        return TransportError::TlsFailed {
            host: endpoint.host.clone(),
            detail: error.to_string(),
        };
    }

    if hyper_error.is_some_and(hyper::Error::is_parse)
        || (phase == Phase::ReadingResponseBody
            && io_error.is_some_and(|error| error.kind() == io::ErrorKind::InvalidData))
    {
        return TransportError::InvalidResponse {
            detail: diagnostic(error),
        };
    }

    if hyper_error.is_some_and(|error| error.is_closed() || error.is_incomplete_message())
        || io_error.is_some_and(|error| {
            is_closed_io(error.kind())
                && (phase != Phase::Connecting
                    || matches!(
                        error.kind(),
                        io::ErrorKind::BrokenPipe | io::ErrorKind::UnexpectedEof
                    ))
        })
    {
        return TransportError::ConnectionClosed;
    }

    if phase == Phase::Connecting {
        if let Some(error) = find_source::<DnsError>(error) {
            return TransportError::DnsFailed {
                host: endpoint.host.clone(),
                detail: error.to_string(),
            };
        }
        if let Some(error) = io_error {
            // The default GAI resolver returns an io::Error and does not expose
            // a public DNS marker. NotFound is the one portable kind that does
            // not represent a TCP connect failure.
            if error.kind() == io::ErrorKind::NotFound {
                return TransportError::DnsFailed {
                    host: endpoint.host.clone(),
                    detail: error.to_string(),
                };
            }
            return TransportError::ConnectFailed {
                host: endpoint.host.clone(),
                port: endpoint.port,
                reason: connect_reason(error.kind()),
                detail: error.to_string(),
            };
        }
    }

    match phase {
        Phase::Connecting => TransportError::Other {
            detail: diagnostic(error),
        },
        // Client::request covers both writing the request and waiting for
        // response headers. Hyper does not expose enough phase information to
        // split those failures honestly.
        Phase::Exchanging => TransportError::ExchangeFailed {
            detail: diagnostic(error),
        },
        Phase::ReadingResponseBody => TransportError::ResponseBodyFailed {
            detail: diagnostic(error),
        },
    }
}

pub(crate) fn classify_client_error(
    error: &hyper_util::client::legacy::Error,
    endpoint: &Endpoint,
) -> TransportError {
    let phase = if error.is_connect() {
        Phase::Connecting
    } else {
        Phase::Exchanging
    };
    classify(error, endpoint, phase)
}

pub(crate) fn classify_response_error(error: &hyper::Error, endpoint: &Endpoint) -> TransportError {
    classify(error, endpoint, Phase::ReadingResponseBody)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn endpoint() -> Endpoint {
        Endpoint {
            host: "example.test".into(),
            port: 443,
        }
    }

    #[test]
    fn extracts_endpoint_and_default_ports() {
        assert_eq!(
            Endpoint::from_uri(&"https://example.test/path".parse().unwrap()),
            Some(endpoint())
        );
        assert_eq!(
            Endpoint::from_uri(&"http://example.test/path".parse().unwrap()),
            Some(Endpoint {
                host: "example.test".into(),
                port: 80,
            })
        );
        assert_eq!(
            Endpoint::from_uri(&"https://example.test:8443/".parse().unwrap()),
            Some(Endpoint {
                host: "example.test".into(),
                port: 8443,
            })
        );
        assert_eq!(
            Endpoint::from_uri(&"ftp://example.test:21/".parse().unwrap()),
            None
        );
    }

    #[test]
    fn os_connect_timeout_has_a_typed_connect_reason() {
        let error = io::Error::new(io::ErrorKind::TimedOut, "connect timed out");
        assert_eq!(
            classify(&error, &endpoint(), Phase::Connecting),
            TransportError::ConnectFailed {
                host: "example.test".into(),
                port: 443,
                reason: ConnectReason::TimedOut,
                detail: "connect timed out".into(),
            }
        );
    }

    #[test]
    fn interrupted_takes_precedence_over_phase_fallback() {
        let error = io::Error::new(io::ErrorKind::Interrupted, "cancelled");
        assert_eq!(
            classify(&error, &endpoint(), Phase::ReadingResponseBody),
            TransportError::Cancelled
        );
    }

    #[test]
    fn finds_tls_error_through_io_source_chain() {
        let tls = rustls::Error::General("bad certificate".into());
        let expected_detail = tls.to_string();
        let error = io::Error::other(tls);
        assert_eq!(
            classify(&error, &endpoint(), Phase::Connecting),
            TransportError::TlsFailed {
                host: "example.test".into(),
                detail: expected_detail,
            }
        );
    }

    #[test]
    fn explicit_dns_marker_beats_connect_fallback() {
        let error = DnsError::new("name has no address");
        assert_eq!(
            classify(&error, &endpoint(), Phase::Connecting),
            TransportError::DnsFailed {
                host: "example.test".into(),
                detail: "name has no address".into(),
            }
        );
    }

    #[test]
    fn not_found_io_error_is_dns_failure_while_connecting() {
        let error = io::Error::new(io::ErrorKind::NotFound, "no records");
        assert_eq!(
            classify(&error, &endpoint(), Phase::Connecting),
            TransportError::DnsFailed {
                host: "example.test".into(),
                detail: "no records".into(),
            }
        );
    }

    #[test]
    fn connect_io_kinds_have_stable_reasons() {
        let cases = [
            (
                io::ErrorKind::ConnectionRefused,
                ConnectReason::ConnectionRefused,
            ),
            (
                io::ErrorKind::ConnectionReset,
                ConnectReason::ConnectionReset,
            ),
            (
                io::ErrorKind::ConnectionAborted,
                ConnectReason::ConnectionAborted,
            ),
            (io::ErrorKind::NotConnected, ConnectReason::Other),
            (io::ErrorKind::AddrInUse, ConnectReason::AddressNotAvailable),
            (
                io::ErrorKind::AddrNotAvailable,
                ConnectReason::AddressNotAvailable,
            ),
            (
                io::ErrorKind::NetworkUnreachable,
                ConnectReason::NetworkUnreachable,
            ),
            (
                io::ErrorKind::HostUnreachable,
                ConnectReason::HostUnreachable,
            ),
            (
                io::ErrorKind::PermissionDenied,
                ConnectReason::PermissionDenied,
            ),
            (io::ErrorKind::TimedOut, ConnectReason::TimedOut),
            (io::ErrorKind::Unsupported, ConnectReason::Other),
            (io::ErrorKind::Other, ConnectReason::Other),
        ];

        for (kind, expected_reason) in cases {
            let error = io::Error::new(kind, "connect detail");
            assert_eq!(
                classify(&error, &endpoint(), Phase::Connecting),
                TransportError::ConnectFailed {
                    host: "example.test".into(),
                    port: 443,
                    reason: expected_reason,
                    detail: "connect detail".into(),
                },
                "unexpected classification for {kind:?}"
            );
        }
    }

    #[test]
    fn closed_io_kinds_take_precedence_over_connect_reason() {
        let error = io::Error::new(io::ErrorKind::BrokenPipe, "closed");
        assert_eq!(
            classify(&error, &endpoint(), Phase::Connecting),
            TransportError::ConnectionClosed
        );
    }

    #[test]
    fn response_invalid_data_is_invalid_response() {
        let error = io::Error::new(io::ErrorKind::InvalidData, "bad status line");
        assert_eq!(
            classify(&error, &endpoint(), Phase::ReadingResponseBody),
            TransportError::InvalidResponse {
                detail: "bad status line".into(),
            }
        );
    }

    #[test]
    fn phase_fallbacks_name_only_observable_exchange_stages() {
        let opaque = DnsError::new("opaque");
        assert_eq!(
            classify(&opaque, &endpoint(), Phase::Exchanging),
            TransportError::ExchangeFailed {
                detail: "opaque".into(),
            }
        );
        assert_eq!(
            classify(&opaque, &endpoint(), Phase::ReadingResponseBody),
            TransportError::ResponseBodyFailed {
                detail: "opaque".into(),
            }
        );
        assert_eq!(
            classify(&opaque, &endpoint(), Phase::Connecting),
            TransportError::DnsFailed {
                host: "example.test".into(),
                detail: "opaque".into(),
            }
        );

        let io_error = io::Error::other("exchange failed");
        assert_eq!(
            classify(&io_error, &endpoint(), Phase::Exchanging),
            TransportError::ExchangeFailed {
                detail: "exchange failed".into(),
            }
        );
    }
}
