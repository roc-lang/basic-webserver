use crate::roc;
use crate::roc_http;
use crate::roc_http::ResponseToHost;
use bytes::Bytes;
use futures::{Future, FutureExt};
use hyper::header::{HeaderName, HeaderValue};
use roc_std::RocList;
use std::convert::Infallible;
use std::env;
use std::io::Write;
use std::net::SocketAddr;
use std::panic::AssertUnwindSafe;
use tokio::task::spawn_blocking;

const DEFAULT_PORT: u16 = 8000;
const HOST_ENV_NAME: &str = "ROC_BASIC_WEBSERVER_HOST";
const PORT_ENV_NAME: &str = "ROC_BASIC_WEBSERVER_PORT";

use once_cell::sync::Lazy;
use std::sync::{Arc, RwLock};

static ROC_SERVER: Lazy<Arc<RwLock<roc::RocServer>>> =
    Lazy::new(|| Arc::new(RwLock::new(roc::call_roc_init())));

fn get_roc_server() -> Arc<RwLock<roc::RocServer>> {
    Arc::clone(&ROC_SERVER)
}

pub fn start() -> i32 {
    // hold a reference to the server so it doesn't get dropped
    #[allow(unused_variables)]
    let persistent_server_ref = get_roc_server();

    match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime.block_on(async { run_server().await }),
        Err(err) => {
            eprintln!("Error initializing tokio multithreaded runtime: {}", err); // TODO improve this

            1
        }
    }
}

#[allow(dead_code)]
fn call_roc<'a>(
    method: reqwest::Method,
    url: hyper::Uri,
    headers: impl Iterator<Item = (&'a HeaderName, &'a HeaderValue)>,
    body: Bytes,
) -> hyper::Response<hyper::Body> {
    let headers: RocList<roc_http::Header> = headers
        .map(|(key, value)| {
            roc_http::Header::new(
                key.as_str().into(),
                value
                    .to_str()
                    .expect("valid header value from hyper")
                    .into(),
            )
        })
        .collect();

    let roc_request = roc_http::RequestToAndFromHost::from_reqwest(body, headers, method, url);

    let server = get_roc_server();

    // we don't need to increment as we made the RocList's
    // readonly when we created them
    //
    // when we cannot allocate memory or the lock is poisoned return a 500
    let roc_response: ResponseToHost = server
        .read()
        .map_err(|_poisoned_lock_err| "SERVER ERROR: Poisoned RwLock for RocServer")
        .and_then(|roc_server| roc::call_roc_respond(&roc_request, &roc_server))
        .unwrap_or_else(|err_msg| {
            std::io::stderr().write_all(err_msg.as_bytes()).unwrap();

            roc_http::ResponseToHost {
                body: RocList::empty(),
                headers: RocList::empty(),
                status: 500,
            }
        });

    to_server_response(roc_response)
}

#[allow(dead_code)]
fn to_server_response(roc_response: roc_http::ResponseToHost) -> hyper::Response<hyper::Body> {
    let mut builder = hyper::Response::builder();

    match roc_response.hyper_status() {
        Ok(status_code) => {
            builder = builder.status(status_code);
        }
        Err(_) => {
            todo!("invalid status code from Roc: {:?}", roc_response.status) // TODO respond with a 500 and a message saying tried to return an invalid status code
        }
    };

    for header in roc_response.headers.iter() {
        builder = builder.header(header.key.as_str(), header.value.as_bytes());
    }

    builder
        .body(Vec::from(roc_response.body.as_slice()).into()) // TODO try not to use Vec here
        .unwrap() // TODO don't unwrap this
}

async fn handle_req(req: hyper::Request<hyper::Body>) -> hyper::Response<hyper::Body> {
    let (parts, body) = req.into_parts();

    #[allow(deprecated)]
    match hyper::body::to_bytes(body).await {
        Ok(body) => {
            spawn_blocking(move || call_roc(parts.method, parts.uri, parts.headers.iter(), body))
                .then(|resp| async {
                    resp.unwrap() // TODO don't unwrap here
                })
                .await
        }
        Err(_) => {
            hyper::Response::builder()
                .status(hyper::StatusCode::BAD_REQUEST)
                .body("Error receiving HTTP request body".into())
                .unwrap() // TODO don't unwrap here
        }
    }
}

/// Translate Rust panics in the given Future into 500 errors
async fn handle_panics(
    fut: impl Future<Output = hyper::Response<hyper::Body>>,
) -> Result<hyper::Response<hyper::Body>, Infallible> {
    match AssertUnwindSafe(fut).catch_unwind().await {
        Ok(response) => Ok(response),
        Err(_panic) => {
            let error = hyper::Response::builder()
                .status(hyper::StatusCode::INTERNAL_SERVER_ERROR)
                .body("Panic detected!".into())
                .unwrap(); // TODO don't unwrap here

            Ok(error)
        }
    }
}

async fn run_server() -> i32 {
    let host = env::var(HOST_ENV_NAME).unwrap_or("127.0.0.1".to_string());
    let port = env::var(PORT_ENV_NAME).unwrap_or(DEFAULT_PORT.to_string());
    let addr = format!("{}:{}", host, port)
        .parse::<SocketAddr>()
        .expect("Failed to parse host and port");
    let server = hyper::Server::bind(&addr).serve(hyper::service::make_service_fn(|_conn| async {
        Ok::<_, Infallible>(hyper::service::service_fn(|req| {
            handle_panics(handle_req(req))
        }))
    }));

    println!("Listening on <http://{host}:{port}>");

    match server.await {
        Ok(_) => 0,
        Err(err) => {
            eprintln!("Error initializing Rust `hyper` server: {}", err); // TODO improve this

            1
        }
    }
}
