use bytes::Bytes;
use futures::{Future, FutureExt};
use hyper::header::{HeaderName, HeaderValue};
use roc_std::{RocList, RocStr};
use std::convert::Infallible;
use std::env;
use std::net::SocketAddr;
use std::panic::AssertUnwindSafe;
use tokio::task::spawn_blocking;

const DEFAULT_PORT: u16 = 8000;
const HOST_ENV_NAME: &str = "ROC_BASIC_WEBSERVER_HOST";
const PORT_ENV_NAME: &str = "ROC_BASIC_WEBSERVER_PORT";

pub fn start() -> i32 {
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

fn call_roc<'a>(
    method: &str,
    url: &str,
    headers: impl Iterator<Item = (&'a HeaderName, &'a HeaderValue)>,
    body: Bytes,
) -> hyper::Response<hyper::Body> {
    let roc_headers: RocList<roc_app::InternalHeader> = headers
        .map(|(name, value)| roc_app::InternalHeader {
            name: RocStr::from(name.as_str()),
            value: RocList::from(value.as_bytes()),
        })
        .collect::<Vec<_>>() // TODO remove intermediate Vec if possible
        .as_slice()
        .into();

    let answer = roc_app::mainForHost(roc_app::InternalRequest {
        body: roc_app::InternalBody::Body(roc_app::InternalBodyBody {
            body: body.to_vec().as_slice().into(),
            mimeType: RocStr::from("text/plain"),
        }),
        headers: roc_headers,
        url: RocStr::from(url),
        method: method_from_str(method),
        timeout: roc_app::InternalTimeoutConfig::TimeoutMilliseconds(1_000), // TODO implement timeouts
    })
    .force_thunk();
    to_server_response(answer)
}

fn method_from_str(method: &str) -> roc_app::InternalMethod {
    match method {
        "DELETE" => roc_app::InternalMethod::Delete,
        "GET" => roc_app::InternalMethod::Get,
        "HEAD" => roc_app::InternalMethod::Head,
        "OPTIONS" => roc_app::InternalMethod::Options,
        "POST" => roc_app::InternalMethod::Post,
        "PUT" => roc_app::InternalMethod::Put,
        _ => todo!("handle unrecognized method from Roc: {method:?}"),
    }
}

fn to_server_response(resp: roc_app::InternalResponse) -> hyper::Response<hyper::Body> {
    let mut builder = hyper::Response::builder();

    match hyper::StatusCode::from_u16(resp.status) {
        Ok(status_code) => {
            builder = builder.status(status_code);
        }
        Err(_) => {
            todo!("invalid status code from Roc: {:?}", resp.status) // TODO respond with a 500 and a message saying tried to return an invalid status code
        }
    };

    for header in resp.headers.iter() {
        builder = builder.header(header.name.as_str(), header.value.as_slice());
    }

    builder
        .body(Vec::from(resp.body.as_slice()).into()) // TODO try not to use Vec here
        .unwrap() // TODO don't unwrap this
}

async fn handle_req(req: hyper::Request<hyper::Body>) -> hyper::Response<hyper::Body> {
    let (parts, body) = req.into_parts();

    match hyper::body::to_bytes(body).await {
        Ok(body) => {
            spawn_blocking(move || {
                call_roc(
                    parts.method.as_str(),
                    &parts.uri.to_string(),
                    parts.headers.iter(),
                    body,
                )
            })
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

    println!("Listening on localhost port {port}");

    match server.await {
        Ok(_) => 0,
        Err(err) => {
            eprintln!("Error initializing Rust `hyper` server: {}", err); // TODO improve this

            1
        }
    }
}
