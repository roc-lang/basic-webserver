use crate::abi::roc_host;
use crate::bounded_gate::{AcquireError, BoundedGate};
use crate::http_error::{
    classify_client_error, classify_response_error, DnsError, Endpoint, TransportError,
};
use crate::roc_platform_abi::*;
use hyper::body::Body;
use std::future::Future;
use std::mem::ManuallyDrop;
use std::pin::Pin;
use std::sync::OnceLock;
use std::task::{Context, Poll};
use std::time::{Duration, Instant};
use tower_service::Service;

type HttpResponse = HostHttpSendRequestOk;
type HttpHeader = HostHttpSendRequestArg0Headers;
type AbiConnectReason = AddressNotAvailableOrConnectionAbortedOrConnectionRefusedOrConnectionResetOrHostUnreachableOrNetworkUnreachableOrOtherOrPermissionDeniedOrTimedOut;
type OutboundBody = http_body_util::Full<bytes::Bytes>;
type OutboundConnector = hyper_rustls::HttpsConnector<
    hyper_util::client::legacy::connect::HttpConnector<TypedDnsResolver>,
>;
type OutboundClient = hyper_util::client::legacy::Client<OutboundConnector, OutboundBody>;

#[derive(Debug)]
struct RequestBuildError {
    detail: String,
}

struct InternalResponse {
    status: u16,
    headers: Vec<(String, String)>,
    body: bytes::Bytes,
}

/// Preserve the DNS phase in the source chain while retaining Hyper's default
/// blocking `getaddrinfo` implementation.
#[derive(Clone)]
struct TypedDnsResolver {
    inner: hyper_util::client::legacy::connect::dns::GaiResolver,
}

impl TypedDnsResolver {
    fn new() -> Self {
        Self {
            inner: hyper_util::client::legacy::connect::dns::GaiResolver::new(),
        }
    }
}

impl Service<hyper_util::client::legacy::connect::dns::Name> for TypedDnsResolver {
    type Response = hyper_util::client::legacy::connect::dns::GaiAddrs;
    type Error = DnsError;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(&mut self, context: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        match self.inner.poll_ready(context) {
            Poll::Ready(Ok(())) => Poll::Ready(Ok(())),
            Poll::Ready(Err(error)) => Poll::Ready(Err(DnsError::new(error.to_string()))),
            Poll::Pending => Poll::Pending,
        }
    }

    fn call(&mut self, name: hyper_util::client::legacy::connect::dns::Name) -> Self::Future {
        let future = self.inner.call(name);
        Box::pin(async move {
            future
                .await
                .map_err(|error| DnsError::new(error.to_string()))
        })
    }
}

struct OutboundHttp {
    runtime: tokio::runtime::Runtime,
    client: OutboundClient,
}

static OUTBOUND_HTTP: OnceLock<OutboundHttp> = OnceLock::new();
static OUTBOUND_GATE: BoundedGate = BoundedGate::new(64, 256);

fn outbound_http() -> &'static OutboundHttp {
    OUTBOUND_HTTP.get_or_init(|| {
        use hyper_rustls::HttpsConnectorBuilder;
        use hyper_util::client::legacy::connect::HttpConnector;
        use hyper_util::client::legacy::Client;
        use hyper_util::rt::TokioExecutor;

        let runtime = tokio::runtime::Builder::new_multi_thread()
            .thread_name("roc-outbound-http")
            .enable_io()
            .enable_time()
            .build()
            .expect("failed to build outbound HTTP runtime");

        let mut http = HttpConnector::new_with_resolver(TypedDnsResolver::new());
        http.enforce_http(false);
        let https = HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_or_http()
            .enable_http1()
            .wrap_connector(http);
        let mut client_builder = Client::builder(TokioExecutor::new());
        // Even the legacy client's narrow "request was not transmitted" retry
        // is disabled: retry policy is observable application policy.
        client_builder.retry_canceled_requests(false);
        let client = client_builder.build(https);

        OutboundHttp { runtime, client }
    })
}

