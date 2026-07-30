//! Protocol-neutral validation and classification of inbound request control data.
//!
//! Hyper has already parsed the wire representation when this module runs, but
//! an application needs a stricter semantic contract than an overloaded `Uri`.
//! This module is the single source of truth used by both native route selection
//! and the Roc fallback request.

use hyper::header::HOST;
use hyper::http::{HeaderMap, Method, Uri, Version};
use std::net::Ipv6Addr;
use std::str::FromStr;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum TargetKind {
    Resource,
    Authority,
    Asterisk,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AuthoritySource {
    Uri,
    Host,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct ParsedAuthority {
    source: AuthoritySource,
    host_end: usize,
    port: Option<u16>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct ParsedHostHeader {
    present: bool,
    authority: Option<ParsedAuthority>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct RequestMetadata {
    target: TargetKind,
    target_authority: Option<ParsedAuthority>,
    effective_authority: Option<ParsedAuthority>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct AuthorityView<'a> {
    pub(crate) host: &'a str,
    pub(crate) port: Option<u16>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct InvalidRequestTarget;

impl RequestMetadata {
    #[cfg(test)]
    pub(crate) fn validate<B>(request: &hyper::Request<B>) -> Result<Self, InvalidRequestTarget> {
        Self::validate_components(
            request.method(),
            request.version(),
            request.uri(),
            request.headers(),
        )
    }

    pub(crate) fn validate_parts(
        parts: &hyper::http::request::Parts,
    ) -> Result<Self, InvalidRequestTarget> {
        Self::validate_components(&parts.method, parts.version, &parts.uri, &parts.headers)
    }

    fn validate_components(
        method: &Method,
        version: Version,
        uri: &Uri,
        headers: &HeaderMap,
    ) -> Result<Self, InvalidRequestTarget> {
        let target = classify_target(method, version, uri)?;
        let uri_authority = uri
            .authority()
            .map(|authority| parse_authority(authority.as_str(), AuthoritySource::Uri))
            .transpose()?;
        let host = parse_host_header(headers)?;

        let effective_authority = match version {
            Version::HTTP_11 => {
                // RFC 9112 section 3.2 requires exactly one Host field,
                // including for absolute-form and authority-form targets. An
                // empty field is distinct from a missing field and represents
                // an undefined authority (RFC 9110 section 7.2).
                if !host.present {
                    return Err(InvalidRequestTarget);
                }
                uri_authority.or(host.authority)
            }
            Version::HTTP_2 => {
                // Hyper represents :authority in Uri::authority. RFC 9113
                // section 8.3.1 requires an ordinary Host field, when also
                // present, to agree with it.
                if host.present {
                    match (uri_authority, host.authority) {
                        (Some(uri_authority), Some(host_authority)) => {
                            if !authorities_equal(uri_authority, host_authority, uri, headers) {
                                return Err(InvalidRequestTarget);
                            }
                        }
                        (Some(_), None) => return Err(InvalidRequestTarget),
                        (None, Some(_)) | (None, None) => {}
                    }
                }
                uri_authority.or(host.authority)
            }
            Version::HTTP_10 => uri_authority.or(host.authority),
            _ => return Err(InvalidRequestTarget),
        };

        let target_authority = match target {
            TargetKind::Authority => uri_authority,
            TargetKind::Resource | TargetKind::Asterisk => None,
        };
        if target == TargetKind::Authority && target_authority.is_none() {
            return Err(InvalidRequestTarget);
        }

        Ok(Self {
            target,
            target_authority,
            effective_authority,
        })
    }

    pub(crate) fn target_kind(self) -> TargetKind {
        self.target
    }

    pub(crate) fn resource_path(self, uri: &Uri) -> Option<&str> {
        if self.target != TargetKind::Resource {
            return None;
        }
        Some(
            uri.path_and_query()
                .map(hyper::http::uri::PathAndQuery::path)
                .unwrap_or("/"),
        )
    }

    pub(crate) fn resource_query(self, uri: &Uri) -> Option<&str> {
        if self.target != TargetKind::Resource {
            return None;
        }
        uri.query()
    }

    pub(crate) fn normalized_target_len(self, uri: &Uri) -> usize {
        match self.target {
            TargetKind::Resource => uri
                .path_and_query()
                .map(|value| value.as_str().len())
                .unwrap_or(1),
            TargetKind::Authority => uri
                .authority()
                .expect("validated authority target must retain its authority")
                .as_str()
                .len(),
            TargetKind::Asterisk => 1,
        }
    }

    pub(crate) fn target_authority<'a>(
        self,
        uri: &'a Uri,
        headers: &'a HeaderMap,
    ) -> Option<AuthorityView<'a>> {
        self.target_authority
            .map(|authority| authority.view(uri, headers))
    }

    pub(crate) fn effective_authority<'a>(
        self,
        uri: &'a Uri,
        headers: &'a HeaderMap,
    ) -> Option<AuthorityView<'a>> {
        self.effective_authority
            .map(|authority| authority.view(uri, headers))
    }
}

impl ParsedAuthority {
    fn raw<'a>(self, uri: &'a Uri, headers: &'a HeaderMap) -> &'a str {
        match self.source {
            AuthoritySource::Uri => uri
                .authority()
                .expect("validated URI authority must remain present")
                .as_str(),
            AuthoritySource::Host => headers
                .get(HOST)
                .expect("validated Host header must remain present")
                .to_str()
                .expect("validated Host header must remain ASCII"),
        }
    }

    fn view<'a>(self, uri: &'a Uri, headers: &'a HeaderMap) -> AuthorityView<'a> {
        let raw = self.raw(uri, headers);
        AuthorityView {
            host: &raw[..self.host_end],
            port: self.port,
        }
    }
}

fn classify_target(
    method: &Method,
    version: Version,
    uri: &Uri,
) -> Result<TargetKind, InvalidRequestTarget> {
    if version == Version::HTTP_2 {
        if method == Method::CONNECT {
            return if uri.scheme().is_none()
                && uri.authority().is_some()
                && uri.path_and_query().is_none()
            {
                Ok(TargetKind::Authority)
            } else {
                Err(InvalidRequestTarget)
            };
        }

        let path = uri.path_and_query().ok_or(InvalidRequestTarget)?.as_str();
        if path == "*" {
            return if method == Method::OPTIONS {
                Ok(TargetKind::Asterisk)
            } else {
                Err(InvalidRequestTarget)
            };
        }
        return if path.starts_with('/') {
            Ok(TargetKind::Resource)
        } else {
            Err(InvalidRequestTarget)
        };
    }

    if uri.scheme().is_some() {
        return if method != Method::CONNECT && uri.authority().is_some() {
            Ok(TargetKind::Resource)
        } else {
            Err(InvalidRequestTarget)
        };
    }

    if uri.authority().is_some() {
        return if method == Method::CONNECT && uri.path_and_query().is_none() {
            Ok(TargetKind::Authority)
        } else {
            Err(InvalidRequestTarget)
        };
    }

    let path = uri.path_and_query().ok_or(InvalidRequestTarget)?.as_str();
    if path == "*" {
        return if method == Method::OPTIONS {
            Ok(TargetKind::Asterisk)
        } else {
            Err(InvalidRequestTarget)
        };
    }
    if method == Method::CONNECT || !path.starts_with('/') {
        Err(InvalidRequestTarget)
    } else {
        Ok(TargetKind::Resource)
    }
}

fn parse_host_header(headers: &HeaderMap) -> Result<ParsedHostHeader, InvalidRequestTarget> {
    let mut values = headers.get_all(HOST).iter();
    let Some(value) = values.next() else {
        return Ok(ParsedHostHeader {
            present: false,
            authority: None,
        });
    };
    if values.next().is_some() {
        return Err(InvalidRequestTarget);
    }
    let raw = value.to_str().map_err(|_| InvalidRequestTarget)?;
    let authority = if raw.is_empty() {
        None
    } else {
        Some(parse_authority(raw, AuthoritySource::Host)?)
    };
    Ok(ParsedHostHeader {
        present: true,
        authority,
    })
}

fn parse_authority(
    raw: &str,
    source: AuthoritySource,
) -> Result<ParsedAuthority, InvalidRequestTarget> {
    if raw.is_empty() || !raw.is_ascii() || raw.as_bytes().contains(&b'@') {
        return Err(InvalidRequestTarget);
    }

    let host_end = if raw.starts_with('[') {
        let close = raw.find(']').ok_or(InvalidRequestTarget)?;
        let end = close + 1;
        validate_ip_literal(&raw[1..close])?;
        end
    } else {
        let end = raw.rfind(':').unwrap_or(raw.len());
        validate_reg_name(&raw[..end])?;
        end
    };
    if host_end == 0 {
        return Err(InvalidRequestTarget);
    }

    let port = match &raw[host_end..] {
        "" => None,
        suffix if suffix.starts_with(':') => {
            let digits = &suffix[1..];
            if digits.is_empty() {
                None
            } else if !digits.bytes().all(|byte| byte.is_ascii_digit()) {
                return Err(InvalidRequestTarget);
            } else {
                Some(digits.parse::<u16>().map_err(|_| InvalidRequestTarget)?)
            }
        }
        _ => return Err(InvalidRequestTarget),
    };

    Ok(ParsedAuthority {
        source,
        host_end,
        port,
    })
}

fn validate_reg_name(host: &str) -> Result<(), InvalidRequestTarget> {
    if host.is_empty() {
        return Err(InvalidRequestTarget);
    }
    validate_uri_component(host, true)
}

fn validate_ip_literal(literal: &str) -> Result<(), InvalidRequestTarget> {
    if let Some(rest) = literal
        .strip_prefix('v')
        .or_else(|| literal.strip_prefix('V'))
    {
        let (version, address) = rest.split_once('.').ok_or(InvalidRequestTarget)?;
        if version.is_empty()
            || !version.bytes().all(|byte| byte.is_ascii_hexdigit())
            || address.is_empty()
            || !address.bytes().all(is_ipv_future_char)
        {
            return Err(InvalidRequestTarget);
        }
        return Ok(());
    }

    if let Some((address, zone)) = literal.split_once("%25") {
        Ipv6Addr::from_str(address).map_err(|_| InvalidRequestTarget)?;
        if zone.is_empty() {
            return Err(InvalidRequestTarget);
        }
        return validate_uri_component(zone, false);
    }

    Ipv6Addr::from_str(literal)
        .map(|_| ())
        .map_err(|_| InvalidRequestTarget)
}

fn validate_uri_component(value: &str, allow_sub_delims: bool) -> Result<(), InvalidRequestTarget> {
    let bytes = value.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        let byte = bytes[index];
        if is_unreserved(byte) || (allow_sub_delims && is_sub_delim(byte)) {
            index += 1;
        } else if byte == b'%'
            && index + 2 < bytes.len()
            && bytes[index + 1].is_ascii_hexdigit()
            && bytes[index + 2].is_ascii_hexdigit()
        {
            index += 3;
        } else {
            return Err(InvalidRequestTarget);
        }
    }
    Ok(())
}

