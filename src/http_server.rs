//! Tokio/Hyper server lifecycle and the provided Roc application entrypoints.

use crate::abi::{
    roc_host, ServerConfig, ServerHeader, ServerRequest, ServerResponse, ServerShutdownReason,
};
use crate::request_body::{clear_registry, install_registry, BodyRegistry, PumpError};
use crate::request_parts::{request_target, RequestPartsBacking};
use crate::roc_platform_abi::*;
use crate::shutdown::{RequestTracker, ShutdownController, ShutdownReason};
use bytes::Bytes;
use futures::{Future, FutureExt, StreamExt};
use http_body_util::{BodyExt, Full};
use hyper::header::CONTENT_LENGTH;
use hyper_util::rt::{TokioExecutor, TokioIo};
use hyper_util::server::conn::auto;
use std::convert::Infallible;
use std::net::SocketAddr;
use std::panic::AssertUnwindSafe;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};
use tokio::task::{spawn_blocking, JoinSet};

#[derive(Clone, Debug)]
struct RuntimeConfig {
    host: String,
    port: u16,
    max_connections: usize,
    max_handlers: usize,
    max_queued_handlers: usize,
    body_max_bytes: u64,
    body_chunk_bytes: usize,
    body_buffered_chunks: usize,
    drain_timeout: Duration,
    hook_timeout: Duration,
}

impl RuntimeConfig {
    fn from_roc(config: ServerConfig) -> Result<Self, String> {
        let host = config.host.as_str().to_owned();
        unsafe { config.host.decref(roc_host()) };

        if config.body_chunk_bytes == 0 {
            return Err("request body chunk size must be non-zero".to_owned());
        }
        if config.body_buffered_chunks == 0 {
            return Err("request body buffered chunk count must be non-zero".to_owned());
        }
        let (max_connections, max_handlers) =
            validate_concurrency_limits(config.max_connections, config.max_handlers)?;
        Ok(Self {
            host,
            port: config.port,
            max_connections,
            max_handlers,
            max_queued_handlers: config.max_queued_handlers as usize,
            body_max_bytes: config.body_max_bytes,
            body_chunk_bytes: config.body_chunk_bytes as usize,
            body_buffered_chunks: config.body_buffered_chunks as usize,
            drain_timeout: Duration::from_millis(config.drain_timeout_ms),
            hook_timeout: Duration::from_millis(config.hook_timeout_ms),
        })
    }

    fn max_http2_streams_per_connection(&self) -> u32 {
        // The Roc configuration fields are u16, so their sum always fits u32.
        // A stream still passes through the global handler admission gate; the
        // HTTP/2 setting prevents one connection from creating more service
        // futures than the complete active-plus-queued handler budget.
        (self.max_handlers + self.max_queued_handlers)
            .max(1)
            .try_into()
            .expect("validated handler capacity fits in u32")
    }
}

fn validate_concurrency_limits(
    max_connections: u32,
    max_handlers: u16,
) -> Result<(usize, usize), String> {
    if max_connections == 0 {
        return Err("maximum active connections must be non-zero".to_owned());
    }
    if max_handlers == 0 {
        return Err("maximum active Roc handlers must be non-zero".to_owned());
    }
    let max_connections = max_connections as usize;
    if max_connections > Semaphore::MAX_PERMITS {
        return Err(format!(
            "maximum active connections cannot exceed {} on this target",
            Semaphore::MAX_PERMITS
        ));
    }
    Ok((max_connections, max_handlers as usize))
}

/// Bounds both the synchronous Roc invocations submitted to Tokio's blocking
/// pool and the requests waiting to submit one.
///
/// An active permit is acquired before `spawn_blocking`, and the runtime's
/// blocking thread limit is exactly `max_handlers`. Tokio's internal blocking
/// queue is therefore not used as an implicit request queue.
#[derive(Clone)]
struct HandlerAdmission {
    active: Arc<Semaphore>,
    queued: Arc<Semaphore>,
}

impl HandlerAdmission {
    fn new(max_handlers: usize, max_queued_handlers: usize) -> Self {
        Self {
            active: Arc::new(Semaphore::new(max_handlers)),
            queued: Arc::new(Semaphore::new(max_queued_handlers)),
        }
    }

    async fn admit(&self) -> Option<ActiveHandler> {
        if let Ok(active) = Arc::clone(&self.active).try_acquire_owned() {
            return Some(ActiveHandler { _permit: active });
        }

        let queued = Arc::clone(&self.queued).try_acquire_owned().ok()?;
        let active = Arc::clone(&self.active)
            .acquire_owned()
            .await
            .expect("handler admission semaphore is never closed");
        drop(queued);
        Some(ActiveHandler { _permit: active })
    }
}