// Numeric method tags must match `to_host_method` in platform/InternalHttp.roc.
fn as_hyper_method(method: u8, method_ext: &str) -> Option<hyper::Method> {
    match method {
        0 => Some(hyper::Method::CONNECT),
        1 => Some(hyper::Method::DELETE),
        2 => hyper::Method::from_bytes(method_ext.as_bytes()).ok(),
        3 => Some(hyper::Method::GET),
        4 => Some(hyper::Method::HEAD),
        5 => Some(hyper::Method::OPTIONS),
        6 => Some(hyper::Method::PATCH),
        7 => Some(hyper::Method::POST),
        8 => Some(hyper::Method::PUT),
        9 => Some(hyper::Method::TRACE),
        _ => None,
    }
}

fn build_hyper_request_from_parts<'a>(
    method: u8,
    method_ext: &str,
    uri: &str,
    headers: impl IntoIterator<Item = (&'a str, &'a str)>,
    body: &[u8],
) -> Result<hyper::Request<http_body_util::Full<bytes::Bytes>>, RequestBuildError> {
    let method = as_hyper_method(method, method_ext).ok_or_else(|| RequestBuildError {
        detail: "invalid HTTP method".into(),
    })?;
    let mut builder = hyper::Request::builder().method(method).uri(uri);

    for (name, value) in headers {
        builder = builder.header(name, value);
    }

    let body = http_body_util::Full::new(bytes::Bytes::from(body.to_vec()));
    builder.body(body).map_err(|error| RequestBuildError {
        detail: error.to_string(),
    })
}

fn endpoint_for_request<B>(request: &hyper::Request<B>) -> Result<Endpoint, RequestBuildError> {
    Endpoint::from_uri(request.uri()).ok_or_else(|| RequestBuildError {
        detail: "outbound HTTP request must have an absolute http or https URL".into(),
    })
}

fn build_hyper_request(
    args: &HostHttpSendRequestArgs,
) -> Result<hyper::Request<http_body_util::Full<bytes::Bytes>>, RequestBuildError> {
    build_hyper_request_from_parts(
        args.method,
        args.method_ext.as_str(),
        args.uri.as_str(),
        args.headers
            .as_slice()
            .iter()
            .map(|header| (header.name.as_str(), header.value.as_str())),
        args.body.as_slice(),
    )
}

fn build_roc_headers(pairs: &[(String, String)], roc_host: &RocHost) -> RocList<HttpHeader> {
    // SAFETY: every allocated element is initialized below before return.
    let list = unsafe { RocList::<HttpHeader>::allocate(pairs.len(), roc_host) };
    for (index, (name, value)) in pairs.iter().enumerate() {
        let header = HttpHeader {
            name: RocStr::from_str(name, roc_host),
            value: RocStr::from_str(value, roc_host),
        };
        unsafe {
            list.elements.add(index).write(header);
        }
    }
    list
}

fn response_headers_to_strings(
    headers: &hyper::HeaderMap,
) -> Result<Vec<(String, String)>, TransportError> {
    headers
        .iter()
        .map(|(name, value)| {
            let value = value
                .to_str()
                .map_err(|_| TransportError::InvalidResponse {
                    detail: format!("response header '{}' is not valid UTF-8", name.as_str()),
                })?;
            Ok((name.as_str().to_string(), value.to_string()))
        })
        .collect()
}

async fn async_send_request(
    request: hyper::Request<http_body_util::Full<bytes::Bytes>>,
    endpoint: Endpoint,
    client: &OutboundClient,
    max_response_bytes: u64,
) -> Result<InternalResponse, TransportError> {
    use http_body_util::BodyExt;

    let mut response = client
        .request(request)
        .await
        .map_err(|error| classify_client_error(&error, &endpoint))?;
    let status = response.status().as_u16();
    let headers = response_headers_to_strings(response.headers())?;
    if let Some(content_length) = response.body().size_hint().exact() {
        if content_length > max_response_bytes {
            return Err(TransportError::ResponseTooLarge {
                limit_bytes: max_response_bytes,
                received_at_least: content_length,
            });
        }
    }

    let initial_capacity = response
        .body()
        .size_hint()
        .exact()
        .unwrap_or(0)
        .min(max_response_bytes)
        .min(64 * 1024)
        .try_into()
        .unwrap_or(64 * 1024);
    let mut body = Vec::with_capacity(initial_capacity);
    let mut received = 0u64;
    while let Some(frame) = response.body_mut().frame().await {
        let frame = frame.map_err(|error| classify_response_error(&error, &endpoint))?;
        if let Ok(data) = frame.into_data() {
            received = received.saturating_add(data.len() as u64);
            if received > max_response_bytes {
                return Err(TransportError::ResponseTooLarge {
                    limit_bytes: max_response_bytes,
                    received_at_least: received,
                });
            }
            body.extend_from_slice(&data);
        }
    }

    Ok(InternalResponse {
        status,
        headers,
        body: body.into(),
    })
}

