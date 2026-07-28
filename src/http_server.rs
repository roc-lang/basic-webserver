//! Tokio/Hyper server lifecycle and the provided Roc application entrypoints.

use crate::abi::{
    roc_host, ServerConfig, ServerFileRoot, ServerHeader, ServerNativeFileRoute,
    ServerReadinessRoute, ServerRequest, ServerResponse as RocServerResponse, ServerShutdownReason,
};
use crate::compression::{
    apply_content_coding, encode_bytes, response_is_compressible, vary_on_accept_encoding,
    AcceptedEncodings, MAX_BUFFERED_COMPRESSION_BYTES,
};
use crate::file_server::{
    full_body, CachePolicy, Disposition, FilePlan, FileRootSpec, FileService, ServerBody,
    ServerResponse,
};
use crate::native_router::{
    FileRouteKind, FileRouteSpec, NativeMatch, NativeRouter, ReadinessRouteSpec,
};
use crate::readiness::ReadinessLease;
use crate::request_body::{register as register_body, PumpError};
use crate::request_parts::{request_target, RequestPartsBacking};
use crate::roc_platform_abi::*;
use crate::server_transport::{detect_protocol, Http1Activity, Http1Io, PrefixedStream, Protocol};
use crate::shutdown::{ActiveRequest, RequestTracker, ShutdownController, ShutdownReason};
use bytes::Bytes;
use futures::{Future, FutureExt, StreamExt};
use http_body_util::BodyExt;
#[cfg(test)]
use http_body_util::Full;
use hyper::body::{Body, Frame, SizeHint};
use hyper::header::CONTENT_LENGTH;
#[cfg(test)]
use hyper_util::rt::TokioExecutor;
use hyper_util::rt::TokioIo;
use std::convert::Infallible;
use std::net::SocketAddr;
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};
use tokio::task::{spawn_blocking, JoinSet};

const MAX_TRANSPORT_TIMEOUT_MS: u64 = 24 * 60 * 60 * 1000;

#[derive(Clone)]
struct RuntimeConfig {
    host: String,
    port: u16,
    max_connections: usize,
    max_handlers: usize,
    max_queued_handlers: usize,
    body_max_bytes: u64,
    body_chunk_bytes: usize,
    body_buffered_chunks: usize,
    header_timeout: Duration,
    body_idle_timeout: Duration,
    keep_alive_idle_timeout: Duration,
    handler_queue_timeout: Duration,
    response_idle_timeout: Duration,
    drain_timeout: Duration,
    hook_timeout: Duration,
    files: FileService,
    routes: NativeRouter,
}

impl RuntimeConfig {
    fn from_roc(config: ServerConfig) -> Result<Self, String> {
        let result = (|| {
            if config.body_chunk_bytes == 0 {
                return Err("request body chunk size must be non-zero".to_owned());
            }
            if config.body_buffered_chunks == 0 {
                return Err("request body buffered chunk count must be non-zero".to_owned());
            }
            if config.file_chunk_bytes > 1024 * 1024 {
                return Err("file transfer chunk size cannot exceed 1 MiB".to_owned());
            }
            let (max_connections, max_handlers) =
                validate_concurrency_limits(config.max_connections, config.max_handlers)?;
            let header_timeout =
                validate_transport_timeout("request head", config.header_timeout_ms)?;
            let body_idle_timeout =
                validate_transport_timeout("request body idle", config.body_idle_timeout_ms)?;
            let keep_alive_idle_timeout =
                validate_transport_timeout("keep-alive idle", config.keep_alive_idle_timeout_ms)?;
            let handler_queue_timeout =
                validate_transport_timeout("handler queue", config.handler_queue_timeout_ms)?;
            let response_idle_timeout =
                validate_transport_timeout("response idle", config.response_idle_timeout_ms)?;
            let roots = config
                .file_roots
                .as_slice()
                .iter()
                .map(file_root_from_roc)
                .collect::<Result<Vec<_>, _>>()?;
            let file_routes = config
                .native_file_routes
                .as_slice()
                .iter()
                .map(native_file_route_from_roc)
                .collect::<Result<Vec<_>, _>>()?;
            let liveness_routes = config
                .liveness_routes
                .as_slice()
                .iter()
                .map(|path| path.as_str().to_owned())
                .collect();
            let readiness_routes = config
                .readiness_routes
                .as_slice()
                .iter()
                .map(readiness_route_from_roc)
                .collect::<Result<Vec<_>, _>>()?;
            let files = FileService::activate(
                roots,
                config.file_max_concurrent as usize,
                config.file_chunk_bytes as usize,
            )?;
            let routes =
                NativeRouter::activate(&files, file_routes, liveness_routes, readiness_routes)?;
            Ok(Self {
                host: config.host.as_str().to_owned(),
                port: config.port,
                max_connections,
                max_handlers,
                max_queued_handlers: config.max_queued_handlers as usize,
                body_max_bytes: config.body_max_bytes,
                body_chunk_bytes: config.body_chunk_bytes as usize,
                body_buffered_chunks: config.body_buffered_chunks as usize,
                header_timeout,
                body_idle_timeout,
                keep_alive_idle_timeout,
                handler_queue_timeout,
                response_idle_timeout,
                drain_timeout: Duration::from_millis(config.drain_timeout_ms),
                hook_timeout: Duration::from_millis(config.hook_timeout_ms),
                files,
                routes,
            })
        })();
        // SAFETY: every Roc-owned field in the ABI config is borrowed only
        // inside the closure above and this consumes the one reference returned
        // by `init!` on both success and failure.
        unsafe { config.decref(roc_host()) };
        result
    }