struct ActiveHandler {
    _permit: OwnedSemaphorePermit,
}

/// The one Roc-owned application context retained for the server lifetime.
///
/// Rust never dereferences this opaque pointer. Each handler atomically retains
/// one owned Roc reference immediately before calling Roc, and the provided Roc
/// wrapper consumes that reference. The root reference is consumed by
/// `shutdown!` only after all request handlers have drained.
struct RocContext {
    root: RocBox,
}

impl RocContext {
    fn new(root: RocBox) -> Self {
        Self { root }
    }

    fn retain_for_request(&self) -> RocBox {
        // SAFETY: `root` is the live reference returned by `init!`. Generated
        // Roc ARC uses atomic refcounts for a box shared across host threads.
        // A null box is the valid zero-allocation representation of an empty
        // context and `incref_box` deliberately treats it as static data.
        unsafe { incref_box(self.root, 1) };
        self.root
    }
}

// SAFETY: Rust treats the pointer as opaque and immutable. Sharing performs
// only generated atomic ARC operations; mutation is neither exposed nor
// performed through this wrapper.
unsafe impl Send for RocContext {}
unsafe impl Sync for RocContext {}

#[derive(Clone)]
struct ServerContext {
    config: Arc<RuntimeConfig>,
    roc_context: Arc<RocContext>,
    bodies: Arc<BodyRegistry>,
    handlers: HandlerAdmission,
    requests: RequestTracker,
    shutdown: ShutdownController,
}

pub fn start() -> i32 {
    let exit_code = start_inner();
    crate::http::shutdown();
    crate::tcp::shutdown();
    exit_code
}

fn start_inner() -> i32 {
    let init_result = unsafe { roc_init_for_host() };
    let initialized = match init_result.tag {
        InitForHostResultTag::Ok => init_result.payload_ok(),
        InitForHostResultTag::Err => return exit_code_to_i32(init_result.payload_err()),
    };

    let raw_context = initialized.context;
    let config = match RuntimeConfig::from_roc(initialized.config) {
        Ok(config) => config,
        Err(detail) => {
            return finish_shutdown(
                ShutdownReason::StartupFailed(detail),
                raw_context,
                Duration::from_secs(10),
            );
        }
    };

    let roc_context = Arc::new(RocContext::new(raw_context));
    let bodies = install_registry(config.body_buffered_chunks);
    let shutdown = ShutdownController::new();
    let context = ServerContext {
        config: Arc::new(config.clone()),
        roc_context: Arc::clone(&roc_context),
        bodies,
        handlers: HandlerAdmission::new(config.max_handlers, config.max_queued_handlers),
        requests: RequestTracker::new(),
        shutdown: shutdown.clone(),
    };

    let reason = match tokio::runtime::Builder::new_multi_thread()
        .max_blocking_threads(config.max_handlers)
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime.block_on(run_server(context)),
        Err(error) => {
            ShutdownReason::RuntimeFailed(format!("failed to initialize Tokio runtime: {error}"))
        }
    };

    clear_registry();
    debug_assert_eq!(
        Arc::strong_count(&roc_context),
        1,
        "all request and connection context references must drain before shutdown"
    );
    finish_shutdown(reason, roc_context.root, config.hook_timeout)
}

fn finish_shutdown(reason: ShutdownReason, context: RocBox, hook_timeout: Duration) -> i32 {
    let default_exit_code = reason.default_exit_code();
    let (tag, detail) = shutdown_reason_to_host(&reason);
    let raw_reason = ServerShutdownReason {
        detail: RocStr::from_str(detail, roc_host()),
        tag,
    };

    let (finished_sender, finished_receiver) = std::sync::mpsc::sync_channel(1);
    let watchdog = std::thread::Builder::new()
        .name("roc-shutdown-watchdog".to_owned())
        .spawn(move || {
            if finished_receiver.recv_timeout(hook_timeout).is_err() {
                eprintln!(
                    "Roc shutdown hook exceeded its {:?} timeout; forcing process exit",
                    hook_timeout
                );
                std::process::exit(1);
            }
        })
        .expect("failed to start shutdown watchdog");

    let result = unsafe { roc_shutdown_for_host(raw_reason, context) };
    let _ = finished_sender.send(());
    let _ = watchdog.join();

    match result.tag {
        ShutdownForHostResultTag::Ok => default_exit_code,
        ShutdownForHostResultTag::Err => exit_code_to_i32(result.payload_err()),
    }
}

