//! Protocol-independent response validation and framing.
//!
//! Roc supplies response semantics; the host owns message framing. Every
//! response passes through this module before Hyper sees it, including native
//! file responses and host-generated errors. Keeping the rules here makes the
//! HTTP/1.1 and HTTP/2 contracts independent of encoder-specific cleanup.

pub(crate) use crate::response_body::ServerData;
use bytes::Bytes;
use http_body_util::{combinators::UnsyncBoxBody, BodyExt, Empty, Full};
use hyper::body::Body;
use hyper::header::{HeaderName, HeaderValue, CONTENT_LENGTH};
use hyper::{HeaderMap, Method, StatusCode, Version};
use std::fmt;
use std::io;

pub(crate) type ServerBody = UnsyncBoxBody<ServerData, io::Error>;
pub(crate) type ServerResponse = hyper::Response<ServerBody>;

const CONNECTION_SPECIFIC_FIELDS: &[&str] = &[
    "connection",
    "http2-settings",
    "keep-alive",
    "proxy-connection",
    "te",
    "transfer-encoding",
    "upgrade",
];
const UNSUPPORTED_TRAILER_FIELD: &str = "trailer";

#[derive(Clone, Debug)]
pub(crate) struct RequestSemantics {
    pub(crate) method: Method,
    pub(crate) version: Version,
}

impl RequestSemantics {
    pub(crate) fn from_request<B>(request: &hyper::Request<B>) -> Self {
        Self {
            method: request.method().clone(),
            version: request.version(),
        }
    }

