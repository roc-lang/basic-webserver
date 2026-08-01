//! Real-listener harness for the Datastar browser/transport research spike.
//!
//! This is intentionally disposable research code. It serves the exact pinned
//! Datastar bundle and uses the bounded body plus explicit Brotli lifecycle
//! adapter from this crate. The second event is gated by a separate request so
//! a browser test can prove it applied event one before event two existed.

use bytes::Bytes;
use datastar_transport_spike::{bounded_body, BoundedProducer, ExplicitBrotli, ReserveError};
use http_body_util::combinators::BoxBody;
use http_body_util::{BodyExt, Full};
use hyper::body::Incoming;
use hyper::header::{ACCEPT_ENCODING, CACHE_CONTROL, CONTENT_ENCODING, CONTENT_TYPE, VARY};
use hyper::service::service_fn;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::{TokioExecutor, TokioIo};
use hyper_util::server::conn::auto::Builder as ConnectionBuilder;
use serde::Serialize;
use std::collections::HashMap;
use std::convert::Infallible;
use std::env;
use std::io;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokio::net::TcpListener;
use tokio::time::{sleep, Duration};

const DATASTAR_BUNDLE: &[u8] =
    include_bytes!("../../../datastar-browser-transport/vendor/datastar-v1.0.2.js");
const FRAME_RESERVATION: usize = 128 * 1024;

type HttpBody = BoxBody<Bytes, io::Error>;

#[derive(Clone, Debug, Default, Serialize)]
struct Observation {
    id: String,
    requests: u64,
    protocol: String,
    accept_encoding: String,
    datastar_request: String,
    selected_encoding: String,
    first_generated_us: Option<u128>,
    second_generated_us: Option<u128>,
    finished_us: Option<u128>,
    cleanup_us: Option<u128>,
    first_frame_bytes: usize,
    second_frame_bytes: usize,
    finish_tail_bytes: usize,
    aborted: bool,
}

struct StreamControl {
    observation: Mutex<Observation>,
    released: Mutex<bool>,
}

struct AppState {
    started: Instant,
    streams: Mutex<HashMap<String, Arc<StreamControl>>>,
}

impl AppState {
    fn elapsed_us(&self) -> u128 {
        self.started.elapsed().as_micros()
    }

    fn stream(&self, id: &str) -> Arc<StreamControl> {
        let mut streams = self
            .streams
            .lock()
            .expect("stream map mutex is not poisoned");
        Arc::clone(streams.entry(id.to_owned()).or_insert_with(|| {
            Arc::new(StreamControl {
                observation: Mutex::new(Observation {
                    id: id.to_owned(),
                    ..Observation::default()
                }),
                released: Mutex::new(false),
            })
        }))
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Coding {
    Identity,
    Brotli,
}

impl Coding {
    fn label(self) -> &'static str {
        match self {
            Self::Identity => "identity",
            Self::Brotli => "br",
        }
    }
}

#[derive(Serialize)]
struct Startup<'a> {
    event: &'a str,
    address: String,
    pid: u32,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let port = parse_port()?;
    let listener = TcpListener::bind(("127.0.0.1", port)).await?;
    let address = listener.local_addr()?;
    let state = Arc::new(AppState {
        started: Instant::now(),
        streams: Mutex::new(HashMap::new()),
    });

    println!(
        "{}",
        serde_json::to_string(&Startup {
            event: "listening",
            address: address.to_string(),
            pid: std::process::id(),
        })?
    );

    loop {
        let (stream, _) = listener.accept().await?;
        let state = Arc::clone(&state);
        tokio::spawn(async move {
            let service = service_fn(move |request| handle(request, Arc::clone(&state)));
            let connection = ConnectionBuilder::new(TokioExecutor::new());
            if let Err(error) = connection
                .serve_connection(TokioIo::new(stream), service)
                .await
            {
                eprintln!("connection error: {error}");
            }
        });
    }
}

fn parse_port() -> Result<u16, Box<dyn std::error::Error>> {
    let mut arguments = env::args().skip(1);
    let mut port = 0_u16;
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--port" => {
                port = arguments.next().ok_or("--port requires a value")?.parse()?;
            }
            _ => return Err(format!("unknown argument: {argument}").into()),
        }
    }
    Ok(port)
}

async fn handle(
    request: Request<Incoming>,
    state: Arc<AppState>,
) -> Result<Response<HttpBody>, Infallible> {
    let path = request.uri().path();
    let query = parse_query(request.uri().query().unwrap_or_default());
    let response = match path {
        "/" => page(&query),
        "/datastar.js" => bytes_response(
            StatusCode::OK,
            "text/javascript; charset=utf-8",
            Bytes::from_static(DATASTAR_BUNDLE),
        ),
        "/stream" => stream_response(request, &query, state).await,
        "/release" => release_response(&query, state),
        "/status" => status_response(&query, state),
        "/health" => text_response(StatusCode::OK, "ok\n"),
        _ => text_response(StatusCode::NOT_FOUND, "not found\n"),
    };
    Ok(response)
}