fn shutdown_reason_to_host(reason: &ShutdownReason) -> (u8, &str) {
    match reason {
        ShutdownReason::ApplicationRequested { .. } => (0, ""),
        ShutdownReason::Interrupt => (1, ""),
        ShutdownReason::Terminate => (2, ""),
        ShutdownReason::StartupFailed(detail) => (3, detail),
        ShutdownReason::RuntimeFailed(detail) => (4, detail),
    }
}

fn exit_code_to_i32(code: i64) -> i32 {
    i32::try_from(code).unwrap_or(if code < 0 { i32::MIN } else { i32::MAX })
}

/// Canonical mapping shared with InternalServer.from_host_method.
fn method_to_tag(method: &hyper::Method) -> u8 {
    match *method {
        hyper::Method::CONNECT => 0,
        hyper::Method::DELETE => 1,
        hyper::Method::GET => 3,
        hyper::Method::HEAD => 4,
        hyper::Method::OPTIONS => 5,
        hyper::Method::PATCH => 6,
        hyper::Method::POST => 7,
        hyper::Method::PUT => 8,
        hyper::Method::TRACE => 9,
        _ if method.as_str() == "QUERY" => 10,
        _ => 2,
    }
}

fn content_length(headers: &hyper::HeaderMap) -> Option<u64> {
    headers
        .get(CONTENT_LENGTH)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse().ok())
}

fn request_body_error(error: hyper::Error) -> PumpError {
    if error.is_canceled() || error.is_closed() || error.is_incomplete_message() {
        PumpError::ClientDisconnected
    } else {
        PumpError::InvalidBody(error.to_string())
    }
}

fn request_headers_are_utf8(headers: &hyper::HeaderMap) -> bool {
    headers.values().all(|value| value.to_str().is_ok())
}

fn request_to_roc(
    parts: hyper::http::request::Parts,
    body_id: u64,
    body_limit: u64,
    declared_length: Option<u64>,
) -> ServerRequest {
    let roc_host = roc_host();
    let backing = match RequestPartsBacking::new(parts) {
        Ok(backing) => backing,
        Err(parts) => {
            return request_to_roc_copied(*parts, body_id, body_limit, declared_length, roc_host);
        }
    };
    let method_tag = method_to_tag(backing.method());
    let mut backing_references = 0;
    let method_ext = if method_tag == 2 {
        backing_references += 1;
        backing.roc_str(backing.method().as_str())
    } else {
        RocStr::empty()
    };
    let headers = unsafe { RocList::<ServerHeader>::allocate(backing.headers().len(), roc_host) };
    for (index, (name, value)) in backing.headers().iter().enumerate() {
        let header = ServerHeader {
            name: backing.roc_str(name.as_str()),
            value: backing.roc_str(
                value
                    .to_str()
                    .expect("request headers are validated before Roc conversion"),
            ),
        };
        // SAFETY: `headers` allocated exactly HeaderMap::len() uninitialized
        // elements, and HeaderMap iteration yields that many entries.
        unsafe { headers.elements.add(index).write(header) };
    }
    backing_references += headers.len() * 2;
    let target = backing.roc_str(backing.target());
    backing_references += 1;
    backing.install(backing_references);

    ServerRequest {
        body_id,
        body_limit_bytes: body_limit,
        content_length: declared_length.unwrap_or_default(),
        headers,
        method_ext,
        target,
        content_length_known: declared_length.is_some(),
        method: method_tag,
    }
}

fn request_to_roc_copied(
    parts: hyper::http::request::Parts,
    body_id: u64,
    body_limit: u64,
    declared_length: Option<u64>,
    roc_host: &RocHost,
) -> ServerRequest {
    let method_tag = method_to_tag(&parts.method);
    let method_ext = if method_tag == 2 {
        RocStr::from_str(parts.method.as_str(), roc_host)
    } else {
        RocStr::empty()
    };
    let headers = unsafe { RocList::<ServerHeader>::allocate(parts.headers.len(), roc_host) };
    for (index, (name, value)) in parts.headers.iter().enumerate() {
        let header = ServerHeader {
            name: RocStr::from_str(name.as_str(), roc_host),
            value: RocStr::from_str(
                value
                    .to_str()
                    .expect("request headers are validated before Roc conversion"),
                roc_host,
            ),
        };
        // SAFETY: `headers` allocated exactly HeaderMap::len() uninitialized
        // elements, and HeaderMap iteration yields that many entries.
        unsafe { headers.elements.add(index).write(header) };
    }
    let target = request_target(&parts);

    ServerRequest {
        body_id,
        body_limit_bytes: body_limit,
        content_length: declared_length.unwrap_or_default(),
        headers,
        method_ext,
        target: RocStr::from_str(target, roc_host),
        content_length_known: declared_length.is_some(),
        method: method_tag,
    }
}

