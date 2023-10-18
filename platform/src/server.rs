use bytes::Bytes;
use futures::{Future, FutureExt};
use hyper::header::{HeaderName, HeaderValue};
use hyper::{Body, Request, Response, Server, StatusCode};
use roc_app::{self, Method, RocHeader, RocMethod, RocRequest, RocResponse};
use roc_std::{RocList, RocStr};
use std::convert::Infallible;
use std::net::SocketAddr;
use std::panic::AssertUnwindSafe;
use tokio::task::spawn_blocking;

const DEFAULT_PORT: u16 = 8000;

pub fn start() -> i32 {
    match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime.block_on(async { run_server(DEFAULT_PORT).await }),
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
) -> Response<Body> {
    let roc_headers: RocList<RocHeader> = headers
        .map(|(name, value)| RocHeader {
            name: RocStr::from(name.as_str()),
            value: RocList::from(value.as_bytes()),
        })
        .collect::<Vec<_>>() // TODO remove intermediate Vec if possible
        .as_slice()
        .into();

    let answer = roc_app::main(RocRequest {
        body: body.to_vec().as_slice().into(), // TODO don't use to_vec if possible
        headers: roc_headers,
        url: RocStr::from(url),
        method: method_from_str(method),
    });

    to_server_response(answer)
}

fn method_from_str(method: &str) -> RocMethod {
    match method {
        "DELETE" => RocMethod::DELETE,
        "GET" => RocMethod::GET,
        "HEAD" => RocMethod::HEAD,
        "OPTIONS" => RocMethod::OPTIONS,
        "POST" => RocMethod::POST,
        "PUT" => RocMethod::PUT,
        _ => todo!("handle unrecognized method: {method:?}"),
    }
}

fn to_server_response(resp: RocResponse) -> Response<Body> {
    let mut builder = Response::builder();

    match StatusCode::from_u16(resp.status) {
        Ok(status_code) => {
            builder = builder.status(status_code);
        }
        Err(_) => {
            todo!("invalid status code: {:?}", resp.status) // TODO respond with a 500 and a message saying tried to return an invalid status code
        }
    };

    for header in resp.headers.iter() {
        builder = builder.header(header.name.as_str(), header.value.as_slice());
    }

    builder
        .body(Vec::from(resp.body.as_slice()).into()) // TODO try not to use Vec here
        .unwrap() // TODO don't unwrap this
}

async fn handle_req(req: Request<Body>) -> Response<Body> {
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
            Response::builder()
                .status(StatusCode::BAD_REQUEST)
                .body("Error receiving HTTP request body".into())
                .unwrap() // TODO don't unwrap here
        }
    }
}

/// Translate Rust panics in the given Future into 500 errors
async fn handle_panics(
    fut: impl Future<Output = Response<Body>>,
) -> Result<Response<Body>, Infallible> {
    match AssertUnwindSafe(fut).catch_unwind().await {
        Ok(response) => Ok(response),
        Err(_panic) => {
            let error = Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body("Panic detected!".into())
                .unwrap(); // TODO don't unwrap here

            Ok(error)
        }
    }
}

const LOCALHOST: [u8; 4] = [127, 0, 0, 1];

async fn run_server(port: u16) -> i32 {
    let addr = SocketAddr::from((LOCALHOST, port));
    let server = Server::bind(&addr).serve(hyper::service::make_service_fn(|_conn| async {
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