    fn max_http2_streams_per_connection(&self) -> u32 {
        // The Roc configuration fields are u16, so their sum always fits u32.
        // A stream still passes through the global handler admission gate; the
        // HTTP/2 setting prevents one connection from creating substantially
        // more service futures than the complete active-plus-queued handler
        // budget. Two bounded extra streams let liveness and readiness enter
        // native routing while that handler budget is occupied.
        (self.max_handlers + self.max_queued_handlers + 2)
            .max(1)
            .try_into()
            .expect("validated handler capacity fits in u32")
    }
}

fn validate_transport_timeout(name: &str, milliseconds: u64) -> Result<Duration, String> {
    if milliseconds == 0 {
        return Err(format!("{name} timeout must be non-zero"));
    }
    if milliseconds > MAX_TRANSPORT_TIMEOUT_MS {
        return Err(format!(
            "{name} timeout cannot exceed {MAX_TRANSPORT_TIMEOUT_MS} milliseconds"
        ));
    }
    Ok(Duration::from_millis(milliseconds))
}

fn file_root_from_roc(root: &ServerFileRoot) -> Result<FileRootSpec, String> {
    let path = path_buf_from_file_root(root)?;
    Ok(FileRootSpec {
        id: root.id.as_str().to_owned(),
        path,
        cache: CachePolicy::from_abi(root.cache_tag, root.cache_max_age_seconds)?,
    })
}

fn path_buf_from_file_root(root: &ServerFileRoot) -> Result<PathBuf, String> {
    match root.path_tag {
        0 if root.path_unix_bytes.is_empty() && root.path_windows_u16s.is_empty() => {
            Ok(PathBuf::from(root.path_utf8.as_str()))
        }
        1 if root.path_utf8.is_empty() && root.path_windows_u16s.is_empty() => {
            #[cfg(unix)]
            {
                use std::os::unix::ffi::OsStringExt;
                Ok(PathBuf::from(std::ffi::OsString::from_vec(
                    root.path_unix_bytes.as_slice().to_vec(),
                )))
            }
            #[cfg(not(unix))]
            {
                Err("a Unix file-root path was supplied on a non-Unix target".to_owned())
            }
        }
        2 if root.path_utf8.is_empty() && root.path_unix_bytes.is_empty() => {
            #[cfg(windows)]
            {
                use std::os::windows::ffi::OsStringExt;
                Ok(PathBuf::from(std::ffi::OsString::from_wide(
                    root.path_windows_u16s.as_slice(),
                )))
            }
            #[cfg(not(windows))]
            {
                Err("a Windows file-root path was supplied on a non-Windows target".to_owned())
            }
        }
        _ => Err("malformed native file-root path".to_owned()),
    }
}

fn native_file_route_from_roc(route: &ServerNativeFileRoute) -> Result<FileRouteSpec, String> {
    let kind = match route.kind {
        0 => FileRouteKind::Prefix,
        1 => FileRouteKind::Exact,
        _ => return Err("invalid native route kind".to_owned()),
    };
    let cache = if route.cache_override {
        Some(CachePolicy::from_abi(
            route.cache_tag,
            route.cache_max_age_seconds,
        )?)
    } else if route.cache_tag == 0 && route.cache_max_age_seconds == 0 {
        None
    } else {
        return Err("malformed native route cache override".to_owned());
    };
    Ok(FileRouteSpec {
        at: route.at.as_str().to_owned(),
        root_id: route.root_id.as_str().to_owned(),
        kind,
        relative: route.relative.as_str().to_owned(),
        cache,
    })
}

