//! The webserver event loop.
//!
//! `start()` calls the app's `roc_init_for_host` once, stashes the boxed model
//! (promoted to a constant refcount so it is shared across worker threads and
//! never freed), then runs a tokio/hyper accept loop that calls
//! `roc_respond_for_host(request, model)` for each request.

use crate::abi::{
    decref_response, roc_host, Header, InitForHostResult, InitForHostResultTag,
    RequestToAndFromHost, ResponseToAndFromHost,
};
use crate::roc_platform_abi::*;
use bytes::Bytes;
use futures::{Future, FutureExt};
use http_body_util::{BodyExt, Full};
use hyper::header::{HeaderName, HeaderValue};
use std::convert::Infallible;
use std::env;
use std::mem::ManuallyDrop;
use std::net::SocketAddr;
use std::panic::AssertUnwindSafe;
use std::sync::OnceLock;
use tokio::task::spawn_blocking;

const DEFAULT_PORT: u16 = 8000;
const HOST_ENV_NAME: &str = "ROC_BASIC_WEBSERVER_HOST";
const PORT_ENV_NAME: &str = "ROC_BASIC_WEBSERVER_PORT";

/// The boxed Roc model returned by `init!`. It has a constant refcount, so the
/// raw pointer is shared (read-only) across all worker threads.
struct RocModel(RocBox);
unsafe impl Send for RocModel {}
unsafe impl Sync for RocModel {}

static ROC_MODEL: OnceLock<RocModel> = OnceLock::new();

/// Mark a boxed value as static data (refcount 0) so the generated
/// `incref_box`/`decref_box` helpers leave it alone: it is never freed and is
/// safe to share between threads. This mirrors the model lifetime of the old
/// host (the model lives for the whole process and is immutable).
unsafe fn promote_box_to_constant(boxed: RocBox) {
    if boxed.is_null() {
        return;
    }
    let rc = (boxed as *mut u8).sub(core::mem::size_of::<isize>()) as *mut isize;
    *rc = 0;
}

pub fn start() -> i32 {
    // Run `init!` once at startup.
    let init_result: InitForHostResult = unsafe { roc_init_for_host() };
    let model = match init_result.tag {
        InitForHostResultTag::Ok => unsafe { ManuallyDrop::into_inner(init_result.payload.ok) },
        InitForHostResultTag::Err => {
            let code = unsafe { ManuallyDrop::into_inner(init_result.payload.err) };
            std::process::exit(code as i32);
        }
    };

    unsafe { promote_box_to_constant(model) };
    ROC_MODEL
        .set(RocModel(model))
        .unwrap_or_else(|_| panic!("Model is only initialized once at startup"));

    match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime.block_on(async { run_server().await }),
        Err(err) => {
            eprintln!("Error initializing tokio multithreaded runtime: {}", err);
            1
        }
    }
}

/// Map a hyper method to the host-ABI method tag used by InternalHttp.roc.
/// Canonical mapping (must match InternalHttp.from_host_method):
/// CONNECT=0, DELETE=1, Unknown=2, GET=3, HEAD=4, OPTIONS=5, PATCH=6, POST=7,
/// PUT=8, TRACE=9, QUERY=10.
fn method_to_tag(method: &hyper::Method) -> (u8, &'static str) {
    match *method {
        hyper::Method::CONNECT => (0, ""),
        hyper::Method::DELETE => (1, ""),
        hyper::Method::GET => (3, ""),
        hyper::Method::HEAD => (4, ""),
        hyper::Method::OPTIONS => (5, ""),
        hyper::Method::PATCH => (6, ""),
        hyper::Method::POST => (7, ""),
        hyper::Method::PUT => (8, ""),
        hyper::Method::TRACE => (9, ""),
        _ if method.as_str() == "QUERY" => (10, ""),
        _ => (2, "EXTENSION"),
    }
}

fn call_roc<'a>(
    method: hyper::Method,
    url: hyper::Uri,
    headers: impl Iterator<Item = (&'a HeaderName, &'a HeaderValue)>,
    body: Bytes,
) -> hyper::Response<Full<Bytes>> {
    let roc_host = roc_host();

    let (method_tag, method_ext_str) = method_to_tag(&method);
    let method_ext = if method_ext_str.is_empty() {
        RocStr::empty()
    } else {
        RocStr::from_str(method.as_str(), roc_host)
    };

    let header_vec: Vec<Header> = headers
        .map(|(name, value)| Header {
            name: RocStr::from_str(name.as_str(), roc_host),
            value: RocStr::from_str(value.to_str().unwrap_or_default(), roc_host),
        })
        .collect();
    let roc_headers = RocList::<Header>::from_slice(&header_vec, roc_host);

    let roc_uri = RocStr::from_str(&url.to_string(), roc_host);
    let roc_body = RocListWith::<u8, false>::from_slice(&body, roc_host);

    let roc_request = RequestToAndFromHost {
        body: roc_body,
        headers: roc_headers,
        method: method_tag,
        method_ext,
        timeout_ms: 0,
        uri: roc_uri,
    };

    // `roc_respond_for_host` takes ownership of `roc_request` (Roc decrefs it),
    // and reads `model` (constant refcount, so its Box.unbox is a no-op decref).
    let model = ROC_MODEL.get().expect("Model initialized at startup").0;
    let roc_response = unsafe { roc_respond_for_host(roc_request, model) };

    response_to_hyper(roc_response, roc_host)
}