fn call_roc(
    request: ServerRequest,
    context: RocBox,
) -> (hyper::Response<Full<Bytes>>, Option<i64>) {
    let response = unsafe { roc_respond_for_host(request, context) };
    response_to_hyper(response)
}

fn response_to_hyper(response: ServerResponse) -> (hyper::Response<Full<Bytes>>, Option<i64>) {
    let stop_code = response.stop.then_some(response.exit_code);
    let mut builder = hyper::Response::builder().status(response.status);
    for header in response.headers.as_slice() {
        builder = builder.header(header.name.as_str(), header.value.as_str());
    }
    let body = Bytes::from_owner(RocResponseOwner { response });
    let hyper_response = builder
        .body(Full::new(body))
        .unwrap_or_else(|_| internal_server_error("Failed to build response"));
    (hyper_response, stop_code)
}

/// Owns every Roc reference in a response while Hyper may still transmit the
/// body. This is intentionally the whole response rather than just its body:
/// generated recursive decref remains the single source of truth, and keeping
/// the small header descriptors alive until body completion is bounded.
struct RocResponseOwner {
    response: ServerResponse,
}

impl AsRef<[u8]> for RocResponseOwner {
    fn as_ref(&self) -> &[u8] {
        self.response.body.as_slice()
    }
}

// SAFETY: `roc_respond_for_host` has returned, so these Roc allocations are
// immutable. Their ARC slots are atomic, and the shared RocHost deallocator is
// thread-safe. Hyper may therefore move the owner to a transport worker.
unsafe impl Send for RocResponseOwner {}

impl Drop for RocResponseOwner {
    fn drop(&mut self) {
        // SAFETY: this owner contains exactly the references returned by Roc,
        // and Bytes drops its owner exactly once after its last clone.
        unsafe { self.response.decref(roc_host()) };
    }
}

fn internal_server_error(message: &str) -> hyper::Response<Full<Bytes>> {
    hyper::Response::builder()
        .status(hyper::StatusCode::INTERNAL_SERVER_ERROR)
        .body(Full::new(Bytes::copy_from_slice(message.as_bytes())))
        .expect("static 500 response is valid")
}

fn service_unavailable() -> hyper::Response<Full<Bytes>> {
    hyper::Response::builder()
        .status(hyper::StatusCode::SERVICE_UNAVAILABLE)
        .body(Full::new(Bytes::from_static(b"Server is shutting down")))
        .expect("static 503 response is valid")
}

fn overloaded() -> hyper::Response<Full<Bytes>> {
    hyper::Response::builder()
        .status(hyper::StatusCode::SERVICE_UNAVAILABLE)
        .body(Full::new(Bytes::from_static(b"Server is overloaded")))
        .expect("static 503 response is valid")
}

fn invalid_request_headers() -> hyper::Response<Full<Bytes>> {
    hyper::Response::builder()
        .status(hyper::StatusCode::BAD_REQUEST)
        .body(Full::new(Bytes::from_static(
            b"Request header values must be valid UTF-8",
        )))
        .expect("static 400 response is valid")
}

fn payload_too_large(limit: u64) -> hyper::Response<Full<Bytes>> {
    hyper::Response::builder()
        .status(hyper::StatusCode::PAYLOAD_TOO_LARGE)
        .body(Full::new(Bytes::from(format!(
            "Request body exceeds the {limit}-byte limit"
        ))))
        .expect("static 413 response is valid")
}

async fn handle_req(
    request: hyper::Request<hyper::body::Incoming>,
    context: ServerContext,
) -> hyper::Response<Full<Bytes>> {
    let active_request = match context.requests.begin() {
        Some(active) => active,
        None => return service_unavailable(),
    };

    if !request_headers_are_utf8(request.headers()) {
        return invalid_request_headers();
    }

    let declared_length = content_length(request.headers());
    if declared_length.is_some_and(|length| length > context.config.body_max_bytes) {
        return payload_too_large(context.config.body_max_bytes);
    }

    let active_handler = match context.handlers.admit().await {
        Some(active) => active,
        None => return overloaded(),
    };

    let (parts, body) = request.into_parts();
    let registration = context.bodies.register(context.config.body_max_bytes);
    let body_id = registration.id;
    let stream = body
        .into_data_stream()
        .map(|frame| frame.map_err(request_body_error));
    let chunk_bytes = context.config.body_chunk_bytes;
    tokio::spawn(async move { registration.pump.run(stream, chunk_bytes).await });

    let body_limit = context.config.body_max_bytes;
    let bodies = Arc::clone(&context.bodies);
    let roc_context = Arc::clone(&context.roc_context);
    let handled = spawn_blocking(move || {
        // These guards intentionally live in the non-cancellable blocking task.
        // Aborting its Tokio JoinHandle must not make shutdown believe Roc has
        // stopped using its handler slot, body, or immutable application
        // context.
        let _active_request = active_request;
        let _active_handler = active_handler;
        let roc_request = request_to_roc(parts, body_id, body_limit, declared_length);
        let request_context = roc_context.retain_for_request();
        let result = call_roc(roc_request, request_context);
        bodies.expire(body_id);
        result
    })
    .await;

    match handled {
        Ok((response, Some(exit_code))) => {
            context
                .shutdown
                .request(ShutdownReason::ApplicationRequested { exit_code });
            response
        }
        Ok((response, None)) => response,
        Err(error) => {
            context.bodies.expire(body_id);
            eprintln!("Recovered from calling Roc: {error:?}");
            internal_server_error("500 Internal Server Error")
        }
    }
}