fn internal_response_to_roc(response: InternalResponse, roc_host: &RocHost) -> HttpResponse {
    HttpResponse {
        // SAFETY: the returned list owns a copy of the body.
        body: unsafe { RocListWith::<u8, false>::from_slice(&response.body, roc_host) },
        headers: build_roc_headers(&response.headers, roc_host),
        status: response.status,
    }
}

#[cfg(not(target_pointer_width = "32"))]
fn make_http_result(
    payload: HostHttpSendRequestResultPayload,
    tag: HostHttpSendRequestResultTag,
) -> HostHttpSendRequestResult {
    HostHttpSendRequestResult { payload, tag }
}

#[cfg(target_pointer_width = "32")]
fn make_http_result(
    payload: HostHttpSendRequestResultPayload,
    tag: HostHttpSendRequestResultTag,
) -> HostHttpSendRequestResult {
    let mut result = HostHttpSendRequestResult {
        _payload_alignment: [],
        payload: [0; core::mem::size_of::<HostHttpSendRequestResultPayload>()],
        tag,
    };
    unsafe {
        (result.payload.as_mut_ptr() as *mut HostHttpSendRequestResultPayload).write(payload);
    }
    result
}

#[cfg(not(target_pointer_width = "32"))]
fn make_http_error(
    payload: HostHttpSendRequestErrPayload,
    tag: HostHttpSendRequestErrTag,
) -> HostHttpSendRequestErr {
    HostHttpSendRequestErr { payload, tag }
}

#[cfg(target_pointer_width = "32")]
fn make_http_error(
    payload: HostHttpSendRequestErrPayload,
    tag: HostHttpSendRequestErrTag,
) -> HostHttpSendRequestErr {
    let mut error = HostHttpSendRequestErr {
        _payload_alignment: [],
        payload: [0; core::mem::size_of::<HostHttpSendRequestErrPayload>()],
        tag,
    };
    unsafe {
        (error.payload.as_mut_ptr() as *mut HostHttpSendRequestErrPayload).write(payload);
    }
    error
}

#[cfg(not(target_pointer_width = "32"))]
fn make_transport(
    payload: HostHttpSendRequestErrTransportPayload,
    tag: HostHttpSendRequestErrTransportTag,
) -> HostHttpSendRequestErrTransport {
    HostHttpSendRequestErrTransport { payload, tag }
}

#[cfg(target_pointer_width = "32")]
fn make_transport(
    payload: HostHttpSendRequestErrTransportPayload,
    tag: HostHttpSendRequestErrTransportTag,
) -> HostHttpSendRequestErrTransport {
    let mut transport = HostHttpSendRequestErrTransport {
        _payload_alignment: [],
        payload: [0; core::mem::size_of::<HostHttpSendRequestErrTransportPayload>()],
        tag,
    };
    unsafe {
        (transport.payload.as_mut_ptr() as *mut HostHttpSendRequestErrTransportPayload)
            .write(payload);
    }
    transport
}

fn try_http_ok(response: HttpResponse) -> HostHttpSendRequestResult {
    make_http_result(
        HostHttpSendRequestResultPayload {
            ok: ManuallyDrop::new(response),
        },
        HostHttpSendRequestResultTag::Ok,
    )
}

fn try_http_err(error: HostHttpSendRequestErr) -> HostHttpSendRequestResult {
    make_http_result(
        HostHttpSendRequestResultPayload {
            err: ManuallyDrop::new(error),
        },
        HostHttpSendRequestResultTag::Err,
    )
}