fn response_to_hyper(
    response: ResponseToAndFromHost,
    roc_host: &RocHost,
) -> hyper::Response<Full<Bytes>> {
    let mut builder = hyper::Response::builder().status(response.status);

    for header in response.headers.as_slice() {
        builder = builder.header(header.name.as_str(), header.value.as_str());
    }

    let body = Bytes::copy_from_slice(response.body.as_slice());

    let hyper_response = builder
        .body(Full::new(body))
        .unwrap_or_else(|_| internal_server_error("Failed to build response"));

    // Now that the response data has been copied into owned Rust types, release
    // the Roc-owned heap allocations.
    decref_response(response, roc_host);

    hyper_response
}

fn internal_server_error(message: &str) -> hyper::Response<Full<Bytes>> {
    hyper::Response::builder()
        .status(hyper::StatusCode::INTERNAL_SERVER_ERROR)
        .body(Full::new(Bytes::copy_from_slice(message.as_bytes())))
        .expect("static 500 response is always valid")
}

async fn handle_req(req: hyper::Request<hyper::body::Incoming>) -> hyper::Response<Full<Bytes>> {
    let (parts, body) = req.into_parts();

    match body.collect().await.map(|collected| collected.to_bytes()) {
        Ok(body_bytes) => {
            spawn_blocking(move || {
                call_roc(parts.method, parts.uri, parts.headers.iter(), body_bytes)
            })
            .then(|resp| async {
                match resp {
                    Ok(resp) => resp,
                    Err(err) => {
                        eprintln!("Recovered from calling roc:\n\t{:?}", err);
                        internal_server_error("500 Internal Server Error")
                    }
                }
            })
            .await
        }
        Err(err) => {
            eprintln!("Failed to receive HTTP request body:\n\t{:?}", err);
            hyper::Response::builder()
                .status(hyper::StatusCode::BAD_REQUEST)
                .body(Full::new(Bytes::from_static(
                    b"Failed to receive HTTP request body",
                )))
                .expect("static 400 response is always valid")
        }
    }
}

/// Translate Rust panics in the given future into 500 errors.
async fn handle_panics(
    fut: impl Future<Output = hyper::Response<Full<Bytes>>>,
) -> Result<hyper::Response<Full<Bytes>>, Infallible> {
    match AssertUnwindSafe(fut).catch_unwind().await {
        Ok(response) => Ok(response),
        Err(_panic) => Ok(internal_server_error("Panic detected!")),
    }
}

async fn run_server() -> i32 {
    let host = env::var(HOST_ENV_NAME).unwrap_or("127.0.0.1".to_string());
    let port = env::var(PORT_ENV_NAME).unwrap_or(DEFAULT_PORT.to_string());
    let addr = match format!("{}:{}", host, port).parse::<SocketAddr>() {
        Ok(addr) => addr,
        Err(err) => {
            eprintln!(
                "Failed to parse host '{}' and port '{}': {}",
                host, port, err
            );
            return 1;
        }
    };

    let listener = match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("Failed to bind TCP listener to {}: {}", addr, err);
            return 1;
        }
    };

    println!("Listening on <http://{addr}>");

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let io = hyper_util::rt::TokioIo::new(stream);

                tokio::task::spawn(async move {
                    if let Err(err) = hyper::server::conn::http1::Builder::new()
                        .serve_connection(
                            io,
                            hyper::service::service_fn(|req| handle_panics(handle_req(req))),
                        )
                        .await
                    {
                        eprintln!("Error serving connection:\n\t{:?}", err);
                    }
                });
            }
            Err(err) => {
                eprintln!("Failed to accept incoming connection: {}", err);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn method_to_tag_matches_internal_http_contract() {
        assert_eq!(method_to_tag(&hyper::Method::CONNECT), (0, ""));
        assert_eq!(method_to_tag(&hyper::Method::DELETE), (1, ""));
        assert_eq!(method_to_tag(&hyper::Method::GET), (3, ""));
        assert_eq!(method_to_tag(&hyper::Method::HEAD), (4, ""));
        assert_eq!(method_to_tag(&hyper::Method::OPTIONS), (5, ""));
        assert_eq!(method_to_tag(&hyper::Method::PATCH), (6, ""));
        assert_eq!(method_to_tag(&hyper::Method::POST), (7, ""));
        assert_eq!(method_to_tag(&hyper::Method::PUT), (8, ""));
        assert_eq!(method_to_tag(&hyper::Method::TRACE), (9, ""));
        assert_eq!(
            method_to_tag(&hyper::Method::from_bytes(b"QUERY").unwrap()),
            (10, "")
        );
    }

    #[test]
    fn method_to_tag_marks_extensions_as_unknown() {
        assert_eq!(
            method_to_tag(&hyper::Method::from_bytes(b"PROPFIND").unwrap()),
            (2, "EXTENSION")
        );
    }
}