async fn handle_panics(
    future: impl Future<Output = hyper::Response<Full<Bytes>>>,
) -> Result<hyper::Response<Full<Bytes>>, Infallible> {
    match AssertUnwindSafe(future).catch_unwind().await {
        Ok(response) => Ok(response),
        Err(_) => Ok(internal_server_error("Panic detected")),
    }
}

fn connection_builder(max_http2_streams: u32) -> auto::Builder<TokioExecutor> {
    let mut builder = auto::Builder::new(TokioExecutor::new());
    builder.http2().max_concurrent_streams(max_http2_streams);
    builder
}

async fn serve_connection(stream: tokio::net::TcpStream, context: ServerContext) {
    let io = TokioIo::new(stream);
    let service_context = context.clone();
    let builder = connection_builder(context.config.max_http2_streams_per_connection());
    let connection = builder.serve_connection(
        io,
        hyper::service::service_fn(move |request| {
            handle_panics(handle_req(request, service_context.clone()))
        }),
    );
    tokio::pin!(connection);

    tokio::select! {
        result = &mut connection => {
            if let Err(error) = result {
                eprintln!("Error serving connection: {error:?}");
            }
        }
        _ = context.shutdown.requested() => {
            connection.as_mut().graceful_shutdown();
            if let Err(error) = connection.await {
                eprintln!("Error draining connection: {error:?}");
            }
        }
    }
}

async fn run_server(context: ServerContext) -> ShutdownReason {
    let listener =
        match tokio::net::TcpListener::bind((context.config.host.as_str(), context.config.port))
            .await
        {
            Ok(listener) => listener,
            Err(error) => {
                return ShutdownReason::StartupFailed(format!(
                    "failed to bind {}:{}: {error}",
                    context.config.host, context.config.port
                ));
            }
        };
    let address = listener
        .local_addr()
        .unwrap_or_else(|_| SocketAddr::from(([127, 0, 0, 1], context.config.port)));
    println!("Listening on <http://{address}>");

    let signal_shutdown = context.shutdown.clone();
    let signal_task = tokio::spawn(async move { watch_signals(signal_shutdown).await });
    let mut connections = JoinSet::new();
    let connection_slots = Arc::new(Semaphore::new(context.config.max_connections));
    let mut next_connection_slot = None;

    let reason = loop {
        tokio::select! {
            biased;
            reason = context.shutdown.requested() => break reason,
            completed = connections.join_next(), if !connections.is_empty() => {
                if let Some(Err(error)) = completed {
                    eprintln!("Connection task failed: {error:?}");
                }
            },
            slot = Arc::clone(&connection_slots).acquire_owned(),
                if next_connection_slot.is_none() =>
            {
                next_connection_slot = Some(
                    slot.expect("connection admission semaphore is never closed")
                );
            }
            accepted = listener.accept(), if next_connection_slot.is_some() => match accepted {
                Ok((stream, _)) => {
                    if let Err(error) = stream.set_nodelay(true) {
                        eprintln!("Failed to disable Nagle's algorithm: {error}");
                        continue;
                    }
                    let connection_slot = next_connection_slot
                        .take()
                        .expect("accept is polled only with a reserved connection slot");
                    let connection_context = context.clone();
                    connections.spawn(async move {
                        let _connection_slot = connection_slot;
                        serve_connection(stream, connection_context).await;
                    });
                }
                Err(error) => eprintln!("Failed to accept incoming connection: {error}"),
            },
        }
    };

    context.requests.begin_draining();
    let drained = tokio::time::timeout(context.config.drain_timeout, async {
        context.requests.wait_for_idle().await;
        while connections.join_next().await.is_some() {}
    })
    .await;

    if drained.is_err() {
        context.bodies.cancel_all();
        connections.abort_all();
        eprintln!(
            "Graceful drain exceeded {:?}; request bodies were cancelled and connections aborted; forcing process exit without running the Roc shutdown hook",
            context.config.drain_timeout
        );

        // spawn_blocking Roc handlers cannot be safely preempted. Running the
        // shutdown hook or dropping the context while one may still use it
        // would be unsound, so the configured drain deadline is a hard process
        // deadline and intentionally skips application shutdown cleanup.
        std::process::exit(1);
    }

    signal_task.abort();
    reason
}