fn page(query: &HashMap<String, String>) -> Response<HttpBody> {
    let id = query.get("id").map(String::as_str).unwrap_or("browser");
    let coding = query
        .get("coding")
        .map(String::as_str)
        .unwrap_or("identity");
    if !valid_token(id) || !matches!(coding, "identity" | "br") {
        return text_response(StatusCode::BAD_REQUEST, "invalid page query\n");
    }
    let body = format!(
        r#"<!doctype html>
<html>
<head><meta charset="utf-8"><title>Datastar transport spike</title></head>
<body>
  <main id="phase">initial</main>
  <div data-init="@get('/stream?id={id}&amp;coding={coding}')"></div>
  <script type="module" src="/datastar.js"></script>
</body>
</html>
"#
    );
    bytes_response(
        StatusCode::OK,
        "text/html; charset=utf-8",
        Bytes::from(body),
    )
}

async fn stream_response(
    request: Request<Incoming>,
    query: &HashMap<String, String>,
    state: Arc<AppState>,
) -> Response<HttpBody> {
    let Some(id) = query.get("id") else {
        return text_response(StatusCode::BAD_REQUEST, "missing id\n");
    };
    if !valid_token(id) {
        return text_response(StatusCode::BAD_REQUEST, "invalid id\n");
    }
    let requested_coding = query
        .get("coding")
        .map(String::as_str)
        .unwrap_or("identity");
    let accept_encoding = request
        .headers()
        .get(ACCEPT_ENCODING)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .to_owned();
    let coding = match requested_coding {
        "identity" => Coding::Identity,
        "br" if accepts_brotli(&accept_encoding) => Coding::Brotli,
        "br" => return text_response(StatusCode::NOT_ACCEPTABLE, "br not accepted\n"),
        _ => return text_response(StatusCode::BAD_REQUEST, "invalid coding\n"),
    };

    let control = state.stream(id);
    {
        let mut observation = control
            .observation
            .lock()
            .expect("observation mutex is not poisoned");
        observation.requests += 1;
        observation.protocol = format!("{:?}", request.version());
        observation.accept_encoding = accept_encoding;
        observation.datastar_request = request
            .headers()
            .get("datastar-request")
            .and_then(|value| value.to_str().ok())
            .unwrap_or_default()
            .to_owned();
        observation.selected_encoding = coding.label().to_owned();
        observation.first_generated_us = Some(state.elapsed_us());
        observation.second_generated_us = None;
        observation.finished_us = None;
        observation.cleanup_us = None;
        observation.finish_tail_bytes = 0;
        observation.aborted = false;
    }

    let (producer, body) = bounded_body(3, FRAME_RESERVATION * 3);
    let first_reservation = producer
        .reserve(FRAME_RESERVATION)
        .expect("new response body has first-frame capacity");
    let mut encoder = (coding == Coding::Brotli).then(|| ExplicitBrotli::new(FRAME_RESERVATION));
    let first = encode(coding, encoder.as_mut(), &datastar_event(id, "one"))
        .expect("fixture is within bounded encoder output");
    let first_bytes = first.len();
    first_reservation
        .commit(first)
        .expect("new response body accepts first frame");
    control
        .observation
        .lock()
        .expect("observation mutex is not poisoned")
        .first_frame_bytes = first_bytes;

    tokio::spawn(produce_remainder(
        Arc::clone(&state),
        Arc::clone(&control),
        producer,
        coding,
        encoder,
        id.to_owned(),
    ));

    let mut response = Response::new(body.boxed());
    response.headers_mut().insert(
        CONTENT_TYPE,
        "text/event-stream; charset=utf-8".parse().unwrap(),
    );
    response
        .headers_mut()
        .insert(CACHE_CONTROL, "no-cache".parse().unwrap());
    response
        .headers_mut()
        .insert(VARY, "Accept-Encoding".parse().unwrap());
    response
        .headers_mut()
        .insert("x-accel-buffering", "no".parse().unwrap());
    if coding == Coding::Brotli {
        response
            .headers_mut()
            .insert(CONTENT_ENCODING, "br".parse().unwrap());
    }
    response
}