fn readiness_route_from_roc(route: &ServerReadinessRoute) -> Result<ReadinessRouteSpec, String> {
    Ok(ReadinessRouteSpec {
        at: route.at.as_str().to_owned(),
        readiness: ReadinessLease::retain(route.readiness)?,
    })
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

    async fn admit(&self, wait_timeout: Duration) -> Result<ActiveHandler, AdmissionError> {
        if let Ok(active) = Arc::clone(&self.active).try_acquire_owned() {
            return Ok(ActiveHandler { _permit: active });
        }

        let queued = Arc::clone(&self.queued)
            .try_acquire_owned()
            .map_err(|_| AdmissionError::Full)?;
        let active = tokio::time::timeout(wait_timeout, Arc::clone(&self.active).acquire_owned())
            .await
            .map_err(|_| AdmissionError::TimedOut)?
            .expect("handler admission semaphore is never closed");
        drop(queued);
        Ok(ActiveHandler { _permit: active })
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AdmissionError {
    Full,
    TimedOut,
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
            eprintln!("Server startup configuration is invalid: {detail}");
            return finish_shutdown(
                ShutdownReason::StartupFailed(detail),
                raw_context,
                Duration::from_secs(10),
            );
        }
    };

    let roc_context = Arc::new(RocContext::new(raw_context));
    let shutdown = ShutdownController::new();
    let context = ServerContext {
        config: Arc::new(config.clone()),
        roc_context: Arc::clone(&roc_context),
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
    body_handle: *mut u64,
    body_limit: u64,
    declared_length: Option<u64>,
) -> ServerRequest {
    let roc_host = roc_host();
    let backing = match RequestPartsBacking::new(parts) {
        Ok(backing) => backing,
        Err(parts) => {
            return request_to_roc_copied(
                *parts,
                body_handle,
                body_limit,
                declared_length,
                roc_host,
            );
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
        body_handle,
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
    body_handle: *mut u64,
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
        body_handle,
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
    accepted_encodings: AcceptedEncodings,
) -> RocOutcome {
    let response = unsafe { roc_respond_for_host(request, context) };
    outcome_from_roc(response, accepted_encodings)
}

enum RocOutcome {
    Ordinary(ServerResponse, Option<i64>),
    File(FilePlan),
    Invalid(String),
}

fn outcome_from_roc(
    response: RocServerResponse,
    accepted_encodings: AcceptedEncodings,
) -> RocOutcome {
    match response.kind {
        0 => {
            let stop_code = response.stop.then_some(response.exit_code);
            RocOutcome::Ordinary(response_to_hyper(response, accepted_encodings), stop_code)
        }
        1 => {
            let root_id = response.file_root_id.as_str().to_owned();
            let relative = response.file_relative.as_str().to_owned();
            let disposition = match response.file_disposition {
                0 if response.file_download_name.is_empty() => Disposition::Inline,
                1 => Disposition::Attachment(response.file_download_name.as_str().to_owned()),
                _ => {
                    unsafe { response.decref(roc_host()) };
                    return RocOutcome::Invalid(
                        "Roc returned a malformed file disposition".to_owned(),
                    );
                }
            };
            let cache = if response.file_cache_override {
                match CachePolicy::from_abi(
                    response.file_cache_tag,
                    response.file_cache_max_age_seconds,
                ) {
                    Ok(cache) => Some(cache),
                    Err(detail) => {
                        unsafe { response.decref(roc_host()) };
                        return RocOutcome::Invalid(detail);
                    }
                }
            } else if response.file_cache_tag == 0 && response.file_cache_max_age_seconds == 0 {
                None
            } else {
                unsafe { response.decref(roc_host()) };
                return RocOutcome::Invalid(
                    "Roc returned a malformed file cache override".to_owned(),
                );
            };
            let valid = !response.stop
                && response.status == 500
                && response.body.is_empty()
                && response.headers.is_empty();
            unsafe { response.decref(roc_host()) };
            if !valid {
                return RocOutcome::Invalid(
                    "Roc returned a malformed file response plan".to_owned(),
                );
            }
            RocOutcome::File(FilePlan::authorized(root_id, relative, disposition, cache))
        }
        _ => {
            unsafe { response.decref(roc_host()) };
            RocOutcome::Invalid("Roc returned an unknown response-plan kind".to_owned())
        }
    }
}

fn response_to_hyper(
    response: RocServerResponse,
    accepted_encodings: AcceptedEncodings,
) -> ServerResponse {
    crate::request_body::validate_response_body(&response.body);
    let mut builder = hyper::Response::builder().status(response.status);
    for header in response.headers.as_slice() {
        builder = builder.header(header.name.as_str(), header.value.as_str());
    }
    let head = match builder.body(()) {
        Ok(head) => head,
        Err(_) => {
            unsafe { response.decref(roc_host()) };
            return internal_server_error("Failed to build response");
        }
    };
    let (mut parts, ()) = head.into_parts();
    let body_length = response.body.len();
    if body_length <= MAX_BUFFERED_COMPRESSION_BYTES
        && response_is_compressible(parts.status, &parts.headers, body_length as u64)
    {
        vary_on_accept_encoding(&mut parts.headers);
        if let Some(coding) = accepted_encodings.preferred() {
            if let Ok(encoded) = encode_bytes(coding, response.body.as_slice()) {
                if encoded.len() < body_length {
                    apply_content_coding(&mut parts.headers, coding, Some(encoded.len()));
                    unsafe { response.decref(roc_host()) };
                    return hyper::Response::from_parts(parts, full_body(Bytes::from(encoded)));
                }
            }
        }
    }
    let body = Bytes::from_owner(RocResponseOwner { response });
    hyper::Response::from_parts(parts, full_body(body))
}

/// Owns every Roc reference in a response while Hyper may still transmit the
/// body. This is intentionally the whole response rather than just its body:
/// generated recursive decref remains the single source of truth, and keeping
/// the small header descriptors alive until body completion is bounded.
struct RocResponseOwner {
    response: RocServerResponse,
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

fn internal_server_error(message: &str) -> ServerResponse {
    hyper::Response::builder()
        .status(hyper::StatusCode::INTERNAL_SERVER_ERROR)
        .body(full_body(Bytes::copy_from_slice(message.as_bytes())))
        .expect("static 500 response is valid")
}

fn service_unavailable() -> ServerResponse {
    hyper::Response::builder()
        .status(hyper::StatusCode::SERVICE_UNAVAILABLE)
        .body(full_body(Bytes::from_static(b"Server is shutting down")))
        .expect("static 503 response is valid")
}

fn overloaded() -> ServerResponse {
    hyper::Response::builder()
        .status(hyper::StatusCode::SERVICE_UNAVAILABLE)
        .body(full_body(Bytes::from_static(b"Server is overloaded")))
        .expect("static 503 response is valid")
}

fn handler_queue_timed_out() -> ServerResponse {
    hyper::Response::builder()
        .status(hyper::StatusCode::SERVICE_UNAVAILABLE)
        .body(full_body(Bytes::from_static(
            b"Server handler queue wait timed out",
        )))
        .expect("static 503 response is valid")
}

fn invalid_request_headers() -> ServerResponse {
    hyper::Response::builder()
        .status(hyper::StatusCode::BAD_REQUEST)
        .body(full_body(Bytes::from_static(
            b"Request header values must be valid UTF-8",
        )))
        .expect("static 400 response is valid")
}

fn payload_too_large(limit: u64) -> ServerResponse {
    hyper::Response::builder()
        .status(hyper::StatusCode::PAYLOAD_TOO_LARGE)
        .body(full_body(Bytes::from(format!(
            "Request body exceeds the {limit}-byte limit"
        ))))
        .expect("static 413 response is valid")
}

type RequestBodyStream =
    Pin<Box<dyn futures::Stream<Item = Result<Bytes, PumpError>> + Send + 'static>>;

struct TrackedResponseBody {
    inner: ServerBody,
    active_request: Option<Arc<ActiveRequest>>,
    http1_activity: Option<Http1Activity>,
    body_idle_timeout: Option<Duration>,
    body_sleep: Option<Pin<Box<tokio::time::Sleep>>>,
    body_waiting: bool,
}

impl TrackedResponseBody {
    fn body_finished(&mut self) {
        if let Some(activity) = self.http1_activity.take() {
            activity.response_body_finished();
        }
    }

    fn finish(&mut self) {
        self.body_finished();
        self.active_request.take();
    }

    fn body_progress(&mut self) {
        self.body_waiting = false;
    }

    fn pending_body(
        &mut self,
        context: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Bytes>, std::io::Error>>> {
        let Some(timeout) = self.body_idle_timeout else {
            return Poll::Pending;
        };
        let sleep = self
            .body_sleep
            .as_mut()
            .expect("an HTTP/1 body timeout has a timer");
        if !self.body_waiting {
            self.body_waiting = true;
            sleep.as_mut().reset(tokio::time::Instant::now() + timeout);
        }
        if sleep.as_mut().poll(context).is_pending() {
            return Poll::Pending;
        }

        self.finish();
        Poll::Ready(Some(Err(std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            "response body made no progress before its deadline",
        ))))
    }
}

impl Body for TrackedResponseBody {
    type Data = Bytes;
    type Error = std::io::Error;

    fn poll_frame(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        let this = self.get_mut();
        match Pin::new(&mut this.inner).poll_frame(context) {
            Poll::Ready(None) => {
                this.finish();
                Poll::Ready(None)
            }
            Poll::Ready(Some(Err(error))) => {
                this.finish();
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(Some(Ok(frame))) => {
                let made_progress = frame.data_ref().is_some_and(|data| !data.is_empty())
                    || frame.trailers_ref().is_some();
                if made_progress {
                    this.body_progress();
                }
                if this.inner.is_end_stream() {
                    // Hyper may flush the final frame without polling the body
                    // again. Publish completion while that flush is still
                    // guaranteed to happen after this point.
                    this.body_finished();
                }
                Poll::Ready(Some(Ok(frame)))
            }
            Poll::Pending => this.pending_body(context),
        }
    }

    fn is_end_stream(&self) -> bool {
        self.inner.is_end_stream()
    }

    fn size_hint(&self) -> SizeHint {
        self.inner.size_hint()
    }
}

impl Drop for TrackedResponseBody {
    fn drop(&mut self) {
        self.finish();
    }
}

fn track_response(
    response: ServerResponse,
    active_request: Option<Arc<ActiveRequest>>,
    http1_activity: Option<Http1Activity>,
    body_idle_timeout: Option<Duration>,
) -> ServerResponse {
    response.map(|inner| {
        let mut http1_activity = http1_activity;
        if inner.is_end_stream() {
            if let Some(activity) = http1_activity.take() {
                activity.response_body_finished();
            }
        }
        TrackedResponseBody {
            inner,
            active_request,
            http1_activity,
            body_idle_timeout,
            body_sleep: body_idle_timeout.map(|timeout| Box::pin(tokio::time::sleep(timeout))),
            body_waiting: false,
        }
        .boxed_unsync()
    })
}

async fn handle_req(
    parts: hyper::http::request::Parts,
    body: RequestBodyStream,
    context: ServerContext,
    http1_activity: Option<Http1Activity>,
) -> ServerResponse {
    let body_idle_timeout = http1_activity
        .as_ref()
        .map(|_| context.config.response_idle_timeout);
    let active_request = match context.requests.begin() {
        Some(active) => Arc::new(active),
        None => {
            return track_response(
                service_unavailable(),
                None,
                http1_activity,
                body_idle_timeout,
            )
        }
    };

    let response = if let Some(native) =
        context.config.routes.route(parts.uri.path(), &parts.method)
    {
        drop(body);
        match native {
            NativeMatch::File(plan) => {
                context
                    .config
                    .files
                    .serve(
                        plan,
                        parts.method,
                        parts.headers,
                        Arc::clone(&active_request),
                    )
                    .await
            }
            NativeMatch::Probe(response) => response,
        }
    } else if !request_headers_are_utf8(&parts.headers) {
        drop(body);
        invalid_request_headers()
    } else {
        let declared_length = content_length(&parts.headers);
        if declared_length.is_some_and(|length| length > context.config.body_max_bytes) {
            drop(body);
            payload_too_large(context.config.body_max_bytes)
        } else {
            let accepted_encodings = AcceptedEncodings::from_headers(&parts.headers);
            let file_method = parts.method.clone();
            let file_headers = parts.headers.clone();
            let registration = register_body(
                context.config.body_max_bytes,
                context.config.body_buffered_chunks,
                declared_length,
                roc_host(),
            );
            let body_handle = registration.handle;
            let body_pump = registration.pump;
            let chunk_bytes = context.config.body_chunk_bytes;
            let body_idle_timeout = context.config.body_idle_timeout;
            tokio::spawn(async move { body_pump.run(body, chunk_bytes, body_idle_timeout).await });

            match context
                .handlers
                .admit(context.config.handler_queue_timeout)
                .await
            {
                Err(AdmissionError::Full) => overloaded(),
                Err(AdmissionError::TimedOut) => handler_queue_timed_out(),
                Ok(active_handler) => {
                    let body_limit = context.config.body_max_bytes;
                    let roc_context = Arc::clone(&context.roc_context);
                    let handler_request = Arc::clone(&active_request);
                    let handled = spawn_blocking(move || {
                        // These guards intentionally live in the non-cancellable
                        // blocking task. Aborting its Tokio JoinHandle must not
                        // make shutdown believe Roc has stopped using its slot,
                        // body, or immutable application context.
                        let _active_request = handler_request;
                        let _active_handler = active_handler;
                        let roc_request = request_to_roc(
                            parts,
                            body_handle.retain_for_roc(),
                            body_limit,
                            declared_length,
                        );
                        let request_context = roc_context.retain_for_request();
                        let result = call_roc(roc_request, request_context, accepted_encodings);
                        body_handle.expire();
                        result
                    })
                    .await;

                    match handled {
                        Ok(RocOutcome::Ordinary(response, Some(exit_code))) => {
                            context
                                .shutdown
                                .request(ShutdownReason::ApplicationRequested { exit_code });
                            response
                        }
                        Ok(RocOutcome::Ordinary(response, None)) => response,
                        Ok(RocOutcome::File(plan)) => {
                            context
                                .config
                                .files
                                .serve(plan, file_method, file_headers, Arc::clone(&active_request))
                                .await
                        }
                        Ok(RocOutcome::Invalid(detail)) => {
                            eprintln!("Invalid Roc response plan: {detail}");
                            internal_server_error("500 Internal Server Error")
                        }
                        Err(error) => {
                            eprintln!("Recovered from calling Roc: {error:?}");
                            internal_server_error("500 Internal Server Error")
                        }
                    }
                }
            }
        }
    };

    track_response(
        response,
        Some(active_request),
        http1_activity,
        body_idle_timeout,
    )
}

async fn handle_panics(
    future: impl Future<Output = ServerResponse>,
    http1_activity: Option<Http1Activity>,
    body_idle_timeout: Option<Duration>,
) -> Result<ServerResponse, Infallible> {
    match AssertUnwindSafe(future).catch_unwind().await {
        Ok(response) => Ok(response),
        Err(_) => Ok(track_response(
            internal_server_error("Panic detected"),
            None,
            http1_activity,
            body_idle_timeout,
        )),
    }
}

async fn serve_http1(stream: PrefixedStream, context: ServerContext) {
    let activity = Http1Activity::new();
    let io = TokioIo::new(Http1Io::new(
        stream,
        activity.clone(),
        context.config.header_timeout,
        context.config.keep_alive_idle_timeout,
        context.config.response_idle_timeout,
    ));
    let service_context = context.clone();
    let service_activity = activity.clone();
    let connection = hyper::server::conn::http1::Builder::new().serve_connection(
        io,
        hyper::service::service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
            service_activity.request_started();
            let (parts, body) = request.into_parts();
            let stream = body
                .into_data_stream()
                .map(|frame| frame.map_err(request_body_error));
            handle_panics(
                handle_req(
                    parts,
                    Box::pin(stream),
                    service_context.clone(),
                    Some(service_activity.clone()),
                ),
                Some(service_activity.clone()),
                Some(service_context.config.response_idle_timeout),
            )
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

fn h2_request_body(mut body: h2::RecvStream) -> RequestBodyStream {
    Box::pin(futures::stream::poll_fn(move |context| {
        match body.poll_data(context) {
            Poll::Ready(Some(Ok(bytes))) => {
                if let Err(error) = body.flow_control().release_capacity(bytes.len()) {
                    Poll::Ready(Some(Err(PumpError::InvalidBody(error.to_string()))))
                } else {
                    Poll::Ready(Some(Ok(bytes)))
                }
            }
            Poll::Ready(Some(Err(error))) if error.is_reset() => {
                Poll::Ready(Some(Err(PumpError::ClientDisconnected)))
            }
            Poll::Ready(Some(Err(error))) => {
                Poll::Ready(Some(Err(PumpError::InvalidBody(error.to_string()))))
            }
            Poll::Ready(None) => Poll::Ready(None),
            Poll::Pending => Poll::Pending,
        }
    }))
}

async fn send_h2_response(
    mut responder: h2::server::SendResponse<Bytes>,
    response: ServerResponse,
    idle_timeout: Duration,
) -> Result<(), String> {
    let (parts, mut body) = response.into_parts();
    let end_stream = body.is_end_stream();
    let mut sender = responder
        .send_response(hyper::Response::from_parts(parts, ()), end_stream)
        .map_err(|error| error.to_string())?;
    if end_stream {
        return Ok(());
    }

    let mut deadline = tokio::time::Instant::now() + idle_timeout;
    loop {
        let frame = match tokio::time::timeout_at(deadline, body.frame()).await {
            Ok(frame) => frame,
            Err(_) => {
                sender.send_reset(h2::Reason::CANCEL);
                return Err("HTTP/2 response made no progress before its deadline".to_owned());
            }
        };
        match frame {
            Some(Ok(frame)) if frame.is_data() => {
                let mut data = frame
                    .into_data()
                    .expect("a data frame contains a data buffer");
                if data.is_empty() {
                    continue;
                }
                while !data.is_empty() {
                    sender.reserve_capacity(data.len());
                    let capacity = match tokio::time::timeout_at(
                        deadline,
                        futures::future::poll_fn(|context| sender.poll_capacity(context)),
                    )
                    .await
                    {
                        Ok(Some(Ok(capacity))) if capacity > 0 => capacity,
                        Ok(Some(Ok(_))) => continue,
                        Ok(Some(Err(error))) => return Err(error.to_string()),
                        Ok(None) => return Err("HTTP/2 response stream closed".to_owned()),
                        Err(_) => {
                            sender.send_reset(h2::Reason::CANCEL);
                            return Err(
                                "HTTP/2 response flow control made no progress before its deadline"
                                    .to_owned(),
                            );
                        }
                    };
                    let count = capacity.min(data.len());
                    let chunk = data.split_to(count);
                    let end_stream = data.is_empty() && body.is_end_stream();
                    sender
                        .send_data(chunk, end_stream)
                        .map_err(|error| error.to_string())?;
                    deadline = tokio::time::Instant::now() + idle_timeout;
                    if end_stream {
                        return Ok(());
                    }
                }
            }
            Some(Ok(frame)) if frame.is_trailers() => {
                sender
                    .send_trailers(
                        frame
                            .into_trailers()
                            .expect("a trailers frame contains headers"),
                    )
                    .map_err(|error| error.to_string())?;
                return Ok(());
            }
            Some(Ok(_)) => {}
            Some(Err(error)) => {
                sender.send_reset(h2::Reason::INTERNAL_ERROR);
                return Err(error.to_string());
            }
            None => {
                sender
                    .send_data(Bytes::new(), true)
                    .map_err(|error| error.to_string())?;
                return Ok(());
            }
        }
    }
}

fn spawn_h2_request(
    tasks: &mut JoinSet<()>,
    request: hyper::Request<h2::RecvStream>,
    responder: h2::server::SendResponse<Bytes>,
    context: ServerContext,
) {
    tasks.spawn(async move {
        let (parts, body) = request.into_parts();
        let response = handle_panics(
            handle_req(parts, h2_request_body(body), context.clone(), None),
            None,
            None,
        )
        .await
        .expect("request panic conversion is infallible");
        if let Err(error) =
            send_h2_response(responder, response, context.config.response_idle_timeout).await
        {
            eprintln!("Error serving HTTP/2 response stream: {error}");
        }
    });
}

async fn serve_http2(stream: PrefixedStream, context: ServerContext) {
    let mut builder = h2::server::Builder::new();
    builder
        .max_concurrent_streams(context.config.max_http2_streams_per_connection())
        // The response sender reserves exact flow-control capacity before
        // handing bytes to h2; one 64 KiB flow-control grant is sufficient.
        .max_send_buffer_size(64 * 1024);
    let handshake = builder.handshake::<_, Bytes>(stream);
    let mut connection = match tokio::time::timeout(context.config.header_timeout, handshake).await
    {
        Ok(Ok(connection)) => connection,
        Ok(Err(error)) => {
            eprintln!("Error establishing HTTP/2 connection: {error}");
            return;
        }
        Err(_) => {
            eprintln!("HTTP/2 preface timed out");
            return;
        }
    };
    let mut tasks = JoinSet::new();
    let mut accepted_any = false;
    let mut draining = false;

    loop {
        if tasks.is_empty() && !draining {
            let idle_timeout = if accepted_any {
                context.config.keep_alive_idle_timeout
            } else {
                context.config.header_timeout
            };
            tokio::select! {
                _ = context.shutdown.requested() => {
                    draining = true;
                    connection.graceful_shutdown();
                }
                accepted = tokio::time::timeout(idle_timeout, connection.accept()) => {
                    match accepted {
                        Err(_) => return,
                        Ok(Some(Ok((request, responder)))) => {
                            accepted_any = true;
                            spawn_h2_request(&mut tasks, request, responder, context.clone());
                        }
                        Ok(Some(Err(error))) => {
                            eprintln!("Error accepting HTTP/2 stream: {error}");
                            return;
                        }
                        Ok(None) => return,
                    }
                }
            }
            continue;
        }

        tokio::select! {
            _ = context.shutdown.requested(), if !draining => {
                draining = true;
                connection.graceful_shutdown();
            }
            completed = tasks.join_next(), if !tasks.is_empty() => {
                if let Some(Err(error)) = completed {
                    eprintln!("HTTP/2 stream task failed: {error:?}");
                }
            }
            accepted = connection.accept() => {
                match accepted {
                    Some(Ok((request, responder))) if !draining => {
                        accepted_any = true;
                        spawn_h2_request(&mut tasks, request, responder, context.clone());
                    }
                    Some(Ok((_request, mut responder))) => {
                        responder.send_reset(h2::Reason::REFUSED_STREAM);
                    }
                    Some(Err(error)) => {
                        eprintln!("Error accepting HTTP/2 stream: {error}");
                        return;
                    }
                    None => return,
                }
            }
        }
    }
}

async fn serve_connection(stream: tokio::net::TcpStream, context: ServerContext) {
    match detect_protocol(stream, context.config.header_timeout).await {
        Ok((Protocol::Http1, stream)) => serve_http1(stream, context).await,
        Ok((Protocol::Http2, stream)) => serve_http2(stream, context).await,
        Err(error)
            if matches!(
                error.kind(),
                std::io::ErrorKind::UnexpectedEof | std::io::ErrorKind::ConnectionReset
            ) => {}
        Err(error) => eprintln!("Error detecting HTTP protocol: {error}"),
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

    context.config.routes.begin_draining();
    context.requests.begin_draining();
    let drained = tokio::time::timeout(context.config.drain_timeout, async {
        context.requests.wait_for_idle().await;
        while connections.join_next().await.is_some() {}
    })
    .await;

    if drained.is_err() {
        connections.abort_all();
        eprintln!(
            "Graceful drain exceeded {:?}; connections were aborted; forcing process exit without running the Roc shutdown hook",
            context.config.drain_timeout
        );

        // spawn_blocking Roc handlers cannot be safely preempted. Running the
        // shutdown hook or dropping the context while one may still use it
        // would be unsound, so the configured drain deadline is a hard process
        // deadline and intentionally skips application shutdown cleanup.
        std::process::exit(1);
    }

    debug_assert_eq!(
        context.config.files.active_transfers(),
        0,
        "all native file transfers must drain before shutdown"
    );
    if context.config.files.high_water_transfers() > 0 {
        eprintln!(
            "Native file transfer high-water mark: {}",
            context.config.files.high_water_transfers()
        );
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
    use std::io::Read;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn initialize_test_host() {
        crate::abi::initialize_test_roc_host();
    }

    fn no_compression() -> AcceptedEncodings {
        AcceptedEncodings::from_headers(&hyper::HeaderMap::new())
    }

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
        initialize_test_host();

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

        let roc_request = request_to_roc(parts, core::ptr::null_mut(), 4096, None);
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

        let roc_response = RocServerResponse {
            exit_code: 0,
            body: escaped_body,
            file_download_name: RocStr::empty(),
            file_relative: RocStr::empty(),
            file_root_id: RocStr::empty(),
            headers: RocList::empty(),
            file_cache_max_age_seconds: 0,
            status: 200,
            file_cache_override: false,
            file_cache_tag: 0,
            file_disposition: 0,
            kind: 0,
            stop: false,
        };
        let response = response_to_hyper(roc_response, no_compression());
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

    struct DropOwner {
        bytes: &'static [u8],
        drops: Arc<AtomicUsize>,
    }

    impl AsRef<[u8]> for DropOwner {
        fn as_ref(&self) -> &[u8] {
            self.bytes
        }
    }

    impl Drop for DropOwner {
        fn drop(&mut self) {
            self.drops.fetch_add(1, Ordering::AcqRel);
        }
    }

    #[tokio::test]
    async fn seamless_request_chunk_escapes_until_hyper_finishes_the_response() {
        initialize_test_host();
        let drops = Arc::new(AtomicUsize::new(0));
        let bytes = Bytes::from_owner(DropOwner {
            bytes: b"escaped body chunk",
            drops: Arc::clone(&drops),
        });
        let original_ptr = bytes.as_ptr();
        let response = RocServerResponse {
            exit_code: 0,
            body: crate::request_body::seamless_chunk_for_test(bytes),
            file_download_name: RocStr::empty(),
            file_relative: RocStr::empty(),
            file_root_id: RocStr::empty(),
            headers: RocList::empty(),
            file_cache_max_age_seconds: 0,
            status: 200,
            file_cache_override: false,
            file_cache_tag: 0,
            file_disposition: 0,
            kind: 0,
            stop: false,
        };

        let response = response_to_hyper(response, no_compression());
        assert_eq!(drops.load(Ordering::Acquire), 0);
        let transmitted = response.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(transmitted.as_ptr(), original_ptr);
        assert_eq!(transmitted.as_ref(), b"escaped body chunk");
        assert_eq!(drops.load(Ordering::Acquire), 0);
        drop(transmitted);
        assert_eq!(drops.load(Ordering::Acquire), 1);
    }

    #[tokio::test]
    async fn ordinary_responses_negotiate_zstandard_inside_the_handler_domain() {
        initialize_test_host();
        let original = b"compressible ordinary response ".repeat(256);
        let response = RocServerResponse {
            exit_code: 0,
            body: unsafe { RocListWith::<u8, false>::from_slice(&original, roc_host()) },
            file_download_name: RocStr::empty(),
            file_relative: RocStr::empty(),
            file_root_id: RocStr::empty(),
            headers: RocList::empty(),
            file_cache_max_age_seconds: 0,
            status: 200,
            file_cache_override: false,
            file_cache_tag: 0,
            file_disposition: 0,
            kind: 0,
            stop: false,
        };
        let mut request_headers = hyper::HeaderMap::new();
        request_headers.insert(
            hyper::header::ACCEPT_ENCODING,
            "gzip, br, zstd".parse().unwrap(),
        );

        let response =
            response_to_hyper(response, AcceptedEncodings::from_headers(&request_headers));
        assert_eq!(response.headers()[hyper::header::CONTENT_ENCODING], "zstd");
        assert_eq!(response.headers()[hyper::header::VARY], "Accept-Encoding");
        let encoded = response.into_body().collect().await.unwrap().to_bytes();
        let mut decoded = Vec::new();
        zstd::stream::read::Decoder::new(encoded.as_ref())
            .unwrap()
            .read_to_end(&mut decoded)
            .unwrap();
        assert_eq!(decoded, original);
    }

    #[tokio::test]
    async fn stalled_http1_body_times_out_and_releases_request_accounting() {
        let requests = RequestTracker::new();
        let active_request = Arc::new(requests.begin().expect("request should be admitted"));
        let pending_frames = futures::stream::pending::<Result<Frame<Bytes>, std::io::Error>>();
        let response = track_response(
            hyper::Response::new(http_body_util::StreamBody::new(pending_frames).boxed_unsync()),
            Some(active_request),
            Some(Http1Activity::new()),
            Some(Duration::from_millis(20)),
        );

        let error = response
            .into_body()
            .frame()
            .await
            .expect("timed-out bodies report an error frame")
            .expect_err("a stalled body must not complete successfully");
        assert_eq!(error.kind(), std::io::ErrorKind::TimedOut);
        assert_eq!(
            requests.active(),
            0,
            "timing out a response must release shutdown accounting"
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

    #[test]
    fn transport_timeout_bounds_are_explicit() {
        assert!(validate_transport_timeout("test", 0).is_err());
        assert_eq!(
            validate_transport_timeout("test", 1),
            Ok(Duration::from_millis(1))
        );
        assert_eq!(
            validate_transport_timeout("test", MAX_TRANSPORT_TIMEOUT_MS),
            Ok(Duration::from_millis(MAX_TRANSPORT_TIMEOUT_MS))
        );
        assert!(validate_transport_timeout("test", MAX_TRANSPORT_TIMEOUT_MS + 1).is_err());
    }

    #[tokio::test]
    async fn handler_admission_bounds_active_and_queued_work() {
        let admission = HandlerAdmission::new(1, 1);
        let wait = Duration::from_secs(1);
        let first = admission.admit(wait).await.unwrap();

        let waiting = {
            let admission = admission.clone();
            tokio::spawn(async move { admission.admit(wait).await })
        };
        tokio::time::timeout(Duration::from_secs(1), async {
            while admission.queued.available_permits() != 0 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("second handler did not enter the bounded queue");
        assert_eq!(admission.queued.available_permits(), 0);
        assert_eq!(
            admission.admit(wait).await.err(),
            Some(AdmissionError::Full),
            "work beyond the active and queued limits must be rejected",
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
        let wait = Duration::from_secs(1);
        let active = admission.admit(wait).await.unwrap();
        assert_eq!(
            admission.admit(wait).await.err(),
            Some(AdmissionError::Full)
        );
        drop(active);
        assert!(admission.admit(wait).await.is_ok());
    }

    #[tokio::test]
    async fn expired_handler_queue_wait_releases_its_slot_without_dispatch() {
        let admission = HandlerAdmission::new(1, 1);
        let active = admission.admit(Duration::from_secs(1)).await.unwrap();

        assert_eq!(
            admission.admit(Duration::from_millis(20)).await.err(),
            Some(AdmissionError::TimedOut)
        );
        assert_eq!(admission.queued.available_permits(), 1);
        assert_eq!(admission.active.available_permits(), 0);

        drop(active);
        assert!(admission.admit(Duration::from_secs(1)).await.is_ok());
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
    fn http2_stream_limit_reserves_bounded_native_probe_headroom() {
        let files = FileService::activate(Vec::new(), 1, 1024).unwrap();
        let routes = NativeRouter::activate(&files, Vec::new(), Vec::new(), Vec::new()).unwrap();
        let config = RuntimeConfig {
            host: "127.0.0.1".to_owned(),
            port: 8000,
            max_connections: 256,
            max_handlers: 32,
            max_queued_handlers: 64,
            body_max_bytes: 1024,
            body_chunk_bytes: 1024,
            body_buffered_chunks: 1,
            header_timeout: Duration::from_secs(10),
            body_idle_timeout: Duration::from_secs(30),
            keep_alive_idle_timeout: Duration::from_secs(60),
            handler_queue_timeout: Duration::from_secs(5),
            response_idle_timeout: Duration::from_secs(30),
            drain_timeout: Duration::from_secs(30),
            hook_timeout: Duration::from_secs(10),
            files,
            routes,
        };
        assert_eq!(config.max_http2_streams_per_connection(), 98);
    }

    #[tokio::test]
    async fn stalled_http2_response_resets_only_its_stream() {
        let (client_io, server_io) = tokio::io::duplex(4096);
        let server = tokio::spawn(async move {
            let mut connection = h2::server::handshake(server_io)
                .await
                .expect("HTTP/2 server handshake should succeed");
            let (_, stalled_responder) = connection
                .accept()
                .await
                .expect("client should open the stalled stream")
                .expect("stalled request should be valid");
            let (_, healthy_responder) = connection
                .accept()
                .await
                .expect("client should open the healthy stream")
                .expect("healthy request should be valid");

            let mut responses = JoinSet::new();
            responses.spawn(async move {
                (
                    "stalled",
                    send_h2_response(
                        stalled_responder,
                        hyper::Response::new(full_body(Bytes::from_static(b"stalled"))),
                        Duration::from_millis(30),
                    )
                    .await,
                )
            });
            responses.spawn(async move {
                (
                    "healthy",
                    send_h2_response(
                        healthy_responder,
                        hyper::Response::new(full_body(Bytes::from_static(b"healthy"))),
                        Duration::from_millis(30),
                    )
                    .await,
                )
            });

            let mut results = Vec::new();
            while results.len() < 2 {
                tokio::select! {
                    result = responses.join_next() => {
                        results.push(
                            result
                                .expect("a response task should still be active")
                                .expect("response task should not panic"),
                        );
                    }
                    accepted = connection.accept() => {
                        assert!(
                            accepted.is_some(),
                            "client connection should remain open while responses are active"
                        );
                    }
                }
            }
            // Drive the connection once more so the stream reset queued by
            // the timed-out sender reaches the peer before this test server
            // drops the connection.
            let _ = tokio::time::timeout(Duration::from_millis(10), connection.accept()).await;
            results
        });

        let mut builder = h2::client::Builder::new();
        builder.initial_window_size(1);
        let (mut sender, connection) = builder
            .handshake::<_, Bytes>(client_io)
            .await
            .expect("HTTP/2 client handshake should succeed");
        let client = tokio::spawn(connection);

        sender = sender.ready().await.expect("client should become ready");
        let (stalled_response, _) = sender
            .send_request(hyper::Request::new(()), true)
            .expect("stalled request should be accepted");
        sender = sender.ready().await.expect("client should remain ready");
        let (healthy_response, _) = sender
            .send_request(hyper::Request::new(()), true)
            .expect("healthy request should be accepted");

        let mut stalled_body = stalled_response
            .await
            .expect("stalled stream should receive response headers")
            .into_body();
        let mut healthy_body = healthy_response
            .await
            .expect("healthy stream should receive a response")
            .into_body();
        let mut healthy_bytes = Vec::new();
        while let Some(data) = healthy_body.data().await {
            let data = data.expect("healthy stream should not be reset");
            healthy_bytes.extend_from_slice(&data);
            healthy_body
                .flow_control()
                .release_capacity(data.len())
                .expect("healthy flow-control capacity should be released");
        }
        assert_eq!(healthy_bytes, b"healthy");

        let results = server.await.expect("server task should not panic");
        assert!(results
            .iter()
            .any(|(name, result)| *name == "healthy" && result.is_ok()));
        assert!(results
            .iter()
            .any(|(name, result)| *name == "stalled" && result.is_err()));

        let mut reset_reason = None;
        while let Some(data) = stalled_body.data().await {
            match data {
                Ok(_) => {}
                Err(error) => {
                    reset_reason = error.reason();
                    break;
                }
            }
        }
        assert_eq!(reset_reason, Some(h2::Reason::CANCEL));

        drop(sender);
        client.abort();
    }

    #[tokio::test]
    async fn auto_server_accepts_an_http2_prior_knowledge_request() {
        let (client_io, server_io) = tokio::io::duplex(4096);
        let server = tokio::spawn(async move {
            let mut connection = h2::server::handshake(server_io)
                .await
                .expect("HTTP/2 server handshake should succeed");
            let (request, mut responder) = connection
                .accept()
                .await
                .expect("client should open one stream")
                .expect("HTTP/2 request should be valid");
            assert_eq!(request.version(), hyper::Version::HTTP_2);
            let mut sender = responder
                .send_response(hyper::Response::new(()), false)
                .expect("response headers should be accepted");
            sender
                .send_data(Bytes::from_static(b"http2"), true)
                .expect("response body should be accepted");
            while connection.accept().await.is_some() {}
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