#[derive(Default)]
struct TerminationSignals {
    seen_one: bool,
}

impl TerminationSignals {
    /// Return true only after a previous OS termination signal was observed.
    fn should_force_exit(&mut self) -> bool {
        std::mem::replace(&mut self.seen_one, true)
    }
}

#[cfg(unix)]
async fn watch_signals(shutdown: ShutdownController) {
    use tokio::signal::unix::{signal, SignalKind};

    let mut interrupt = signal(SignalKind::interrupt()).expect("failed to register SIGINT");
    let mut terminate = signal(SignalKind::terminate()).expect("failed to register SIGTERM");
    let mut signals = TerminationSignals::default();
    loop {
        let reason = tokio::select! {
            _ = interrupt.recv() => ShutdownReason::Interrupt,
            _ = terminate.recv() => ShutdownReason::Terminate,
        };
        if signals.should_force_exit() {
            eprintln!("Second termination signal received; forcing process exit");
            std::process::exit(1);
        }
        shutdown.request(reason);
    }
}

#[cfg(not(unix))]
async fn watch_signals(shutdown: ShutdownController) {
    let mut signals = TerminationSignals::default();
    loop {
        if tokio::signal::ctrl_c().await.is_err() {
            shutdown.request(ShutdownReason::RuntimeFailed(
                "failed to listen for Ctrl-C".to_owned(),
            ));
            return;
        }
        if signals.should_force_exit() {
            eprintln!("Second termination signal received; forcing process exit");
            std::process::exit(1);
        }
        shutdown.request(ShutdownReason::Interrupt);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn method_tags_match_internal_server_contract() {
        assert_eq!(method_to_tag(&hyper::Method::CONNECT), 0);
        assert_eq!(method_to_tag(&hyper::Method::DELETE), 1);
        assert_eq!(method_to_tag(&hyper::Method::GET), 3);
        assert_eq!(method_to_tag(&hyper::Method::HEAD), 4);
        assert_eq!(method_to_tag(&hyper::Method::OPTIONS), 5);
        assert_eq!(method_to_tag(&hyper::Method::PATCH), 6);
        assert_eq!(method_to_tag(&hyper::Method::POST), 7);
        assert_eq!(method_to_tag(&hyper::Method::PUT), 8);
        assert_eq!(method_to_tag(&hyper::Method::TRACE), 9);
        assert_eq!(
            method_to_tag(&hyper::Method::from_bytes(b"QUERY").unwrap()),
            10
        );
        assert_eq!(
            method_to_tag(&hyper::Method::from_bytes(b"PROPFIND").unwrap()),
            2
        );
    }

    #[test]
    fn parses_only_valid_content_length() {
        let mut headers = hyper::HeaderMap::new();
        assert_eq!(content_length(&headers), None);
        headers.insert(CONTENT_LENGTH, "123".parse().unwrap());
        assert_eq!(content_length(&headers), Some(123));
        headers.insert(CONTENT_LENGTH, "not-a-number".parse().unwrap());
        assert_eq!(content_length(&headers), None);
    }

    #[test]
    fn identifies_non_utf8_request_header_values() {
        let mut headers = hyper::HeaderMap::new();
        headers.insert("x-valid", hyper::header::HeaderValue::from_static("hello"));
        assert!(request_headers_are_utf8(&headers));

        headers.insert(
            "x-invalid",
            hyper::header::HeaderValue::from_bytes(b"\xff").unwrap(),
        );
        assert!(!request_headers_are_utf8(&headers));
    }

    #[test]
    fn absolute_uri_target_is_normalized_to_path_and_query() {
        let request = hyper::Request::builder()
            .method(hyper::Method::GET)
            .uri("http://example.test/a/path?from=h2")
            .body(())
            .unwrap();
        let (parts, _) = request.into_parts();
        assert_eq!(request_target(&parts), "/a/path?from=h2");
    }

    #[test]
    fn connect_target_preserves_authority_form() {
        let request = hyper::Request::builder()
            .method(hyper::Method::CONNECT)
            .uri("upstream.example:443")
            .body(())
            .unwrap();
        let (parts, _) = request.into_parts();
        assert_eq!(request_target(&parts), "upstream.example:443");
    }

    #[tokio::test]
    async fn request_metadata_and_escaped_response_body_share_hyper_storage() {
        static INITIALIZE: std::sync::Once = std::sync::Once::new();
        INITIALIZE.call_once(crate::abi::initialize_roc_host);

        let request = hyper::Request::builder()
            .method("PROPFIND")
            .uri("/a/long/request/target?with=a-query")
            .header("x-long-request-header", "a sufficiently long header value")
            .body(())
            .unwrap();
        let original_target_ptr = request.uri().path_and_query().unwrap().as_str().as_ptr();
        let original_headers: Vec<(*const u8, *const u8)> = request
            .headers()
            .iter()
            .map(|(name, value)| (name.as_str().as_ptr(), value.as_bytes().as_ptr()))
            .collect();
        let (parts, _) = request.into_parts();

        let roc_request = request_to_roc(parts, 1, 4096, None);
        assert_eq!(crate::request_parts::active_backings(), 1);
        assert!(roc_request.target.is_seamless_slice());
        assert_eq!(roc_request.target.as_u8_ptr(), original_target_ptr);
        assert!(roc_request.method_ext.is_seamless_slice());
        assert_eq!(roc_request.method_ext.as_str(), "PROPFIND");
        for (header, (name_ptr, value_ptr)) in
            roc_request.headers.as_slice().iter().zip(original_headers)
        {
            assert!(header.name.is_seamless_slice());
            assert!(header.value.is_seamless_slice());
            assert_eq!(header.name.as_u8_ptr(), name_ptr);
            assert_eq!(header.value.as_u8_ptr(), value_ptr);
            assert_eq!(
                header.name.capacity_or_alloc_ptr,
                roc_request.target.capacity_or_alloc_ptr
            );
            assert_eq!(
                header.value.capacity_or_alloc_ptr,
                roc_request.target.capacity_or_alloc_ptr
            );
        }

        // Model Roc returning `Str.to_utf8(request.target)`: the output list
        // owns one additional reference to the same request-parts backing.
        let target = roc_request.target;
        unsafe { target.incref(1) };
        let escaped_body = RocListWith::<u8, false> {
            elements: target.bytes,
            length: target.len(),
            capacity_or_alloc_ptr: target.capacity_or_alloc_ptr,
        };
        let escaped_ptr = escaped_body.elements;

        unsafe { roc_request.decref(roc_host()) };
        assert_eq!(
            crate::request_parts::active_backings(),
            1,
            "the escaped response slice must keep request metadata alive"
        );

        let roc_response = ServerResponse {
            exit_code: 0,
            body: escaped_body,
            headers: RocList::empty(),
            status: 200,
            stop: false,
        };
        let (response, stop_code) = response_to_hyper(roc_response);
        assert_eq!(stop_code, None);
        assert_eq!(crate::request_parts::active_backings(), 1);

        let body = response.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(body.as_ptr(), escaped_ptr);
        assert_eq!(body.as_ref(), b"/a/long/request/target?with=a-query");
        assert_eq!(crate::request_parts::active_backings(), 1);
        drop(body);
        assert_eq!(
            crate::request_parts::active_backings(),
            0,
            "Hyper's final Bytes drop must release the escaped Roc slice"
        );
    }

    #[test]
    fn shutdown_reason_tags_match_internal_server_contract() {
        assert_eq!(
            shutdown_reason_to_host(&ShutdownReason::ApplicationRequested { exit_code: 0 }).0,
            0
        );
        assert_eq!(shutdown_reason_to_host(&ShutdownReason::Interrupt).0, 1);
        assert_eq!(shutdown_reason_to_host(&ShutdownReason::Terminate).0, 2);
        assert_eq!(
            shutdown_reason_to_host(&ShutdownReason::StartupFailed("x".to_owned())).0,
            3
        );
        assert_eq!(
            shutdown_reason_to_host(&ShutdownReason::RuntimeFailed("x".to_owned())).0,
            4
        );
    }

    #[test]
    fn app_shutdown_then_first_os_signal_does_not_force_exit() {
        let shutdown = ShutdownController::new();
        shutdown.request(ShutdownReason::ApplicationRequested { exit_code: 0 });

        let mut signals = TerminationSignals::default();
        assert!(!signals.should_force_exit());
        shutdown.request(ShutdownReason::Terminate);
        assert_eq!(
            shutdown.reason(),
            Some(ShutdownReason::ApplicationRequested { exit_code: 0 })
        );

        assert!(signals.should_force_exit());
    }

    #[test]
    fn concurrency_limits_reject_zero_connections_and_handlers() {
        assert_eq!(
            validate_concurrency_limits(0, 1),
            Err("maximum active connections must be non-zero".to_owned())
        );
        assert_eq!(
            validate_concurrency_limits(1, 0),
            Err("maximum active Roc handlers must be non-zero".to_owned())
        );
        assert_eq!(validate_concurrency_limits(256, 32), Ok((256, 32)));
    }

    #[tokio::test]
    async fn handler_admission_bounds_active_and_queued_work() {
        let admission = HandlerAdmission::new(1, 1);
        let first = admission.admit().await.unwrap();

        let waiting = {
            let admission = admission.clone();
            tokio::spawn(async move { admission.admit().await })
        };
        tokio::time::timeout(Duration::from_secs(1), async {
            while admission.queued.available_permits() != 0 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("second handler did not enter the bounded queue");
        assert_eq!(admission.queued.available_permits(), 0);
        assert!(
            admission.admit().await.is_none(),
            "work beyond the active and queued limits must be rejected"
        );

        drop(first);
        let second = tokio::time::timeout(Duration::from_secs(1), waiting)
            .await
            .expect("queued handler was not admitted after capacity became available")
            .unwrap()
            .expect("bounded queued handler should be admitted");
        assert_eq!(admission.queued.available_permits(), 1);
        assert_eq!(admission.active.available_permits(), 0);
        drop(second);
        assert_eq!(admission.active.available_permits(), 1);
    }

    #[tokio::test]
    async fn zero_handler_queue_rejects_immediately_at_saturation() {
        let admission = HandlerAdmission::new(1, 0);
        let active = admission.admit().await.unwrap();
        assert!(admission.admit().await.is_none());
        drop(active);
        assert!(admission.admit().await.is_some());
    }

    #[test]
    fn overload_response_is_protocol_neutral() {
        let response = overloaded();
        assert_eq!(response.status(), hyper::StatusCode::SERVICE_UNAVAILABLE);
        assert!(!response.headers().contains_key(hyper::header::CONNECTION));
    }

    #[test]
    fn invalid_header_response_is_protocol_neutral() {
        let response = invalid_request_headers();
        assert_eq!(response.status(), hyper::StatusCode::BAD_REQUEST);
        assert!(!response.headers().contains_key(hyper::header::CONNECTION));
    }

    #[test]
    fn http2_stream_limit_matches_the_complete_handler_budget() {
        let config = RuntimeConfig {
            host: "127.0.0.1".to_owned(),
            port: 8000,
            max_connections: 256,
            max_handlers: 32,
            max_queued_handlers: 64,
            body_max_bytes: 1024,
            body_chunk_bytes: 1024,
            body_buffered_chunks: 1,
            drain_timeout: Duration::from_secs(30),
            hook_timeout: Duration::from_secs(10),
        };
        assert_eq!(config.max_http2_streams_per_connection(), 96);
    }

    #[tokio::test]
    async fn auto_server_accepts_an_http2_prior_knowledge_request() {
        let (client_io, server_io) = tokio::io::duplex(4096);
        let server = tokio::spawn(async move {
            connection_builder(8)
                .serve_connection(
                    TokioIo::new(server_io),
                    hyper::service::service_fn(
                        |request: hyper::Request<hyper::body::Incoming>| async move {
                            assert_eq!(request.version(), hyper::Version::HTTP_2);
                            Ok::<_, Infallible>(hyper::Response::new(Full::new(
                                Bytes::from_static(b"http2"),
                            )))
                        },
                    ),
                )
                .await
                .expect("HTTP/2 server connection should complete without error");
        });

        let (mut sender, connection) = hyper::client::conn::http2::handshake::<_, _, Full<Bytes>>(
            TokioExecutor::new(),
            TokioIo::new(client_io),
        )
        .await
        .expect("HTTP/2 prior-knowledge handshake should succeed");
        let client = tokio::spawn(connection);
        let request = hyper::Request::builder()
            .uri("http://localhost/http2")
            .body(Full::new(Bytes::new()))
            .unwrap();
        let response = sender
            .send_request(request)
            .await
            .expect("HTTP/2 request should receive a response");

        assert_eq!(response.version(), hyper::Version::HTTP_2);
        assert_eq!(
            response.into_body().collect().await.unwrap().to_bytes(),
            Bytes::from_static(b"http2")
        );

        drop(sender);
        client.abort();
        server.abort();
    }
}