    fn protocol_name(&self) -> &'static str {
        match self.version {
            Version::HTTP_2 => "HTTP/2",
            Version::HTTP_10 | Version::HTTP_11 => "HTTP/1",
            _ => "HTTP",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ResponseError(String);

impl ResponseError {
    fn new(detail: impl Into<String>) -> Self {
        Self(detail.into())
    }
}

impl fmt::Display for ResponseError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

pub(crate) fn full_body(bytes: Bytes) -> ServerBody {
    Full::new(ServerData::from(bytes))
        .map_err(|never| match never {})
        .boxed_unsync()
}

pub(crate) fn empty_body() -> ServerBody {
    Empty::<ServerData>::new()
        .map_err(|never| match never {})
        .boxed_unsync()
}

/// Validate application-supplied status and headers, and replace any accepted
/// Content-Length fields with one canonical host-owned value.
pub(crate) fn application_parts<'a>(
    raw_status: u16,
    raw_headers: impl IntoIterator<Item = (&'a str, &'a str)>,
    representation_length: u64,
    request: &RequestSemantics,
) -> Result<(StatusCode, HeaderMap), ResponseError> {
    let status = StatusCode::from_u16(raw_status)
        .map_err(|_| ResponseError::new(format!("invalid response status {raw_status}")))?;
    let length_rule = length_rule(status, request)?;
    if (matches!(length_rule, LengthRule::Forbidden) || status == StatusCode::RESET_CONTENT)
        && representation_length != 0
    {
        return Err(ResponseError::new(format!(
            "status {status} forbids response content"
        )));
    }

    let mut headers = HeaderMap::new();
    let mut supplied_lengths = Vec::new();
    for (raw_name, raw_value) in raw_headers {
        let name = HeaderName::from_bytes(raw_name.as_bytes()).map_err(|_| {
            ResponseError::new(format!("invalid response header name {raw_name:?}"))
        })?;
        let value = HeaderValue::from_str(raw_value).map_err(|_| {
            ResponseError::new(format!("invalid value for response header {raw_name:?}"))
        })?;
        if is_connection_specific(&name) || name.as_str() == UNSUPPORTED_TRAILER_FIELD {
            return Err(ResponseError::new(format!(
                "{} response field {name:?} controls unsupported connection framing or trailers",
                request.protocol_name()
            )));
        }
        if name == CONTENT_LENGTH {
            supplied_lengths.extend(parse_content_length_value(value.as_bytes())?);
        } else {
            headers.append(name, value);
        }
    }

    let supplied_length = one_content_length(&supplied_lengths)?;
    match length_rule {
        LengthRule::Forbidden => {
            if supplied_length.is_some() {
                return Err(ResponseError::new(format!(
                    "status {status} forbids Content-Length"
                )));
            }
        }
        LengthRule::Representation => {
            if let Some(supplied) = supplied_length {
                if supplied != representation_length {
                    return Err(ResponseError::new(format!(
                        "Content-Length {supplied} does not match the {representation_length}-byte response representation"
                    )));
                }
            }
            set_content_length(&mut headers, representation_length);
        }
    }
    Ok((status, headers))
}

/// Apply the same framing invariants to application, native, and host-generated
/// responses immediately before protocol transmission.
pub(crate) fn finalize_response(
    mut response: ServerResponse,
    request: &RequestSemantics,
) -> Result<ServerResponse, ResponseError> {
    let status = response.status();
    let length_rule = length_rule(status, request)?;
    for name in response.headers().keys() {
        if is_connection_specific(name) || name.as_str() == UNSUPPORTED_TRAILER_FIELD {
            return Err(ResponseError::new(format!(
                "host response contained unsupported connection framing or trailer field {name:?}"
            )));
        }
    }
    let supplied_lengths = response
        .headers()
        .get_all(CONTENT_LENGTH)
        .iter()
        .map(|value| parse_content_length_value(value.as_bytes()))
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .flatten()
        .collect::<Vec<_>>();
    let supplied_length = one_content_length(&supplied_lengths)?;
    let body_length = response.body().size_hint().exact();
    if status == StatusCode::RESET_CONTENT && body_length != Some(0) {
        return Err(ResponseError::new(
            "status 205 Reset Content forbids response content",
        ));
    }

    match length_rule {
        LengthRule::Forbidden => {
            if supplied_length.is_some() {
                return Err(ResponseError::new(format!(
                    "status {status} forbids Content-Length"
                )));
            }
            if body_length != Some(0) {
                return Err(ResponseError::new(format!(
                    "status {status} forbids response content"
                )));
            }
            response.headers_mut().remove(CONTENT_LENGTH);
        }
        LengthRule::Representation if request.method == Method::HEAD => {
            // Native responses can arrive with the body already suppressed and
            // a representation length in the header. Complete ordinary and
            // host error responses still carry their representation here.
            let representation_length = match (supplied_length, body_length) {
                (Some(length), Some(0)) => Some(length),
                (Some(length), Some(body_length)) if length == body_length => Some(length),
                (Some(length), Some(body_length)) => {
                    return Err(ResponseError::new(format!(
                        "Content-Length {length} does not match the {body_length}-byte response representation"
                    )));
                }
                (Some(_), None) => {
                    return Err(ResponseError::new(
                        "Content-Length cannot frame a response body with an unknown encoded length",
                    ));
                }
                (None, Some(0)) | (None, None) => None,
                (None, Some(body_length)) => Some(body_length),
            };
            if let Some(representation_length) = representation_length {
                set_content_length(response.headers_mut(), representation_length);
            } else {
                response.headers_mut().remove(CONTENT_LENGTH);
            }
            *response.body_mut() = empty_body();
        }
        LengthRule::Representation => match (supplied_length, body_length) {
            (Some(length), Some(body_length)) if length != body_length => {
                return Err(ResponseError::new(format!(
                    "Content-Length {length} does not match the {body_length}-byte response body"
                )));
            }
            (Some(_), None) => {
                return Err(ResponseError::new(
                    "Content-Length cannot frame a response body with an unknown encoded length",
                ));
            }
            (_, Some(body_length)) => {
                set_content_length(response.headers_mut(), body_length);
            }
            (None, None) => {
                response.headers_mut().remove(CONTENT_LENGTH);
            }
        },
    }
    Ok(response)
}

pub(crate) fn safe_internal_server_error(request: &RequestSemantics) -> ServerResponse {
    let mut response =
        hyper::Response::new(full_body(Bytes::from_static(b"500 Internal Server Error")));
    *response.status_mut() = StatusCode::INTERNAL_SERVER_ERROR;
    response.headers_mut().insert(
        hyper::header::CONTENT_TYPE,
        HeaderValue::from_static("text/plain; charset=utf-8"),
    );
    finalize_response(response, request).expect("the static safe 500 response must be valid")
}

fn length_rule(
    status: StatusCode,
    request: &RequestSemantics,
) -> Result<LengthRule, ResponseError> {
    if status.is_informational() {
        return Err(ResponseError::new(
            "ordinary responses cannot be informational because no final response would follow",
        ));
    }
    if request.method == Method::CONNECT && status.is_success() {
        return Err(ResponseError::new(
            "a successful CONNECT requires an unsupported tunnel outcome",
        ));
    }
    if status == StatusCode::NO_CONTENT || status == StatusCode::NOT_MODIFIED {
        Ok(LengthRule::Forbidden)
    } else {
        Ok(LengthRule::Representation)
    }
}

#[derive(Clone, Copy)]
enum LengthRule {
    Forbidden,
    Representation,
}

fn is_connection_specific(name: &HeaderName) -> bool {
    CONNECTION_SPECIFIC_FIELDS
        .iter()
        .any(|forbidden| name.as_str() == *forbidden)
}

fn parse_content_length_value(value: &[u8]) -> Result<Vec<u64>, ResponseError> {
    let text = std::str::from_utf8(value)
        .map_err(|_| ResponseError::new("Content-Length is not valid ASCII"))?;
    text.split(',')
        .map(|part| {
            let digits = part.trim_matches([' ', '\t']);
            if digits.is_empty() || !digits.bytes().all(|byte| byte.is_ascii_digit()) {
                return Err(ResponseError::new(format!(
                    "invalid Content-Length value {text:?}"
                )));
            }
            digits
                .parse::<u64>()
                .map_err(|_| ResponseError::new(format!("invalid Content-Length value {text:?}")))
        })
        .collect()
}

fn one_content_length(lengths: &[u64]) -> Result<Option<u64>, ResponseError> {
    let Some((&first, rest)) = lengths.split_first() else {
        return Ok(None);
    };
    if rest.iter().any(|length| *length != first) {
        return Err(ResponseError::new(
            "conflicting Content-Length field values",
        ));
    }
    Ok(Some(first))
}

fn set_content_length(headers: &mut HeaderMap, length: u64) {
    headers.remove(CONTENT_LENGTH);
    headers.insert(
        CONTENT_LENGTH,
        HeaderValue::from_str(&length.to_string())
            .expect("a decimal u64 is a valid Content-Length"),
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use http_body_util::{BodyExt, Full};
    use hyper::service::service_fn;
    use hyper_util::rt::{TokioExecutor, TokioIo};
    use std::convert::Infallible;

    #[derive(Clone)]
    struct ApplicationCase {
        name: &'static str,
        method: Method,
        status: u16,
        headers: Vec<(&'static str, &'static str)>,
        body: &'static [u8],
        expected_status: StatusCode,
        expected_body: &'static [u8],
        expected_content_length: Option<u64>,
    }

    impl ApplicationCase {
        fn valid(
            name: &'static str,
            method: Method,
            status: u16,
            headers: Vec<(&'static str, &'static str)>,
            body: &'static [u8],
            expected_body: &'static [u8],
            expected_content_length: Option<u64>,
        ) -> Self {
            Self {
                name,
                method,
                status,
                headers,
                body,
                expected_status: StatusCode::from_u16(status).unwrap(),
                expected_body,
                expected_content_length,
            }
        }

        fn invalid(
            name: &'static str,
            method: Method,
            status: u16,
            headers: Vec<(&'static str, &'static str)>,
            body: &'static [u8],
        ) -> Self {
            Self {
                name,
                method,
                status,
                headers,
                body,
                expected_status: StatusCode::INTERNAL_SERVER_ERROR,
                expected_body: b"500 Internal Server Error",
                expected_content_length: Some(25),
            }
        }
    }

    fn application_response_for_wire(
        case: &ApplicationCase,
        semantics: &RequestSemantics,
    ) -> ServerResponse {
        let unframed = match application_parts(
            case.status,
            case.headers.iter().copied(),
            case.body.len() as u64,
            semantics,
        ) {
            Ok((status, headers)) => {
                let mut response = hyper::Response::new(full_body(Bytes::from_static(case.body)));
                *response.status_mut() = status;
                *response.headers_mut() = headers;
                response
            }
            Err(_) => return safe_internal_server_error(semantics),
        };
        finalize_response(unframed, semantics)
            .unwrap_or_else(|_| safe_internal_server_error(semantics))
    }

    async fn wire_exchange(
        version: Version,
        case: ApplicationCase,
    ) -> (StatusCode, HeaderMap, Bytes) {
        let semantics = RequestSemantics {
            method: case.method.clone(),
            version,
        };
        let (client_io, server_io) = tokio::io::duplex(64 * 1024);
        let server_semantics = semantics.clone();
        let server_case = case.clone();
        let server = tokio::spawn(async move {
            let service = service_fn(move |_request| {
                let response = application_response_for_wire(&server_case, &server_semantics);
                async move { Ok::<_, Infallible>(response) }
            });
            match version {
                Version::HTTP_11 => {
                    hyper::server::conn::http1::Builder::new()
                        .serve_connection(TokioIo::new(server_io), service)
                        .await
                }
                Version::HTTP_2 => {
                    hyper::server::conn::http2::Builder::new(TokioExecutor::new())
                        .serve_connection(TokioIo::new(server_io), service)
                        .await
                }
                _ => unreachable!(),
            }
            .expect("wire-test server connection must succeed");
        });

        let uri = if case.method == Method::CONNECT {
            "localhost:80"
        } else {
            "http://localhost/"
        };
        let (response, connection) = match version {
            Version::HTTP_11 => {
                let (mut sender, connection) =
                    hyper::client::conn::http1::handshake(TokioIo::new(client_io))
                        .await
                        .unwrap();
                let connection = tokio::spawn(connection);
                let request = hyper::Request::builder()
                    .method(case.method)
                    .uri(uri)
                    .body(Full::new(Bytes::new()))
                    .unwrap();
                let response = sender.send_request(request).await.unwrap();
                drop(sender);
                (response, connection)
            }
            Version::HTTP_2 => {
                let (mut sender, connection) =
                    hyper::client::conn::http2::handshake::<_, _, Full<Bytes>>(
                        TokioExecutor::new(),
                        TokioIo::new(client_io),
                    )
                    .await
                    .unwrap();
                let connection = tokio::spawn(connection);
                let request = hyper::Request::builder()
                    .method(case.method)
                    .uri(uri)
                    .body(Full::new(Bytes::new()))
                    .unwrap();
                let response = sender.send_request(request).await.unwrap();
                drop(sender);
                (response, connection)
            }
            _ => unreachable!(),
        };
        let status = response.status();
        let headers = response.headers().clone();
        let body = response.into_body().collect().await.unwrap().to_bytes();
        connection.abort();
        server.abort();
        (status, headers, body)
    }

    fn conformance_cases() -> Vec<ApplicationCase> {
        let mut cases = vec![
            ApplicationCase::valid(
                "inferred framing",
                Method::GET,
                200,
                vec![("x-result", "valid")],
                b"abc",
                b"abc",
                Some(3),
            ),
            ApplicationCase::valid(
                "correct Content-Length",
                Method::GET,
                200,
                vec![("Content-Length", "3")],
                b"abc",
                b"abc",
                Some(3),
            ),
            ApplicationCase::valid(
                "repeated identical Content-Length",
                Method::GET,
                200,
                vec![("Content-Length", "3"), ("content-length", "3, 3")],
                b"abc",
                b"abc",
                Some(3),
            ),
            ApplicationCase::invalid(
                "conflicting Content-Length",
                Method::GET,
                200,
                vec![("Content-Length", "3"), ("Content-Length", "4")],
                b"abc",
            ),
            ApplicationCase::invalid(
                "too-small Content-Length",
                Method::GET,
                200,
                vec![("Content-Length", "2")],
                b"abc",
            ),
            ApplicationCase::invalid(
                "too-large Content-Length",
                Method::GET,
                200,
                vec![("Content-Length", "4")],
                b"abc",
            ),
            ApplicationCase::invalid(
                "malformed Content-Length",
                Method::GET,
                200,
                vec![("Content-Length", "+3")],
                b"abc",
            ),
            ApplicationCase::invalid(
                "invalid header name",
                Method::GET,
                200,
                vec![("bad name", "value")],
                b"",
            ),
            ApplicationCase::invalid(
                "CR in header value",
                Method::GET,
                200,
                vec![("x-test", "before\rafter")],
                b"",
            ),
            ApplicationCase::invalid(
                "LF in header value",
                Method::GET,
                200,
                vec![("x-test", "before\nafter")],
                b"",
            ),
            ApplicationCase::invalid(
                "NUL in header value",
                Method::GET,
                200,
                vec![("x-test", "before\0after")],
                b"",
            ),
            ApplicationCase::invalid(
                "Connection-nominated field",
                Method::GET,
                200,
                vec![("Connection", "x-private"), ("x-private", "secret")],
                b"",
            ),
            ApplicationCase::valid(
                "HEAD representation",
                Method::HEAD,
                200,
                vec![],
                b"abc",
                b"",
                Some(3),
            ),
            ApplicationCase::valid("empty 204", Method::GET, 204, vec![], b"", b"", None),
            ApplicationCase::invalid("204 with content", Method::GET, 204, vec![], b"abc"),
            ApplicationCase::invalid(
                "204 with Content-Length",
                Method::GET,
                204,
                vec![("Content-Length", "0")],
                b"",
            ),
            ApplicationCase::valid("empty 304", Method::GET, 304, vec![], b"", b"", None),
            ApplicationCase::invalid("304 with content", Method::GET, 304, vec![], b"abc"),
            ApplicationCase::valid("empty 205", Method::GET, 205, vec![], b"", b"", Some(0)),
            ApplicationCase::invalid("205 with content", Method::GET, 205, vec![], b"abc"),
            ApplicationCase::invalid("informational outcome", Method::GET, 103, vec![], b""),
            ApplicationCase::invalid("successful CONNECT", Method::CONNECT, 200, vec![], b""),
            ApplicationCase::valid(
                "failed CONNECT",
                Method::CONNECT,
                403,
                vec![],
                b"denied",
                b"denied",
                Some(6),
            ),
            ApplicationCase::valid(
                "Proxy-Authenticate is response semantics",
                Method::GET,
                407,
                vec![("Proxy-Authenticate", "Basic realm=\"proxy\"")],
                b"authenticate",
                b"authenticate",
                Some(12),
            ),
            ApplicationCase::valid(
                "Proxy-Authorization is not host framing",
                Method::GET,
                200,
                vec![("Proxy-Authorization", "Basic token")],
                b"",
                b"",
                Some(0),
            ),
            ApplicationCase::invalid(
                "unsupported response trailers",
                Method::GET,
                200,
                vec![("Trailer", "Digest")],
                b"",
            ),
        ];
        for field in CONNECTION_SPECIFIC_FIELDS {
            cases.push(ApplicationCase::invalid(
                field,
                Method::GET,
                200,
                vec![(field, if *field == "te" { "trailers" } else { "value" })],
                b"",
            ));
        }
        cases
    }

    #[tokio::test]
    async fn application_conformance_matrix_is_enforced_on_http1_and_http2_wire() {
        for version in [Version::HTTP_11, Version::HTTP_2] {
            for case in conformance_cases() {
                let name = case.name;
                let expected_status = case.expected_status;
                let expected_body = case.expected_body;
                let expected_content_length = case.expected_content_length;
                let (status, headers, body) = wire_exchange(version, case).await;
                assert_eq!(status, expected_status, "{version:?} {name}");
                assert_eq!(body.as_ref(), expected_body, "{version:?} {name}");
                let lengths = headers.get_all(CONTENT_LENGTH).iter().collect::<Vec<_>>();
                match expected_content_length {
                    Some(expected) => {
                        assert_eq!(lengths.len(), 1, "{version:?} {name}");
                        assert_eq!(
                            lengths[0].to_str().unwrap(),
                            expected.to_string(),
                            "{version:?} {name}"
                        );
                    }
                    None => assert!(lengths.is_empty(), "{version:?} {name}"),
                }
            }
        }
    }

    #[test]
    fn native_head_response_preserves_representation_length_and_suppresses_content() {
        let semantics = RequestSemantics {
            method: Method::HEAD,
            version: Version::HTTP_2,
        };
        let mut response = hyper::Response::new(empty_body());
        response
            .headers_mut()
            .insert(CONTENT_LENGTH, HeaderValue::from_static("123"));
        let response = finalize_response(response, &semantics).unwrap();
        assert_eq!(response.headers()[CONTENT_LENGTH], "123");
        assert_eq!(response.body().size_hint().exact(), Some(0));
    }

    #[test]
    fn native_head_response_omits_an_unknown_encoded_length() {
        let semantics = RequestSemantics {
            method: Method::HEAD,
            version: Version::HTTP_11,
        };
        let response = finalize_response(hyper::Response::new(empty_body()), &semantics).unwrap();
        assert!(!response.headers().contains_key(CONTENT_LENGTH));
        assert_eq!(response.body().size_hint().exact(), Some(0));
    }

    #[test]
    fn native_response_cannot_bypass_shared_framing_checks() {
        let semantics = RequestSemantics {
            method: Method::GET,
            version: Version::HTTP_11,
        };
        let mut response = hyper::Response::new(full_body(Bytes::from_static(b"abc")));
        response
            .headers_mut()
            .insert(CONTENT_LENGTH, HeaderValue::from_static("2"));
        assert_eq!(
            finalize_response(response, &semantics)
                .unwrap_err()
                .to_string(),
            "Content-Length 2 does not match the 3-byte response body"
        );
    }

    struct UnknownLengthBody;

    impl Body for UnknownLengthBody {
        type Data = ServerData;
        type Error = io::Error;

        fn poll_frame(
            self: std::pin::Pin<&mut Self>,
            _context: &mut std::task::Context<'_>,
        ) -> std::task::Poll<Option<Result<hyper::body::Frame<Self::Data>, Self::Error>>> {
            std::task::Poll::Ready(None)
        }
    }

    #[test]
    fn native_stream_can_use_protocol_framing_only_without_content_length() {
        let semantics = RequestSemantics {
            method: Method::GET,
            version: Version::HTTP_2,
        };
        let response = hyper::Response::new(UnknownLengthBody.boxed_unsync());
        let response = finalize_response(response, &semantics).unwrap();
        assert!(!response.headers().contains_key(CONTENT_LENGTH));

        let mut incorrectly_framed = hyper::Response::new(UnknownLengthBody.boxed_unsync());
        incorrectly_framed
            .headers_mut()
            .insert(CONTENT_LENGTH, HeaderValue::from_static("1"));
        assert_eq!(
            finalize_response(incorrectly_framed, &semantics)
                .unwrap_err()
                .to_string(),
            "Content-Length cannot frame a response body with an unknown encoded length"
        );
    }
}