fn invalid_request_error(detail: &str, roc_host: &RocHost) -> HostHttpSendRequestResult {
    try_http_err(make_http_error(
        HostHttpSendRequestErrPayload {
            invalid_request: ManuallyDrop::new(RocStr::from_str(detail, roc_host)),
        },
        HostHttpSendRequestErrTag::InvalidRequest,
    ))
}

fn connect_reason_to_abi(reason: crate::http_error::ConnectReason) -> AbiConnectReason {
    use crate::http_error::ConnectReason;
    match reason {
        ConnectReason::AddressNotAvailable => AbiConnectReason::AddressNotAvailable,
        ConnectReason::ConnectionAborted => AbiConnectReason::ConnectionAborted,
        ConnectReason::ConnectionRefused => AbiConnectReason::ConnectionRefused,
        ConnectReason::ConnectionReset => AbiConnectReason::ConnectionReset,
        ConnectReason::NetworkUnreachable => AbiConnectReason::NetworkUnreachable,
        ConnectReason::HostUnreachable => AbiConnectReason::HostUnreachable,
        ConnectReason::PermissionDenied => AbiConnectReason::PermissionDenied,
        ConnectReason::TimedOut => AbiConnectReason::TimedOut,
        ConnectReason::Other => AbiConnectReason::Other,
    }
}

fn transport_to_abi(error: TransportError, roc_host: &RocHost) -> HostHttpSendRequestErrTransport {
    let (payload, tag) = match error {
        TransportError::Timeout => (
            HostHttpSendRequestErrTransportPayload { timeout: [] },
            HostHttpSendRequestErrTransportTag::Timeout,
        ),
        TransportError::Saturated => (
            HostHttpSendRequestErrTransportPayload { saturated: [] },
            HostHttpSendRequestErrTransportTag::Saturated,
        ),
        TransportError::ResponseTooLarge {
            limit_bytes,
            received_at_least,
        } => (
            HostHttpSendRequestErrTransportPayload {
                response_too_large: ManuallyDrop::new(
                    HostHttpSendRequestErrTransportResponseTooLarge {
                        limit_bytes,
                        received_at_least,
                    },
                ),
            },
            HostHttpSendRequestErrTransportTag::ResponseTooLarge,
        ),
        TransportError::DnsFailed { host, detail } => (
            HostHttpSendRequestErrTransportPayload {
                dns_failed: ManuallyDrop::new(HostHttpSendRequestErrTransportDnsFailed {
                    detail: RocStr::from_str(&detail, roc_host),
                    host: RocStr::from_str(&host, roc_host),
                }),
            },
            HostHttpSendRequestErrTransportTag::DnsFailed,
        ),
        TransportError::ConnectFailed {
            host,
            port,
            reason,
            detail,
        } => (
            HostHttpSendRequestErrTransportPayload {
                connect_failed: ManuallyDrop::new(HostHttpSendRequestErrTransportConnectFailed {
                    detail: RocStr::from_str(&detail, roc_host),
                    host: RocStr::from_str(&host, roc_host),
                    port,
                    reason: connect_reason_to_abi(reason),
                }),
            },
            HostHttpSendRequestErrTransportTag::ConnectFailed,
        ),
        TransportError::TlsFailed { host, detail } => (
            HostHttpSendRequestErrTransportPayload {
                tls_failed: ManuallyDrop::new(HostHttpSendRequestErrTransportTlsFailed {
                    detail: RocStr::from_str(&detail, roc_host),
                    host: RocStr::from_str(&host, roc_host),
                }),
            },
            HostHttpSendRequestErrTransportTag::TlsFailed,
        ),
        TransportError::ConnectionClosed => (
            HostHttpSendRequestErrTransportPayload {
                connection_closed: [],
            },
            HostHttpSendRequestErrTransportTag::ConnectionClosed,
        ),
        TransportError::ExchangeFailed { detail } => (
            HostHttpSendRequestErrTransportPayload {
                exchange_failed: ManuallyDrop::new(RocStr::from_str(&detail, roc_host)),
            },
            HostHttpSendRequestErrTransportTag::ExchangeFailed,
        ),
        TransportError::ResponseBodyFailed { detail } => (
            HostHttpSendRequestErrTransportPayload {
                response_body_failed: ManuallyDrop::new(RocStr::from_str(&detail, roc_host)),
            },
            HostHttpSendRequestErrTransportTag::ResponseBodyFailed,
        ),
        TransportError::InvalidResponse { detail } => (
            HostHttpSendRequestErrTransportPayload {
                invalid_response: ManuallyDrop::new(RocStr::from_str(&detail, roc_host)),
            },
            HostHttpSendRequestErrTransportTag::InvalidResponse,
        ),
        TransportError::Cancelled => (
            HostHttpSendRequestErrTransportPayload { cancelled: [] },
            HostHttpSendRequestErrTransportTag::Cancelled,
        ),
        TransportError::Other { detail } => (
            HostHttpSendRequestErrTransportPayload {
                other: ManuallyDrop::new(RocStr::from_str(&detail, roc_host)),
            },
            HostHttpSendRequestErrTransportTag::Other,
        ),
    };

    make_transport(payload, tag)
}

