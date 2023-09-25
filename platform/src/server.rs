use bytes::Bytes;
use futures::{Future, FutureExt};
use hyper::header::{HeaderName, HeaderValue};
use hyper::{Body, Request, Response, Server, StatusCode};
use roc_app;
use roc_std::RocList;
use std::convert::{Infallible, TryInto};
use std::net::SocketAddr;
use std::panic::AssertUnwindSafe;
use std::str::FromStr;
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
    let mut req_bytes: Vec<u8> = format!("{}\n{}\n", method, url).into();

    for (name, value) in headers {
        req_bytes.extend(name.as_str().as_bytes());
        req_bytes.push(b':');
        req_bytes.extend(value.as_bytes());
        req_bytes.push(b'\n');
    }

    if !body.is_empty() {
        req_bytes.push(b'\n');
        req_bytes.extend(body);
    }

    dbg!(core::str::from_utf8(req_bytes.as_slice()).unwrap());
    let list = RocList::from(req_bytes.as_slice());
    dbg!(list.len()); // This is a load-bearing dbg! somehow
    let answer = roc_app::main(list);

    dbg!("answered");
    response_from_bytes(answer)
}

fn response_from_bytes(bytes: RocList<u8>) -> Response<Body> {
    let mut bytes = bytes.as_slice();
    let mut builder = Response::builder();

    dbg!(core::str::from_utf8(bytes).unwrap());

    {
        let index = bytes.iter().position(|&byte| byte == b'\n').unwrap();
        let (before, after) = bytes.split_at(index + 1);

        let before = &before[..index]; // Drop the newline itself
        let status_code_str = core::str::from_utf8(before).unwrap();
        let status_code: u16 = status_code_str.parse().unwrap();

        builder = builder.status(StatusCode::from_u16(status_code).unwrap());
        bytes = &after[1..]; // Drop the newline itself
    };

    loop {
        match bytes.iter().position(|&byte| byte == b'\n') {
            Some(newline_index) => {
                dbg!(&newline_index); // TODO note we aren't getting here, also we don't use bumpalo here!
                let (line, after) = bytes.split_at(newline_index + 1);

                // Drop the newline itself
                let line = &line[..newline_index];
                bytes = &after[1..];

                if line.is_empty() {
                    // We hit the end of the string; no more headers!
                    break;
                }

                if line.first() == Some(&b'\n') {
                    // Skip over that next newline
                    bytes = &bytes[1..];

                    // We hit a blank line; no more headers!
                    break;
                }

                let colon_index = line.iter().position(|&byte| byte == b':').unwrap();
                let (name, value) = line.split_at(colon_index + 1);

                // Drop the colon itself
                let name = &name[..colon_index];
                let value = &value[1..];

                builder = builder.header(name, value);
            }
            None => {
                // We didn't find any more newlines; we're done!
                break;
            }
        }
    }

    // Whatever's left is the body.
    builder.body(Vec::from(bytes).into()).unwrap() // TODO don't unwrap this
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