async fn produce_remainder(
    state: Arc<AppState>,
    control: Arc<StreamControl>,
    producer: BoundedProducer,
    coding: Coding,
    mut encoder: Option<ExplicitBrotli>,
    id: String,
) {
    loop {
        if producer.is_cancelled() {
            mark_cancelled(&state, &control);
            return;
        }
        if *control
            .released
            .lock()
            .expect("release mutex is not poisoned")
        {
            break;
        }
        sleep(Duration::from_millis(5)).await;
    }

    let second_reservation = match reserve_when_ready(&producer, FRAME_RESERVATION).await {
        Some(reservation) => reservation,
        None => {
            mark_cancelled(&state, &control);
            return;
        }
    };
    control
        .observation
        .lock()
        .expect("observation mutex is not poisoned")
        .second_generated_us = Some(state.elapsed_us());
    let second = match encode(coding, encoder.as_mut(), &datastar_event(&id, "two")) {
        Ok(bytes) => bytes,
        Err(_) => return,
    };
    let second_bytes = second.len();
    if second_reservation.commit(second).is_err() {
        mark_cancelled(&state, &control);
        return;
    }
    control
        .observation
        .lock()
        .expect("observation mutex is not poisoned")
        .second_frame_bytes = second_bytes;

    let tail_bytes = if let Some(encoder) = encoder {
        let tail_reservation = match reserve_when_ready(&producer, FRAME_RESERVATION).await {
            Some(reservation) => reservation,
            None => {
                mark_cancelled(&state, &control);
                return;
            }
        };
        let tail = match encoder.finish() {
            Ok(bytes) => bytes,
            Err(_) => return,
        };
        let tail_bytes = tail.len();
        if tail_reservation.commit(tail).is_err() {
            mark_cancelled(&state, &control);
            return;
        }
        tail_bytes
    } else {
        0
    };
    {
        let mut observation = control
            .observation
            .lock()
            .expect("observation mutex is not poisoned");
        observation.finish_tail_bytes = tail_bytes;
        observation.finished_us = Some(state.elapsed_us());
    }
    producer.close();
}

async fn reserve_when_ready(
    producer: &BoundedProducer,
    bytes: usize,
) -> Option<datastar_transport_spike::Reservation> {
    loop {
        match producer.reserve(bytes) {
            Ok(reservation) => return Some(reservation),
            Err(ReserveError::Closed) => return None,
            Err(ReserveError::Backpressured) => sleep(Duration::from_millis(2)).await,
        }
    }
}

fn mark_cancelled(state: &AppState, control: &StreamControl) {
    let mut observation = control
        .observation
        .lock()
        .expect("observation mutex is not poisoned");
    observation.aborted = true;
    observation.cleanup_us = Some(state.elapsed_us());
}

fn encode(coding: Coding, encoder: Option<&mut ExplicitBrotli>, event: &[u8]) -> io::Result<Bytes> {
    match coding {
        Coding::Identity => Ok(Bytes::copy_from_slice(event)),
        Coding::Brotli => encoder
            .expect("Brotli coding owns an encoder")
            .encode_event(event),
    }
}

fn datastar_event(id: &str, phase: &str) -> Vec<u8> {
    format!(
        "event: datastar-patch-elements\n\
         data: selector #phase\n\
         data: mode inner\n\
         data: elements <span data-phase=\"{phase}\" data-stream=\"{id}\">{phase}</span>\n\n"
    )
    .into_bytes()
}

fn release_response(query: &HashMap<String, String>, state: Arc<AppState>) -> Response<HttpBody> {
    let Some(id) = query.get("id") else {
        return text_response(StatusCode::BAD_REQUEST, "missing id\n");
    };
    if !valid_token(id) {
        return text_response(StatusCode::BAD_REQUEST, "invalid id\n");
    }
    *state
        .stream(id)
        .released
        .lock()
        .expect("release mutex is not poisoned") = true;
    text_response(StatusCode::OK, "released\n")
}

fn status_response(query: &HashMap<String, String>, state: Arc<AppState>) -> Response<HttpBody> {
    let Some(id) = query.get("id") else {
        return text_response(StatusCode::BAD_REQUEST, "missing id\n");
    };
    let Some(control) = state
        .streams
        .lock()
        .expect("stream map mutex is not poisoned")
        .get(id)
        .cloned()
    else {
        return text_response(StatusCode::NOT_FOUND, "unknown stream\n");
    };
    let observation = control
        .observation
        .lock()
        .expect("observation mutex is not poisoned")
        .clone();
    let body = serde_json::to_vec(&observation).expect("observation serializes");
    bytes_response(StatusCode::OK, "application/json", Bytes::from(body))
}

fn parse_query(query: &str) -> HashMap<String, String> {
    query
        .split('&')
        .filter(|pair| !pair.is_empty())
        .map(|pair| pair.split_once('=').unwrap_or((pair, "")))
        .map(|(key, value)| (key.to_owned(), value.to_owned()))
        .collect()
}

fn valid_token(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 80
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
}

fn accepts_brotli(header: &str) -> bool {
    header.split(',').any(|item| {
        let mut parts = item.trim().split(';');
        let coding = parts.next().unwrap_or_default().trim();
        if !coding.eq_ignore_ascii_case("br") {
            return false;
        }
        !parts.any(|parameter| {
            parameter
                .trim()
                .strip_prefix("q=")
                .is_some_and(|quality| quality.trim() == "0")
        })
    })
}

fn text_response(status: StatusCode, body: &'static str) -> Response<HttpBody> {
    bytes_response(
        status,
        "text/plain; charset=utf-8",
        Bytes::from_static(body.as_bytes()),
    )
}

fn bytes_response(
    status: StatusCode,
    content_type: &'static str,
    body: Bytes,
) -> Response<HttpBody> {
    let body = Full::new(body).map_err(|never| match never {}).boxed();
    Response::builder()
        .status(status)
        .header(CONTENT_TYPE, content_type)
        .body(body)
        .expect("static response is valid")
}