fn transport_error(error: TransportError, roc_host: &RocHost) -> HostHttpSendRequestResult {
    try_http_err(make_http_error(
        HostHttpSendRequestErrPayload {
            transport: ManuallyDrop::new(transport_to_abi(error, roc_host)),
        },
        HostHttpSendRequestErrTag::Transport,
    ))
}

#[no_mangle]
pub extern "C" fn hosted_http_send_request(
    args: HostHttpSendRequestArgs,
) -> HostHttpSendRequestResult {
    let roc_host = roc_host();
    let timeout_ms = args.timeout_ms.max(1);
    let max_response_bytes = args.max_response_bytes;
    let deadline = Instant::now()
        .checked_add(Duration::from_millis(timeout_ms))
        .unwrap_or_else(Instant::now);

    // Build the hyper request from borrowed args, then release the owned Roc
    // values after the request has copied everything it needs.
    let request_result = build_hyper_request(&args);
    unsafe { args.body.decref(roc_host) };
    for header in args.headers.as_slice() {
        unsafe { header.decref(roc_host) };
    }
    unsafe { args.headers.decref(roc_host) };
    unsafe { args.method_ext.decref(roc_host) };
    unsafe { args.uri.decref(roc_host) };

    let request = match request_result {
        Ok(request) => request,
        Err(error) => return invalid_request_error(&error.detail, roc_host),
    };
    let endpoint = match endpoint_for_request(&request) {
        Ok(endpoint) => endpoint,
        Err(error) => return invalid_request_error(&error.detail, roc_host),
    };

    let _permit = match OUTBOUND_GATE.acquire(deadline) {
        Ok(permit) => permit,
        Err(AcquireError::Saturated) => {
            return transport_error(TransportError::Saturated, roc_host)
        }
        Err(AcquireError::TimedOut) => return transport_error(TransportError::Timeout, roc_host),
    };
    let remaining = deadline.saturating_duration_since(Instant::now());
    if remaining.is_zero() {
        return transport_error(TransportError::Timeout, roc_host);
    }

    let outbound = outbound_http();
    let result = outbound.runtime.block_on(async {
        match tokio::time::timeout(
            remaining,
            async_send_request(request, endpoint, &outbound.client, max_response_bytes),
        )
        .await
        {
            Ok(response) => response,
            Err(_) => Err(TransportError::Timeout),
        }
    });

    match result {
        Ok(response) => try_http_ok(internal_response_to_roc(response, roc_host)),
        Err(error) => transport_error(error, roc_host),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};

    #[test]
    fn maps_host_method_tags_to_hyper_methods() {
        assert_eq!(as_hyper_method(3, ""), Some(hyper::Method::GET));
        assert_eq!(as_hyper_method(7, ""), Some(hyper::Method::POST));
        assert_eq!(
            as_hyper_method(2, "QUERY"),
            Some(hyper::Method::from_bytes(b"QUERY").unwrap())
        );
        assert_eq!(
            as_hyper_method(2, "PROPFIND"),
            Some(hyper::Method::from_bytes(b"PROPFIND").unwrap())
        );
        assert_eq!(as_hyper_method(10, ""), None);
        assert_eq!(as_hyper_method(255, ""), None);
    }

    #[test]
    fn build_request_does_not_fabricate_content_type() {
        let request = build_hyper_request_from_parts(
            7,
            "",
            "http://example.com/",
            std::iter::empty(),
            b"hello",
        )
        .unwrap();

        assert_eq!(request.method(), hyper::Method::POST);
        assert!(!request.headers().contains_key("content-type"));
    }

    #[test]
    fn outbound_runtime_and_client_are_shared_and_multithreaded() {
        let first = outbound_http();
        let second = outbound_http();

        assert!(core::ptr::eq(first, second));
        assert_eq!(
            first.runtime.handle().runtime_flavor(),
            tokio::runtime::RuntimeFlavor::MultiThread
        );
    }

    #[test]
    fn build_request_preserves_explicit_content_type() {
        let request = build_hyper_request_from_parts(
            7,
            "",
            "http://example.com/",
            [("Content-Type", "application/json")],
            b"{}",
        )
        .unwrap();

        assert_eq!(request.headers()["content-type"], "application/json");
        assert_eq!(request.headers().get_all("content-type").iter().count(), 1);
    }

    #[test]
    fn invalid_request_construction_is_separate_from_transport_errors() {
        let request =
            build_hyper_request_from_parts(7, "", "/relative", std::iter::empty(), b"").unwrap();
        assert_eq!(
            endpoint_for_request(&request).unwrap_err().detail,
            "outbound HTTP request must have an absolute http or https URL"
        );

        assert_eq!(
            build_hyper_request_from_parts(
                255,
                "",
                "https://example.test/",
                std::iter::empty(),
                b"",
            )
            .unwrap_err()
            .detail,
            "invalid HTTP method"
        );
    }

    #[test]
    fn non_utf8_response_headers_are_invalid_responses() {
        let mut headers = hyper::HeaderMap::new();
        headers.insert(
            "x-binary",
            hyper::header::HeaderValue::from_bytes(&[0xff]).unwrap(),
        );
        assert_eq!(
            response_headers_to_strings(&headers),
            Err(TransportError::InvalidResponse {
                detail: "response header 'x-binary' is not valid UTF-8".into(),
            })
        );
    }

    #[test]
    fn chunked_response_limit_is_enforced_before_materialization() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0u8; 1024];
            let _ = stream.read(&mut request).unwrap();
            stream
                .write_all(
                    b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n4\r\n1234\r\n5\r\n56789\r\n0\r\n\r\n",
                )
                .unwrap();
        });

        let uri: hyper::Uri = format!("http://{address}/").parse().unwrap();
        let endpoint = Endpoint::from_uri(&uri).unwrap();
        let request = hyper::Request::builder()
            .uri(uri)
            .body(http_body_util::Full::new(bytes::Bytes::new()))
            .unwrap();
        let outbound = outbound_http();
        let result =
            outbound
                .runtime
                .block_on(async_send_request(request, endpoint, &outbound.client, 6));
        server.join().unwrap();

        assert!(matches!(
            result,
            Err(TransportError::ResponseTooLarge {
                limit_bytes: 6,
                received_at_least,
            }) if received_at_least > 6
        ));
    }

    #[test]
    fn connect_reasons_match_the_roc_transport_union() {
        use crate::http_error::ConnectReason;
        let cases = [
            (
                ConnectReason::AddressNotAvailable,
                AbiConnectReason::AddressNotAvailable,
            ),
            (
                ConnectReason::ConnectionAborted,
                AbiConnectReason::ConnectionAborted,
            ),
            (
                ConnectReason::ConnectionRefused,
                AbiConnectReason::ConnectionRefused,
            ),
            (
                ConnectReason::ConnectionReset,
                AbiConnectReason::ConnectionReset,
            ),
            (
                ConnectReason::HostUnreachable,
                AbiConnectReason::HostUnreachable,
            ),
            (
                ConnectReason::NetworkUnreachable,
                AbiConnectReason::NetworkUnreachable,
            ),
            (
                ConnectReason::PermissionDenied,
                AbiConnectReason::PermissionDenied,
            ),
            (ConnectReason::TimedOut, AbiConnectReason::TimedOut),
            (ConnectReason::Other, AbiConnectReason::Other),
        ];
        for (internal, abi) in cases {
            assert_eq!(connect_reason_to_abi(internal), abi);
        }
    }
}
