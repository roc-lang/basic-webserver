use crate::abi::roc_host;
use crate::roc_platform_abi::*;

type HttpResponse = HostHttpSendRequest;
type HttpHeader = HostHttpSendRequestArg0Headers;

thread_local! {
    static TOKIO_RUNTIME: tokio::runtime::Runtime = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .expect("failed to build tokio runtime");
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
        10 => hyper::Method::from_bytes(b"QUERY").ok(),
        _ => None,
    }
}

fn http_sentinel_response(status: u16, body: &[u8], roc_host: &RocHost) -> HttpResponse {
    HttpResponse {
        // SAFETY: the returned list owns a copy of `body`.
        body: unsafe { RocListWith::<u8, false>::from_slice(body, roc_host) },
        headers: RocList::empty(),
        status,
    }
}

fn build_hyper_request_from_parts<'a>(
    method: u8,
    method_ext: &str,
    uri: &str,
    headers: impl IntoIterator<Item = (&'a str, &'a str)>,
    body: &[u8],
) -> Result<hyper::Request<http_body_util::Full<bytes::Bytes>>, String> {
    let method =
        as_hyper_method(method, method_ext).ok_or_else(|| "invalid HTTP method".to_string())?;
    let mut builder = hyper::Request::builder().method(method).uri(uri);

    // Default to text/plain unless the caller already set a Content-Type.
    let mut has_content_type = false;
    for (name, value) in headers {
        builder = builder.header(name, value);
        if name.eq_ignore_ascii_case("Content-Type") {
            has_content_type = true;
        }
    }
    if !has_content_type {
        builder = builder.header("Content-Type", "text/plain");
    }

    let body = http_body_util::Full::new(bytes::Bytes::from(body.to_vec()));
    builder.body(body).map_err(|err| err.to_string())
}

fn build_hyper_request(
    args: &HostHttpSendRequestArgs,
) -> Result<hyper::Request<http_body_util::Full<bytes::Bytes>>, String> {
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

async fn async_send_request(
    request: hyper::Request<http_body_util::Full<bytes::Bytes>>,
    roc_host: &RocHost,
) -> HttpResponse {
    use http_body_util::BodyExt;
    use hyper_rustls::HttpsConnectorBuilder;
    use hyper_util::client::legacy::Client;
    use hyper_util::rt::TokioExecutor;

    let https = HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_or_http()
        .enable_http1()
        .build();

    let client: Client<_, http_body_util::Full<bytes::Bytes>> =
        Client::builder(TokioExecutor::new()).build(https);

    match client.request(request).await {
        Ok(response) => {
            let status = response.status().as_u16();
            let pairs: Vec<(String, String)> = response
                .headers()
                .iter()
                .map(|(name, value)| {
                    (
                        name.as_str().to_string(),
                        value.to_str().unwrap_or_default().to_string(),
                    )
                })
                .collect();

            match response.into_body().collect().await {
                Ok(collected) => {
                    let bytes = collected.to_bytes();
                    HttpResponse {
                        // SAFETY: the returned list owns a copy of the body.
                        body: unsafe { RocListWith::<u8, false>::from_slice(&bytes, roc_host) },
                        headers: build_roc_headers(&pairs, roc_host),
                        status,
                    }
                }
                Err(_) => http_sentinel_response(500, b"BadBody", roc_host),
            }
        }
        Err(err) => {
            let detail = format!("OTHER ERROR\n{}", err);
            http_sentinel_response(500, detail.as_bytes(), roc_host)
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_http_send_request(args: HostHttpSendRequestArgs) -> HttpResponse {
    let roc_host = roc_host();
    let timeout_ms = args.timeout_ms;

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
        Err(err) => {
            return http_sentinel_response(
                500,
                format!("OTHER ERROR\n{}", err).as_bytes(),
                roc_host,
            )
        }
    };

    TOKIO_RUNTIME.with(|rt| {
        if timeout_ms > 0 {
            rt.block_on(async {
                match tokio::time::timeout(
                    std::time::Duration::from_millis(timeout_ms),
                    async_send_request(request, roc_host),
                )
                .await
                {
                    Ok(response) => response,
                    Err(_) => http_sentinel_response(408, b"Timeout", roc_host),
                }
            })
        } else {
            rt.block_on(async_send_request(request, roc_host))
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_host_method_tags_to_hyper_methods() {
        assert_eq!(as_hyper_method(3, ""), Some(hyper::Method::GET));
        assert_eq!(as_hyper_method(7, ""), Some(hyper::Method::POST));
        assert_eq!(
            as_hyper_method(10, ""),
            Some(hyper::Method::from_bytes(b"QUERY").unwrap())
        );
        assert_eq!(
            as_hyper_method(2, "PROPFIND"),
            Some(hyper::Method::from_bytes(b"PROPFIND").unwrap())
        );
        assert_eq!(as_hyper_method(255, ""), None);
    }

    #[test]
    fn build_request_defaults_content_type_to_text_plain() {
        let request = build_hyper_request_from_parts(
            7,
            "",
            "http://example.com/",
            std::iter::empty(),
            b"hello",
        )
        .unwrap();

        assert_eq!(request.method(), hyper::Method::POST);
        assert_eq!(request.headers()["content-type"], "text/plain");
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
}