fn is_unreserved(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~')
}

fn is_sub_delim(byte: u8) -> bool {
    matches!(
        byte,
        b'!' | b'$' | b'&' | b'\'' | b'(' | b')' | b'*' | b'+' | b',' | b';' | b'='
    )
}

fn is_ipv_future_char(byte: u8) -> bool {
    is_unreserved(byte) || is_sub_delim(byte) || byte == b':'
}

fn authorities_equal(
    left: ParsedAuthority,
    right: ParsedAuthority,
    uri: &Uri,
    headers: &HeaderMap,
) -> bool {
    let left = left.view(uri, headers);
    let right = right.view(uri, headers);
    left.host.eq_ignore_ascii_case(right.host) && left.port == right.port
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(method: Method, uri: &str, version: Version, hosts: &[&str]) -> hyper::Request<()> {
        let mut builder = hyper::Request::builder()
            .method(method)
            .uri(uri)
            .version(version);
        for host in hosts {
            builder = builder.header(HOST, *host);
        }
        builder.body(()).unwrap()
    }

    #[test]
    fn resource_query_preserves_absent_empty_and_encoded_values() {
        for (uri, expected_query) in [
            ("/a%2Fb", None),
            ("/a%2Fb?", Some("")),
            ("/a%2Fb?q=x%26y", Some("q=x%26y")),
        ] {
            let request = request(Method::GET, uri, Version::HTTP_11, &["example.test"]);
            let metadata = RequestMetadata::validate(&request).unwrap();
            assert_eq!(metadata.target_kind(), TargetKind::Resource);
            assert_eq!(metadata.resource_path(request.uri()), Some("/a%2Fb"));
            assert_eq!(metadata.resource_query(request.uri()), expected_query);
        }
    }

    #[test]
    fn absolute_form_normalizes_an_empty_path_and_uses_its_authority() {
        let request = request(
            Method::GET,
            "http://absolute.test?query",
            Version::HTTP_11,
            &["ignored.test"],
        );
        let metadata = RequestMetadata::validate(&request).unwrap();
        assert_eq!(metadata.resource_path(request.uri()), Some("/"));
        assert_eq!(metadata.resource_query(request.uri()), Some("query"));
        assert_eq!(
            metadata.effective_authority(request.uri(), request.headers()),
            Some(AuthorityView {
                host: "absolute.test",
                port: None,
            })
        );
    }

    #[test]
    fn http11_requires_one_valid_host_even_for_absolute_form() {
        assert!(RequestMetadata::validate(&request(
            Method::GET,
            "http://absolute.test/",
            Version::HTTP_11,
            &[],
        ))
        .is_err());
        assert!(RequestMetadata::validate(&request(
            Method::GET,
            "/",
            Version::HTTP_11,
            &["one.test", "two.test"],
        ))
        .is_err());
        for invalid in ["user@example.test", "[not-ip]:80", "x:65536"] {
            assert!(
                RequestMetadata::validate(
                    &request(Method::GET, "/", Version::HTTP_11, &[invalid],)
                )
                .is_err(),
                "{invalid:?} should be rejected"
            );
        }
    }

    #[test]
    fn empty_host_is_present_but_has_no_effective_authority() {
        let empty_host = request(Method::OPTIONS, "*", Version::HTTP_11, &[""]);
        let metadata = RequestMetadata::validate(&empty_host).unwrap();
        assert_eq!(metadata.target_kind(), TargetKind::Asterisk);
        assert_eq!(
            metadata.effective_authority(empty_host.uri(), empty_host.headers()),
            None
        );

        let empty_port = request(Method::GET, "/", Version::HTTP_11, &["example.test:"]);
        assert_eq!(
            RequestMetadata::validate(&empty_port)
                .unwrap()
                .effective_authority(empty_port.uri(), empty_port.headers()),
            Some(AuthorityView {
                host: "example.test",
                port: None,
            })
        );
    }

    #[test]
    fn connect_and_asterisk_have_distinct_method_checked_forms() {
        let connect = request(
            Method::CONNECT,
            "[2001:db8::1]:443",
            Version::HTTP_11,
            &["proxy.test"],
        );
        let metadata = RequestMetadata::validate(&connect).unwrap();
        assert_eq!(metadata.target_kind(), TargetKind::Authority);
        assert_eq!(
            metadata.target_authority(connect.uri(), connect.headers()),
            Some(AuthorityView {
                host: "[2001:db8::1]",
                port: Some(443),
            })
        );

        let options = request(Method::OPTIONS, "*", Version::HTTP_11, &["example.test"]);
        assert_eq!(
            RequestMetadata::validate(&options).unwrap().target_kind(),
            TargetKind::Asterisk
        );
        assert!(RequestMetadata::validate(&request(
            Method::GET,
            "*",
            Version::HTTP_11,
            &["example.test"],
        ))
        .is_err());
        assert!(RequestMetadata::validate(&request(
            Method::GET,
            "example.test:443",
            Version::HTTP_11,
            &["example.test"],
        ))
        .is_err());
    }

    #[test]
    fn http2_authority_uses_host_fallback_and_rejects_disagreement() {
        let authority = request(
            Method::GET,
            "http://example.test:8443/path",
            Version::HTTP_2,
            &[],
        );
        assert_eq!(
            RequestMetadata::validate(&authority)
                .unwrap()
                .effective_authority(authority.uri(), authority.headers()),
            Some(AuthorityView {
                host: "example.test",
                port: Some(8443),
            })
        );

        let host_only = request(Method::GET, "/path", Version::HTTP_2, &["host.test"]);
        assert_eq!(
            RequestMetadata::validate(&host_only)
                .unwrap()
                .effective_authority(host_only.uri(), host_only.headers()),
            Some(AuthorityView {
                host: "host.test",
                port: None,
            })
        );

        let disagreement = request(
            Method::GET,
            "http://authority.test/path",
            Version::HTTP_2,
            &["host.test"],
        );
        assert!(RequestMetadata::validate(&disagreement).is_err());

        let empty_host_disagreement = request(
            Method::GET,
            "http://authority.test/path",
            Version::HTTP_2,
            &[""],
        );
        assert!(RequestMetadata::validate(&empty_host_disagreement).is_err());
    }
}
