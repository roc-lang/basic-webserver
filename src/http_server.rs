//! Tokio/Hyper server lifecycle and the provided Roc application entrypoints.

use crate::abi::{
    roc_host, ServerConfig, ServerFileResponse, ServerFileRoot, ServerHeader,
    ServerNativeFileRoute, ServerOrdinaryResponse, ServerReadinessRoute, ServerRequest,
    ServerResponse as RocServerResponse, ServerResponseTag, ServerShutdownReason,
    ServerWritableRoot,
};
use crate::body_sink::{BodySinkService, WritableRootSpec};
use crate::brotli_executor::{BrotliExecutor, BrotliLane, BrotliProfile};
use crate::compression::{
    apply_content_coding, encode_bytes, response_is_compressible, vary_on_accept_encoding,
    AcceptedEncodings, StreamingContentCoding, MAX_BUFFERED_COMPRESSION_BYTES,
};
use crate::file_server::{
    CachePolicy, Disposition, FilePlan, FileRootSpec, FileServeFailure, FileService,
};
use crate::native_router::{
    FileRouteKind, FileRouteSpec, NativeMatch, NativeRouter, ReadinessRouteSpec,
};
use crate::readiness::ReadinessLease;
use crate::request_body::{register as register_body, PumpError};
use crate::request_limits::{
    RequestMetadataLimits, RequestMetadataRejection, HTTP1_MAX_HEAD_BYTES,
};
use crate::request_parts::RequestPartsBacking;
use crate::request_target::{RequestMetadata, TargetKind};
use crate::response::{
    application_parts, finalize_response, full_body, safe_internal_server_error, RequestSemantics,
    ServerBody, ServerData, ServerResponse,
};
use crate::response_body::{SseBody, SseCompression, SseItem, SseItemSource, SseSourcePoll};
use crate::roc_executor::{
    AdmissionClass, FixedExecutor, FixedExecutorHandle, QueueTicket, SubmitError,
};
use crate::roc_platform_abi::*;
use crate::server_transport::{detect_protocol, Http1Activity, Http1Io, PrefixedStream, Protocol};
use crate::shutdown::{ActiveRequest, RequestTracker, ShutdownController, ShutdownReason};
use crate::telemetry::{
    AccessLogConfig, ActiveGaugeGuard, Destination, LogTarget, Metrics, RejectionReason, Telemetry,
    TelemetryConfig, TelemetryHandle,
};
use bytes::{Buf, Bytes};
use futures::task::AtomicWaker;
use futures::{Future, FutureExt, StreamExt};
use http_body_util::BodyExt;
#[cfg(test)]
use http_body_util::Full;
use hyper::body::{Body, Frame, SizeHint};
use hyper::header::{CACHE_CONTROL, CONTENT_LENGTH, CONTENT_TYPE};
#[cfg(test)]
use hyper_util::rt::TokioExecutor;
use hyper_util::rt::TokioIo;
use std::convert::Infallible;
use std::io;
use std::mem::MaybeUninit;
use std::net::SocketAddr;
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use std::time::{Duration, Instant};
use tokio::sync::{oneshot, OwnedSemaphorePermit, Semaphore};
use tokio::task::JoinSet;

const MAX_TRANSPORT_TIMEOUT_MS: u64 = 24 * 60 * 60 * 1000;
const MAX_SSE_EVENT_BYTES: usize = 16 * 1024 * 1024;
const SSE_FRAME_BYTES: usize = 16 * 1024;

#[derive(Clone)]
struct RuntimeConfig {
    host: String,
    port: u16,
    max_connections: usize,
    max_handlers: usize,
    max_queued_handlers: usize,
    max_sse_streams: usize,
    max_sse_event_bytes: usize,
    request_metadata: RequestMetadataLimits,
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
    body_sinks: BodySinkService,
    telemetry: TelemetryConfig,
    metrics: Arc<Metrics>,
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
            if config.sse_max_streams == 0 {
                return Err("maximum admitted SSE streams must be non-zero".to_owned());
            }
            if config.sse_max_event_bytes == 0
                || config.sse_max_event_bytes as usize > MAX_SSE_EVENT_BYTES
            {
                return Err("maximum SSE event size must be between 1 byte and 16 MiB".to_owned());
            }
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
            let request_metadata = RequestMetadataLimits::new(
                config.request_target_max_bytes,
                config.request_header_max_bytes,
                config.request_header_max_fields,
            )?;
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
            let writable_roots = config
                .writable_roots
                .as_slice()
                .iter()
                .map(writable_root_from_roc)
                .collect::<Result<Vec<_>, _>>()?;
            let metrics = Metrics::new();
            let files = FileService::activate(
                roots,
                config.file_max_concurrent as usize,
                config.file_chunk_bytes as usize,
                Arc::clone(&metrics),
            )?;
            let body_sinks = BodySinkService::activate(
                writable_roots,
                config.body_sink_max_concurrent as usize,
                Duration::from_millis(config.body_sink_timeout_ms),
            )?;
            let access_log = if config.access_log_enabled {
                let target = match config.access_log_target {
                    0 => LogTarget::None,
                    1 => LogTarget::PathWithoutQuery,
                    _ => return Err("invalid access log target policy".to_owned()),
                };
                if config.access_log_buffer_events == 0 {
                    return Err("access log buffer capacity must be non-zero".to_owned());
                }
                Some(AccessLogConfig {
                    target,
                    buffer_events: config.access_log_buffer_events as usize,
                })
            } else if config.access_log_target == 0 && config.access_log_buffer_events == 0 {
                None
            } else {
                return Err("malformed disabled access log configuration".to_owned());
            };
            let metrics_path = if config.metrics_enabled {
                Some(config.metrics_path.as_str().to_owned())
            } else if config.metrics_path.is_empty() {
                None
            } else {
                return Err("malformed disabled metrics configuration".to_owned());
            };
            let routes = NativeRouter::activate(
                &files,
                file_routes,
                liveness_routes,
                readiness_routes,
                metrics_path.clone(),
            )?;
            Ok(Self {
                host: config.host.as_str().to_owned(),
                port: config.port,
                max_connections,
                max_handlers,
                max_queued_handlers: config.max_queued_handlers as usize,
                max_sse_streams: config.sse_max_streams as usize,
                max_sse_event_bytes: config.sse_max_event_bytes as usize,
                request_metadata,
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
                body_sinks,
                telemetry: TelemetryConfig { access_log },
                metrics,
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
    path_buf_from_roc(
        root.path_tag,
        root.path_utf8.as_str(),
        root.path_unix_bytes.as_slice(),
        root.path_windows_u16s.as_slice(),
        "file-root",
    )
}

fn path_buf_from_roc(
    tag: u8,
    utf8: &str,
    unix_bytes: &[u8],
    windows_u16s: &[u16],
    authority_kind: &str,
) -> Result<PathBuf, String> {
    match tag {
        0 if unix_bytes.is_empty() && windows_u16s.is_empty() => Ok(PathBuf::from(utf8)),
        1 if utf8.is_empty() && windows_u16s.is_empty() => {
            #[cfg(unix)]
            {
                use std::os::unix::ffi::OsStringExt;
                Ok(PathBuf::from(std::ffi::OsString::from_vec(
                    unix_bytes.to_vec(),
                )))
            }
            #[cfg(not(unix))]
            {
                Err(format!(
                    "a Unix {authority_kind} path was supplied on a non-Unix target"
                ))
            }
        }
        2 if utf8.is_empty() && unix_bytes.is_empty() => {
            #[cfg(windows)]
            {
                use std::os::windows::ffi::OsStringExt;
                Ok(PathBuf::from(std::ffi::OsString::from_wide(windows_u16s)))
            }
            #[cfg(not(windows))]
            {
                Err(format!(
                    "a Windows {authority_kind} path was supplied on a non-Windows target"
                ))
            }
        }
        _ => Err(format!("malformed {authority_kind} path")),
    }
}

fn writable_root_from_roc(root: &ServerWritableRoot) -> Result<WritableRootSpec, String> {
    let path = path_buf_from_roc(
        root.path_tag,
        root.path_utf8.as_str(),
        root.path_unix_bytes.as_slice(),
        root.path_windows_u16s.as_slice(),
        "writable-root",
    )?;
    Ok(WritableRootSpec {
        id: root.id.as_str().to_owned(),
        path,
    })
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AdmissionError {
    Full,
    Stopping,
}

struct ActiveHandler {
    metrics: Arc<Metrics>,
    _metrics: ActiveGaugeGuard,
}

impl ActiveHandler {
    fn new(metrics: Arc<Metrics>) -> Self {
        let gauge = metrics.handler_started();
        Self {
            metrics,
            _metrics: gauge,
        }
    }

    fn record_duration(&self, duration: Duration) {
        self.metrics.record_handler_duration(duration);
    }
}

enum RocJobAdmission {
    Active {
        handler: ActiveHandler,
        queue_wait: Duration,
    },
    Queued {
        _metrics: ActiveGaugeGuard,
        queued_at: Instant,
        metrics: Arc<Metrics>,
    },
}

impl RocJobAdmission {
    fn new(class: AdmissionClass, metrics: Arc<Metrics>) -> Self {
        match class {
            AdmissionClass::Active => {
                metrics.record_handler_queue_wait(Duration::ZERO);
                Self::Active {
                    handler: ActiveHandler::new(metrics),
                    queue_wait: Duration::ZERO,
                }
            }
            AdmissionClass::Queued => Self::Queued {
                _metrics: metrics.handler_queued(),
                queued_at: Instant::now(),
                metrics,
            },
        }
    }

    fn promote(self) -> (ActiveHandler, Duration) {
        match self {
            Self::Active {
                handler,
                queue_wait,
            } => (handler, queue_wait),
            Self::Queued {
                _metrics,
                queued_at,
                metrics,
            } => {
                drop(_metrics);
                let queue_wait = queued_at.elapsed();
                metrics.record_handler_queue_wait(queue_wait);
                (ActiveHandler::new(metrics), queue_wait)
            }
        }
    }

    fn is_queued(&self) -> bool {
        matches!(self, Self::Queued { .. })
    }
}

struct RocScheduledJob {
    admission: RocJobAdmission,
    job: RocJob,
}

enum RocJob {
    Ordinary(OrdinaryRocJob),
    Sse(SseRocJob),
}

struct OrdinaryRocJob {
    parts: hyper::http::request::Parts,
    metadata: RequestMetadata,
    body_handle: crate::request_body::BodyHandle,
    body_limit: u64,
    declared_length: Option<u64>,
    roc_context: Arc<RocContext>,
    accepted_encodings: AcceptedEncodings,
    response_semantics: RequestSemantics,
    active_request: Arc<ActiveRequest>,
    telemetry: crate::telemetry::RequestTelemetry,
    completion: oneshot::Sender<Result<RocOutcome, RocExecutionError>>,
}

struct SseRocJob {
    source: OwnedSseSource,
    wake_generation: u64,
    active_request: Arc<ActiveRequest>,
    completion: Arc<SseCompletionSlot>,
}

struct QueuedRocJobGuard {
    executor: FixedExecutorHandle<RocScheduledJob>,
    ticket: Option<QueueTicket>,
}

impl QueuedRocJobGuard {
    fn new(executor: FixedExecutorHandle<RocScheduledJob>, ticket: QueueTicket) -> Self {
        Self {
            executor,
            ticket: Some(ticket),
        }
    }

    fn cancel(&mut self) -> bool {
        self.ticket
            .take()
            .and_then(|ticket| self.executor.cancel_queued(ticket))
            .is_some()
    }

    fn disarm(&mut self) {
        self.ticket = None;
    }
}

impl Drop for QueuedRocJobGuard {
    fn drop(&mut self) {
        let _ = self.cancel();
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RocExecutionError {
    Panic,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RocDispatchError {
    Admission(AdmissionError),
    Execution(RocExecutionError),
    CompletionLost,
}

fn execute_roc_job(scheduled: RocScheduledJob) {
    let was_queued = scheduled.admission.is_queued();
    match scheduled.job {
        RocJob::Ordinary(job) => {
            if was_queued && job.completion.is_closed() {
                return;
            }
            let (active_handler, queue_wait) = scheduled.admission.promote();
            let OrdinaryRocJob {
                parts,
                metadata,
                body_handle,
                body_limit,
                declared_length,
                roc_context,
                accepted_encodings,
                response_semantics,
                active_request: _active_request,
                telemetry,
                completion,
            } = job;
            let handled = std::panic::catch_unwind(AssertUnwindSafe(|| {
                let roc_request = request_to_roc(
                    parts,
                    metadata,
                    body_handle.retain_for_roc(),
                    body_limit,
                    declared_length,
                );
                let request_context = roc_context.retain_for_request();
                let (result, handler_duration) = call_roc(
                    roc_request,
                    request_context,
                    accepted_encodings,
                    &response_semantics,
                );
                active_handler.record_duration(handler_duration);
                telemetry.record_handler(queue_wait, handler_duration);
                result
            }))
            .map_err(|_| RocExecutionError::Panic);
            body_handle.expire();
            let _ = completion.send(handled);
        }
        RocJob::Sse(job) => {
            if !job.completion.start_running(was_queued) {
                return;
            }
            let (active_handler, _queue_wait) = scheduled.admission.promote();
            let SseRocJob {
                source,
                wake_generation,
                active_request: _active_request,
                completion,
            } = job;
            let started = Instant::now();
            let step =
                std::panic::catch_unwind(AssertUnwindSafe(|| source.advance(wake_generation)))
                    .map_err(|_| RocExecutionError::Panic);
            active_handler.record_duration(started.elapsed());
            completion.complete(step);
        }
    }
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
    roc_executor: FixedExecutorHandle<RocScheduledJob>,
    stream_slots: Arc<Semaphore>,
    brotli: BrotliExecutor,
    requests: RequestTracker,
    shutdown: ShutdownController,
    telemetry: TelemetryHandle,
}

pub fn start() -> i32 {
    let exit_code = start_inner();
    crate::http::shutdown();
    crate::tcp::shutdown();
    exit_code
}

fn start_inner() -> i32 {
    let mut init_result = unsafe { roc_init_for_host() };
    let initialized = match init_result.tag {
        InitForHostResultTag::Ok => unsafe { init_result.take_payload_ok_unchecked() },
        InitForHostResultTag::Err => {
            return exit_code_to_i32(unsafe { init_result.take_payload_err_unchecked() });
        }
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

    let telemetry = match Telemetry::activate(config.telemetry.clone(), Arc::clone(&config.metrics))
    {
        Ok(telemetry) => telemetry,
        Err(detail) => {
            return finish_shutdown(
                ShutdownReason::StartupFailed(detail),
                raw_context,
                config.hook_timeout,
            );
        }
    };
    let roc_context = Arc::new(RocContext::new(raw_context));
    let shutdown = ShutdownController::new();
    let brotli_workers = std::thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(1)
        .min(config.max_handlers)
        .max(1);
    let brotli = match BrotliExecutor::new(brotli_workers, config.max_sse_streams) {
        Ok(executor) => executor,
        Err(error) => {
            return finish_shutdown(
                ShutdownReason::StartupFailed(format!("failed to start Brotli executor: {error}")),
                raw_context,
                config.hook_timeout,
            );
        }
    };
    let roc_executor = match FixedExecutor::new(
        "roc-handler",
        config.max_handlers,
        config.max_queued_handlers,
        execute_roc_job,
    ) {
        Ok(executor) => executor,
        Err(error) => {
            return finish_shutdown(
                ShutdownReason::StartupFailed(format!("failed to start Roc executor: {error}")),
                raw_context,
                config.hook_timeout,
            );
        }
    };
    let context = ServerContext {
        config: Arc::new(config.clone()),
        roc_context: Arc::clone(&roc_context),
        roc_executor: roc_executor.handle(),
        stream_slots: Arc::new(Semaphore::new(config.max_sse_streams)),
        brotli,
        requests: RequestTracker::new(),
        shutdown: shutdown.clone(),
        telemetry: telemetry.handle(),
    };

    let reason = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime.block_on(run_server(context)),
        Err(error) => {
            ShutdownReason::RuntimeFailed(format!("failed to initialize Tokio runtime: {error}"))
        }
    };
    roc_executor.shutdown();
    telemetry.shutdown();

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

    let mut result = unsafe { roc_shutdown_for_host(raw_reason, context) };
    let _ = finished_sender.send(());
    let _ = watchdog.join();

    match result.tag {
        ShutdownForHostResultTag::Ok => default_exit_code,
        ShutdownForHostResultTag::Err => {
            exit_code_to_i32(unsafe { result.take_payload_err_unchecked() })
        }
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
    metadata: RequestMetadata,
    body_handle: *mut u64,
    body_limit: u64,
    declared_length: Option<u64>,
) -> ServerRequest {
    let roc_host = roc_host();
    let backing = match RequestPartsBacking::new(parts, metadata) {
        Ok(backing) => backing,
        Err(parts) => {
            return request_to_roc_copied(
                *parts,
                metadata,
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
    let mut target_path = RocStr::empty();
    let mut target_query = RocStr::empty();
    let mut target_authority_host = RocStr::empty();
    let mut target_authority_port = 0;
    let mut target_authority_port_present = false;
    let mut target_query_present = false;
    let target_tag = match backing.target_kind() {
        TargetKind::Resource => {
            let path = backing
                .resource_path()
                .expect("validated resource target must have a path");
            target_path = if backing.resource_path_is_backed() {
                backing_references += 1;
                backing.roc_str(path)
            } else {
                // An absolute URI with no path normalizes to `/`. Hyper returns
                // that static string, so it cannot borrow the request backing.
                RocStr::from_str(path, roc_host)
            };
            if let Some(query) = backing.resource_query() {
                target_query_present = true;
                backing_references += 1;
                target_query = backing.roc_str(query);
            }
            0
        }
        TargetKind::Authority => {
            let authority = backing
                .target_authority()
                .expect("validated authority target must have an authority");
            backing_references += 1;
            target_authority_host = backing.roc_str(authority.host);
            target_authority_port = authority.port.unwrap_or_default();
            target_authority_port_present = authority.port.is_some();
            1
        }
        TargetKind::Asterisk => 2,
    };
    let mut authority_host = RocStr::empty();
    let mut authority_port = 0;
    let mut authority_port_present = false;
    let authority_present = if let Some(authority) = backing.effective_authority() {
        backing_references += 1;
        authority_host = backing.roc_str(authority.host);
        authority_port = authority.port.unwrap_or_default();
        authority_port_present = authority.port.is_some();
        true
    } else {
        false
    };
    backing.install(backing_references);

    ServerRequest {
        authority_host,
        authority_port,
        authority_port_present,
        authority_present,
        body_handle,
        body_limit_bytes: body_limit,
        content_length: declared_length.unwrap_or_default(),
        headers,
        method_ext,
        target_authority_host,
        target_authority_port,
        target_authority_port_present,
        target_path,
        target_query,
        target_query_present,
        target_tag,
        content_length_known: declared_length.is_some(),
        method: method_tag,
    }
}

fn request_to_roc_copied(
    parts: hyper::http::request::Parts,
    metadata: RequestMetadata,
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
    let target_tag = match metadata.target_kind() {
        TargetKind::Resource => 0,
        TargetKind::Authority => 1,
        TargetKind::Asterisk => 2,
    };
    let target_path = metadata
        .resource_path(&parts.uri)
        .map_or_else(RocStr::empty, |value| RocStr::from_str(value, roc_host));
    let target_query = metadata
        .resource_query(&parts.uri)
        .map_or_else(RocStr::empty, |value| RocStr::from_str(value, roc_host));
    let target_query_present = metadata.resource_query(&parts.uri).is_some();
    let target_authority = metadata.target_authority(&parts.uri, &parts.headers);
    let target_authority_host = target_authority.map_or_else(RocStr::empty, |value| {
        RocStr::from_str(value.host, roc_host)
    });
    let target_authority_port = target_authority
        .and_then(|value| value.port)
        .unwrap_or_default();
    let target_authority_port_present = target_authority.is_some_and(|value| value.port.is_some());
    let authority = metadata.effective_authority(&parts.uri, &parts.headers);
    let authority_host = authority.map_or_else(RocStr::empty, |value| {
        RocStr::from_str(value.host, roc_host)
    });
    let authority_port = authority.and_then(|value| value.port).unwrap_or_default();
    let authority_port_present = authority.is_some_and(|value| value.port.is_some());

    ServerRequest {
        authority_host,
        authority_port,
        authority_port_present,
        authority_present: authority.is_some(),
        body_handle,
        body_limit_bytes: body_limit,
        content_length: declared_length.unwrap_or_default(),
        headers,
        method_ext,
        target_authority_host,
        target_authority_port,
        target_authority_port_present,
        target_path,
        target_query,
        target_query_present,
        target_tag,
        content_length_known: declared_length.is_some(),
        method: method_tag,
    }
}

fn call_roc(
    request: ServerRequest,
    context: RocBox,
    accepted_encodings: AcceptedEncodings,
    response_semantics: &RequestSemantics,
) -> (RocOutcome, Duration) {
    let started = Instant::now();
    let response = unsafe { roc_respond_for_host(request, context) };
    let roc_duration = started.elapsed();
    (
        outcome_from_roc(response, accepted_encodings, response_semantics),
        roc_duration,
    )
}

enum RocOutcome {
    Ordinary(
        Result<ServerResponse, crate::response::ResponseError>,
        Option<i64>,
    ),
    File(FilePlan),
    Stream {
        source: OwnedSseSource,
        coding: StreamingContentCoding,
    },
    Invalid(String),
}

/// Affine owner for the generated tagged response value. Generated ABI types
/// are layout values and therefore `Copy`; this wrapper is the host's source of
/// truth for whether a consuming payload projection has moved the one owner.
struct OwnedRocOutcome {
    raw: MaybeUninit<RocServerResponse>,
    live: bool,
}

impl OwnedRocOutcome {
    fn new(raw: RocServerResponse) -> Self {
        Self {
            raw: MaybeUninit::new(raw),
            live: true,
        }
    }

    fn tag(&self) -> ServerResponseTag {
        unsafe { self.raw.assume_init_ref().tag }
    }

    unsafe fn take_ordinary(&mut self) -> ServerOrdinaryResponse {
        let payload = unsafe { self.raw.assume_init_mut().take_payload_ordinary_unchecked() };
        self.live = false;
        payload
    }

    unsafe fn take_file(&mut self) -> ServerFileResponse {
        let payload = unsafe { self.raw.assume_init_mut().take_payload_file_unchecked() };
        self.live = false;
        payload
    }

    unsafe fn take_stream(&mut self) -> RocErasedCallable {
        let payload = unsafe { self.raw.assume_init_mut().take_payload_stream_unchecked() };
        self.live = false;
        payload
    }
}

impl Drop for OwnedRocOutcome {
    fn drop(&mut self) {
        if self.live {
            let raw = unsafe { self.raw.assume_init_read() };
            self.live = false;
            unsafe { raw.decref(roc_host()) };
        }
    }
}

struct OwnedSseSource(Option<RocErasedCallable>);

impl OwnedSseSource {
    fn new(raw: RocErasedCallable) -> Self {
        Self(Some(raw))
    }

    fn advance(mut self, wake_generation: u64) -> OwnedSseStep {
        let source = self.0.take().expect("live SSE source owns its callable");
        OwnedSseStep::new(unsafe { roc_sse_advance_for_host(source, wake_generation) })
    }
}

struct OwnedSseStep {
    raw: MaybeUninit<SseStepToHost>,
    live: bool,
}

unsafe impl Send for OwnedSseStep {}

impl OwnedSseStep {
    fn new(raw: SseStepToHost) -> Self {
        Self {
            raw: MaybeUninit::new(raw),
            live: true,
        }
    }

    fn into_result(mut self) -> Result<SseAdvance, io::Error> {
        let tag = unsafe { self.raw.assume_init_ref().tag };
        let result = match tag {
            SseStepToHostTag::EmitToHost => {
                let payload = unsafe {
                    self.raw
                        .assume_init_mut()
                        .take_payload_emit_to_host_unchecked()
                };
                SseAdvance::Emit {
                    item: OwnedSseItem(Some(payload.item)),
                    source: OwnedSseSource::new(payload.source),
                    wait_millis: payload.wait_millis,
                }
            }
            SseStepToHostTag::WaitToHost => {
                let payload = unsafe {
                    self.raw
                        .assume_init_mut()
                        .take_payload_wait_to_host_unchecked()
                };
                SseAdvance::Wait {
                    source: OwnedSseSource::new(payload.source),
                    wait_millis: payload.wait_millis,
                }
            }
            SseStepToHostTag::EndToHost => SseAdvance::End,
            SseStepToHostTag::ErrorToHost => {
                let error = unsafe {
                    self.raw
                        .assume_init_mut()
                        .take_payload_error_to_host_unchecked()
                };
                let detail = error.as_str().to_owned();
                unsafe { error.decref(roc_host()) };
                self.live = false;
                return Err(io::Error::other(format!(
                    "Roc SSE transition failed: {detail}"
                )));
            }
        };
        self.live = false;
        Ok(result)
    }
}

impl Drop for OwnedSseStep {
    fn drop(&mut self) {
        if self.live {
            let raw = unsafe { self.raw.assume_init_read() };
            self.live = false;
            unsafe { raw.decref(roc_host()) };
        }
    }
}

struct OwnedSseItem(Option<RocListWith<u8, false>>);

impl AsRef<[u8]> for OwnedSseItem {
    fn as_ref(&self) -> &[u8] {
        self.0
            .as_ref()
            .expect("live SSE item owns its Roc list")
            .as_slice()
    }
}

unsafe impl Send for OwnedSseItem {}

impl Drop for OwnedSseItem {
    fn drop(&mut self) {
        if let Some(item) = self.0.take() {
            unsafe { item.decref(roc_host()) };
        }
    }
}

enum SseAdvance {
    Emit {
        item: OwnedSseItem,
        source: OwnedSseSource,
        wait_millis: u64,
    },
    Wait {
        source: OwnedSseSource,
        wait_millis: u64,
    },
    End,
}

enum SseCompletionState {
    Idle,
    Pending { queued: bool },
    Running,
    Ready(Result<OwnedSseStep, RocExecutionError>),
    Cancelled,
}

struct SseCompletionSlot {
    state: Mutex<SseCompletionState>,
    waker: AtomicWaker,
}

enum SseCompletionPoll {
    Idle,
    Queued,
    Active,
    Ready(Result<OwnedSseStep, RocExecutionError>),
    Cancelled,
}

#[derive(Debug)]
enum SseTransitionError {
    Admission(AdmissionError),
    QueueTimedOut,
    Panic,
    Application(io::Error),
    Oversized { actual: usize, limit: usize },
}

impl std::fmt::Display for SseTransitionError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Admission(error) => write!(formatter, "transition admission failed: {error:?}"),
            Self::QueueTimedOut => formatter.write_str("transition queue wait timed out"),
            Self::Panic => formatter.write_str("transition panicked"),
            Self::Application(error) => write!(formatter, "{error}"),
            Self::Oversized { actual, limit } => {
                write!(
                    formatter,
                    "framed event is {actual} bytes; limit is {limit}"
                )
            }
        }
    }
}

impl SseCompletionSlot {
    fn new() -> Self {
        Self {
            state: Mutex::new(SseCompletionState::Idle),
            waker: AtomicWaker::new(),
        }
    }

    fn begin(&self) {
        let mut state = self.state.lock().expect("SSE completion mutex poisoned");
        assert!(matches!(*state, SseCompletionState::Idle));
        *state = SseCompletionState::Pending { queued: false };
    }

    fn abort_begin(&self) {
        let mut state = self.state.lock().expect("SSE completion mutex poisoned");
        assert!(matches!(*state, SseCompletionState::Pending { .. }));
        *state = SseCompletionState::Idle;
    }

    fn mark_queued(&self) {
        let mut state = self.state.lock().expect("SSE completion mutex poisoned");
        if let SseCompletionState::Pending { queued } = &mut *state {
            *queued = true;
        }
    }

    fn start_running(&self, was_queued: bool) -> bool {
        let mut state = self.state.lock().expect("SSE completion mutex poisoned");
        match &*state {
            SseCompletionState::Pending { queued } => {
                debug_assert!(!was_queued || *queued);
                *state = SseCompletionState::Running;
                drop(state);
                self.waker.wake();
                true
            }
            SseCompletionState::Cancelled => false,
            _ => panic!("SSE completion started from invalid state"),
        }
    }

    fn complete(&self, result: Result<OwnedSseStep, RocExecutionError>) {
        let mut state = self.state.lock().expect("SSE completion mutex poisoned");
        match &*state {
            SseCompletionState::Running => {
                *state = SseCompletionState::Ready(result);
                drop(state);
                self.waker.wake();
            }
            SseCompletionState::Cancelled => drop(result),
            _ => panic!("SSE completion finished from invalid state"),
        }
    }

    fn poll(&self, context: &mut Context<'_>) -> SseCompletionPoll {
        self.waker.register(context.waker());
        let mut state = self.state.lock().expect("SSE completion mutex poisoned");
        match &*state {
            SseCompletionState::Idle => SseCompletionPoll::Idle,
            SseCompletionState::Pending { queued: true } => SseCompletionPoll::Queued,
            SseCompletionState::Pending { queued: false } | SseCompletionState::Running => {
                SseCompletionPoll::Active
            }
            SseCompletionState::Ready(_) => {
                let SseCompletionState::Ready(result) =
                    std::mem::replace(&mut *state, SseCompletionState::Idle)
                else {
                    unreachable!()
                };
                SseCompletionPoll::Ready(result)
            }
            SseCompletionState::Cancelled => SseCompletionPoll::Cancelled,
        }
    }

    fn cancel(&self) {
        let mut state = self.state.lock().expect("SSE completion mutex poisoned");
        let previous = std::mem::replace(&mut *state, SseCompletionState::Cancelled);
        drop(state);
        if let SseCompletionState::Ready(result) = previous {
            drop(result);
        }
        self.waker.wake();
    }
}

struct RocSseItemSource {
    source: Option<OwnedSseSource>,
    after_item: Option<(OwnedSseSource, u64)>,
    primed_item: Option<SseItem>,
    wake: Pin<Box<tokio::time::Sleep>>,
    wake_parked: bool,
    queue_wait: Pin<Box<tokio::time::Sleep>>,
    wake_generation: u64,
    executor: FixedExecutorHandle<RocScheduledJob>,
    completion: Arc<SseCompletionSlot>,
    queued_ticket: Option<QueueTicket>,
    metrics: Arc<Metrics>,
    handler_queue_timeout: Duration,
    active_request: Arc<ActiveRequest>,
    _stream_slot: OwnedSemaphorePermit,
    ended: bool,
}

impl RocSseItemSource {
    fn new(
        source: OwnedSseSource,
        executor: FixedExecutorHandle<RocScheduledJob>,
        metrics: Arc<Metrics>,
        handler_queue_timeout: Duration,
        active_request: Arc<ActiveRequest>,
        stream_slot: OwnedSemaphorePermit,
    ) -> Self {
        Self {
            source: Some(source),
            after_item: None,
            primed_item: None,
            wake: Box::pin(tokio::time::sleep(Duration::ZERO)),
            wake_parked: false,
            queue_wait: Box::pin(tokio::time::sleep(Duration::ZERO)),
            wake_generation: 0,
            executor,
            completion: Arc::new(SseCompletionSlot::new()),
            queued_ticket: None,
            metrics,
            handler_queue_timeout,
            active_request,
            _stream_slot: stream_slot,
            ended: false,
        }
    }

    fn park(&mut self, source: OwnedSseSource, wait_millis: u64) {
        self.source = Some(source);
        self.wake_parked = wait_millis != 0;
        if self.wake_parked {
            self.wake
                .as_mut()
                .reset(tokio::time::Instant::now() + Duration::from_millis(wait_millis));
        }
    }

    fn start_advance(&mut self) -> Result<(), AdmissionError> {
        let mut source = Some(self.source.take().expect("parked SSE source exists"));
        self.wake_generation = self.wake_generation.wrapping_add(1);
        let wake_generation = self.wake_generation;
        let active_request = Arc::clone(&self.active_request);
        let completion = Arc::clone(&self.completion);
        let metrics = Arc::clone(&self.metrics);
        self.completion.begin();
        let admitted = self.executor.try_submit(|class| {
            if class == AdmissionClass::Queued {
                completion.mark_queued();
            }
            RocScheduledJob {
                admission: RocJobAdmission::new(class, metrics),
                job: RocJob::Sse(SseRocJob {
                    source: source.take().expect("admitted SSE source exists"),
                    wake_generation,
                    active_request,
                    completion,
                }),
            }
        });
        match admitted {
            Ok(admission) if admission.class == AdmissionClass::Active => Ok(()),
            Ok(admission) => {
                self.queued_ticket = Some(admission.ticket);
                self.queue_wait
                    .as_mut()
                    .reset(tokio::time::Instant::now() + self.handler_queue_timeout);
                Ok(())
            }
            Err(error) => {
                self.completion.abort_begin();
                Err(match error {
                    SubmitError::Full => AdmissionError::Full,
                    SubmitError::Stopping => AdmissionError::Stopping,
                })
            }
        }
    }

    fn poll_transition(
        &mut self,
        context: &mut Context<'_>,
    ) -> Poll<Result<SseAdvance, SseTransitionError>> {
        let mut completion = self.completion.poll(context);
        if matches!(completion, SseCompletionPoll::Idle) {
            if let Err(error) = self.start_advance() {
                return Poll::Ready(Err(SseTransitionError::Admission(error)));
            }
            completion = self.completion.poll(context);
        }
        match completion {
            SseCompletionPoll::Queued => {
                if self.queue_wait.as_mut().poll(context).is_ready() {
                    if let Some(ticket) = self.queued_ticket.take() {
                        if let Some(job) = self.executor.cancel_queued(ticket) {
                            self.completion.cancel();
                            drop(job);
                            return Poll::Ready(Err(SseTransitionError::QueueTimedOut));
                        }
                    }
                }
                Poll::Pending
            }
            SseCompletionPoll::Active => {
                self.queued_ticket = None;
                Poll::Pending
            }
            SseCompletionPoll::Ready(Ok(step)) => {
                self.queued_ticket = None;
                Poll::Ready(step.into_result().map_err(SseTransitionError::Application))
            }
            SseCompletionPoll::Ready(Err(RocExecutionError::Panic)) => {
                self.queued_ticket = None;
                Poll::Ready(Err(SseTransitionError::Panic))
            }
            SseCompletionPoll::Cancelled => Poll::Ready(Ok(SseAdvance::End)),
            SseCompletionPoll::Idle => unreachable!("SSE transition was submitted"),
        }
    }

    async fn precommit(mut self, max_event_bytes: usize) -> Result<Self, SseTransitionError> {
        let advance = futures::future::poll_fn(|context| self.poll_transition(context)).await?;
        match advance {
            SseAdvance::Emit {
                item,
                source,
                wait_millis,
            } => {
                let actual = item.as_ref().len();
                if actual > max_event_bytes {
                    self.ended = true;
                    return Err(SseTransitionError::Oversized {
                        actual,
                        limit: max_event_bytes,
                    });
                }
                self.after_item = Some((source, wait_millis));
                self.primed_item = Some(SseItem::new(item));
            }
            SseAdvance::Wait {
                source,
                wait_millis,
            } => self.park(source, wait_millis),
            SseAdvance::End => self.ended = true,
        }
        Ok(self)
    }

    fn cancel_now(&mut self) {
        self.ended = true;
        self.source.take();
        self.after_item.take();
        self.primed_item.take();
        self.wake_parked = false;
        if let Some(ticket) = self.queued_ticket.take() {
            drop(self.executor.cancel_queued(ticket));
        }
        self.completion.cancel();
    }
}

impl SseItemSource for RocSseItemSource {
    fn poll_item(mut self: Pin<&mut Self>, context: &mut Context<'_>) -> SseSourcePoll {
        loop {
            if let Some(item) = self.primed_item.take() {
                return SseSourcePoll::Item(item);
            }
            if self.ended {
                return SseSourcePoll::End;
            }
            if self.after_item.is_some() {
                return SseSourcePoll::Advancing;
            }
            if self.wake_parked {
                if self.wake.as_mut().poll(context).is_pending() {
                    return SseSourcePoll::Parked;
                }
                self.wake_parked = false;
            }
            let advance = match self.poll_transition(context) {
                Poll::Pending => return SseSourcePoll::Advancing,
                Poll::Ready(Ok(advance)) => advance,
                Poll::Ready(Err(error)) => {
                    self.ended = true;
                    return SseSourcePoll::Error(io::Error::other(error.to_string()));
                }
            };
            match advance {
                SseAdvance::Emit {
                    item,
                    source,
                    wait_millis,
                } => {
                    self.after_item = Some((source, wait_millis));
                    return SseSourcePoll::Item(SseItem::new(item));
                }
                SseAdvance::Wait {
                    source,
                    wait_millis,
                } => self.park(source, wait_millis),
                SseAdvance::End => {
                    self.ended = true;
                    return SseSourcePoll::End;
                }
            }
        }
    }

    fn item_drained(mut self: Pin<&mut Self>) {
        let (source, wait_millis) = self
            .after_item
            .take()
            .expect("drained SSE item has one retained next source");
        self.park(source, wait_millis);
    }

    fn cancel(mut self: Pin<&mut Self>) {
        self.cancel_now();
    }
}

impl Drop for RocSseItemSource {
    fn drop(&mut self) {
        if !self.ended {
            self.cancel_now();
        }
    }
}

// SAFETY: a returned erased callable is immutable Roc-owned state. Its ARC
// slots are atomic and the host allocator/deallocator is thread-safe.
unsafe impl Send for OwnedSseSource {}

impl Drop for OwnedSseSource {
    fn drop(&mut self) {
        if let Some(source) = self.0.take() {
            unsafe { decref_erased_callable(source, roc_host()) };
        }
    }
}

fn outcome_from_roc(
    response: RocServerResponse,
    accepted_encodings: AcceptedEncodings,
    response_semantics: &RequestSemantics,
) -> RocOutcome {
    let mut owner = OwnedRocOutcome::new(response);
    match owner.tag() {
        ServerResponseTag::Ordinary => {
            let response = unsafe { owner.take_ordinary() };
            let stop_code = response.stop.then_some(response.exit_code);
            RocOutcome::Ordinary(
                response_to_hyper(
                    RocResponseOwner { response },
                    accepted_encodings,
                    response_semantics,
                ),
                stop_code,
            )
        }
        ServerResponseTag::File => {
            let response = unsafe { owner.take_file() };
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
            unsafe { response.decref(roc_host()) };
            RocOutcome::File(FilePlan::authorized(root_id, relative, disposition, cache))
        }
        ServerResponseTag::Stream => {
            let source = unsafe { owner.take_stream() };
            RocOutcome::Stream {
                source: OwnedSseSource::new(source),
                coding: accepted_encodings.preferred_streaming(),
            }
        }
    }
}

fn request_stop_after(shutdown: &ShutdownController, exit_code: Option<i64>) {
    if let Some(exit_code) = exit_code {
        shutdown.request(ShutdownReason::ApplicationRequested { exit_code });
    }
}

fn response_to_hyper(
    owner: RocResponseOwner,
    accepted_encodings: AcceptedEncodings,
    request: &RequestSemantics,
) -> Result<ServerResponse, crate::response::ResponseError> {
    crate::request_body::validate_response_body(&owner.response.body);
    let body_length = owner.response.body.len();
    let (status, headers) = application_parts(
        owner.response.status,
        owner
            .response
            .headers
            .as_slice()
            .iter()
            .map(|header| (header.name.as_str(), header.value.as_str())),
        body_length as u64,
        request,
    )?;
    let mut head = hyper::Response::new(());
    *head.status_mut() = status;
    *head.headers_mut() = headers;
    let (mut parts, ()) = head.into_parts();
    if body_length <= MAX_BUFFERED_COMPRESSION_BYTES
        && response_is_compressible(parts.status, &parts.headers, body_length as u64)
    {
        vary_on_accept_encoding(&mut parts.headers);
        if let Some(coding) = accepted_encodings.preferred() {
            if let Ok(encoded) = encode_bytes(coding, owner.response.body.as_slice()) {
                if encoded.len() < body_length {
                    apply_content_coding(&mut parts.headers, coding, Some(encoded.len()));
                    return Ok(hyper::Response::from_parts(
                        parts,
                        full_body(Bytes::from(encoded)),
                    ));
                }
            }
        }
    }
    let body = Bytes::from_owner(owner);
    Ok(hyper::Response::from_parts(parts, full_body(body)))
}

fn sse_response(
    source: RocSseItemSource,
    max_event_bytes: usize,
    brotli: Option<BrotliLane>,
) -> ServerResponse {
    let compressed = brotli.is_some();
    let (_handle, body) = match brotli {
        Some(lane) => {
            SseBody::new_bounded_brotli(source, max_event_bytes, 1, SSE_FRAME_BYTES, lane)
        }
        None => SseBody::new(
            source,
            max_event_bytes,
            1,
            SSE_FRAME_BYTES,
            SseCompression::Identity,
        ),
    };
    let mut response = hyper::Response::builder()
        .status(hyper::StatusCode::OK)
        .header(CONTENT_TYPE, "text/event-stream")
        .header(CACHE_CONTROL, "no-cache")
        .body(body.boxed_unsync())
        .expect("canonical SSE response is valid");
    vary_on_accept_encoding(response.headers_mut());
    if compressed {
        response
            .headers_mut()
            .insert(hyper::header::CONTENT_ENCODING, "br".parse().unwrap());
    }
    response
}

/// Owns every Roc reference in a response while Hyper may still transmit the
/// body. This is intentionally the whole response rather than just its body:
/// generated recursive decref remains the single source of truth, and keeping
/// the small header descriptors alive until body completion is bounded.
struct RocResponseOwner {
    response: ServerOrdinaryResponse,
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

fn no_acceptable_sse_content_coding() -> ServerResponse {
    let mut response = hyper::Response::builder()
        .status(hyper::StatusCode::NOT_ACCEPTABLE)
        .body(full_body(Bytes::from_static(
            b"No acceptable SSE content coding",
        )))
        .expect("static 406 response is valid");
    vary_on_accept_encoding(response.headers_mut());
    response
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

fn invalid_request_target() -> ServerResponse {
    hyper::Response::builder()
        .status(hyper::StatusCode::BAD_REQUEST)
        .body(full_body(Bytes::from_static(
            b"Invalid request target or authority",
        )))
        .expect("static 400 response is valid")
}

fn request_target_too_long(limit: usize) -> ServerResponse {
    hyper::Response::builder()
        .status(hyper::StatusCode::URI_TOO_LONG)
        .body(full_body(Bytes::from(format!(
            "Request target exceeds the {limit}-byte limit"
        ))))
        .expect("static 414 response is valid")
}

fn request_headers_too_large(byte_limit: usize, field_limit: usize) -> ServerResponse {
    hyper::Response::builder()
        .status(hyper::StatusCode::REQUEST_HEADER_FIELDS_TOO_LARGE)
        .body(full_body(Bytes::from(format!(
            "Request headers exceed the {byte_limit}-byte or {field_limit}-field limit"
        ))))
        .expect("static 431 response is valid")
}

fn reject_request_metadata(rejection: RequestMetadataRejection) -> ServerResponse {
    match rejection {
        RequestMetadataRejection::TargetTooLong { limit } => request_target_too_long(limit),
        RequestMetadataRejection::HeadersTooLarge {
            byte_limit,
            field_limit,
        } => request_headers_too_large(byte_limit, field_limit),
    }
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
    ) -> Poll<Option<Result<Frame<ServerData>, std::io::Error>>> {
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
    type Data = ServerData;
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
                let made_progress = frame.data_ref().is_some_and(Buf::has_remaining)
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

fn finalize_and_track_response(
    response: ServerResponse,
    response_semantics: &RequestSemantics,
    active_request: Option<Arc<ActiveRequest>>,
    http1_activity: Option<Http1Activity>,
    body_idle_timeout: Option<Duration>,
    telemetry: &crate::telemetry::RequestTelemetry,
) -> ServerResponse {
    let response = match finalize_response(response, response_semantics) {
        Ok(response) => response,
        Err(error) => {
            telemetry.reject(RejectionReason::InvalidRocResponse);
            eprintln!("Invalid host response: {error}");
            safe_internal_server_error(response_semantics)
        }
    };
    track_response(response, active_request, http1_activity, body_idle_timeout)
}

async fn handle_req(
    parts: hyper::http::request::Parts,
    body: RequestBodyStream,
    context: ServerContext,
    http1_activity: Option<Http1Activity>,
    response_semantics: RequestSemantics,
    telemetry: crate::telemetry::RequestTelemetry,
) -> ServerResponse {
    let body_idle_timeout = http1_activity
        .as_ref()
        .map(|_| context.config.response_idle_timeout);
    let active_request = match context.requests.begin() {
        Some(active) => Arc::new(active),
        None => {
            telemetry.reject(RejectionReason::Shutdown);
            return finalize_and_track_response(
                service_unavailable(),
                &response_semantics,
                None,
                http1_activity,
                body_idle_timeout,
                &telemetry,
            );
        }
    };

    let metadata = match RequestMetadata::validate_parts(&parts) {
        Ok(metadata) => metadata,
        Err(_) => {
            drop(body);
            telemetry.reject(RejectionReason::InvalidHeaders);
            return finalize_and_track_response(
                invalid_request_target(),
                &response_semantics,
                Some(active_request),
                http1_activity,
                body_idle_timeout,
                &telemetry,
            );
        }
    };

    if let Err(rejection) = context
        .config
        .request_metadata
        .admit_parts(&parts, metadata)
    {
        drop(body);
        telemetry.reject(RejectionReason::InvalidHeaders);
        return finalize_and_track_response(
            reject_request_metadata(rejection),
            &response_semantics,
            Some(active_request),
            http1_activity,
            body_idle_timeout,
            &telemetry,
        );
    }

    let response = if let Some(native) = metadata
        .resource_path(&parts.uri)
        .and_then(|path| context.config.routes.route(path, &parts.method))
    {
        drop(body);
        match native {
            NativeMatch::File(plan) => {
                telemetry.set_destination(Destination::NativeFile);
                let (response, failure) = context
                    .config
                    .files
                    .serve(
                        plan,
                        parts.method,
                        parts.headers,
                        Arc::clone(&active_request),
                    )
                    .await;
                record_file_failure(&telemetry, failure);
                response
            }
            NativeMatch::Probe(response) => {
                telemetry.set_destination(Destination::NativeProbe);
                response
            }
            NativeMatch::Metrics => {
                telemetry.set_destination(Destination::NativeMetrics);
                context.telemetry.metrics_response(&parts.method)
            }
        }
    } else if !request_headers_are_utf8(&parts.headers) {
        drop(body);
        telemetry.reject(RejectionReason::InvalidHeaders);
        invalid_request_headers()
    } else {
        let declared_length = content_length(&parts.headers);
        if declared_length.is_some_and(|length| length > context.config.body_max_bytes) {
            drop(body);
            telemetry.reject(RejectionReason::BodyTooLarge);
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
                context.config.body_sinks.clone(),
                context.shutdown.clone(),
            );
            let body_handle = registration.handle;
            let body_pump = registration.pump;
            let chunk_bytes = context.config.body_chunk_bytes;
            let body_idle_timeout = context.config.body_idle_timeout;
            tokio::spawn(async move { body_pump.run(body, chunk_bytes, body_idle_timeout).await });

            let (completion, receiver) = oneshot::channel();
            let body_limit = context.config.body_max_bytes;
            let roc_context = Arc::clone(&context.roc_context);
            let handler_request = Arc::clone(&active_request);
            let handler_response_semantics = response_semantics.clone();
            let handler_telemetry = telemetry.clone();
            let admission_metrics = context.telemetry.metrics();
            let admission = context.roc_executor.try_submit(|class| RocScheduledJob {
                admission: RocJobAdmission::new(class, admission_metrics),
                job: RocJob::Ordinary(OrdinaryRocJob {
                    parts,
                    metadata,
                    body_handle,
                    body_limit,
                    declared_length,
                    roc_context,
                    accepted_encodings,
                    response_semantics: handler_response_semantics,
                    active_request: handler_request,
                    telemetry: handler_telemetry,
                    completion,
                }),
            });
            let handled = match admission {
                Err(SubmitError::Full) => Err(RocDispatchError::Admission(AdmissionError::Full)),
                Err(SubmitError::Stopping) => {
                    Err(RocDispatchError::Admission(AdmissionError::Stopping))
                }
                Ok(admission) => {
                    telemetry.set_destination(Destination::Roc);
                    let mut receiver = receiver;
                    let mut queued = (admission.class == AdmissionClass::Queued).then(|| {
                        QueuedRocJobGuard::new(context.roc_executor.clone(), admission.ticket)
                    });
                    let received = if let Some(queued) = &mut queued {
                        match tokio::time::timeout(
                            context.config.handler_queue_timeout,
                            &mut receiver,
                        )
                        .await
                        {
                            Ok(received) => received,
                            Err(_) => {
                                if queued.cancel() {
                                    telemetry.reject(RejectionReason::HandlerOverload);
                                    return finalize_and_track_response(
                                        handler_queue_timed_out(),
                                        &response_semantics,
                                        Some(active_request),
                                        http1_activity,
                                        Some(body_idle_timeout),
                                        &telemetry,
                                    );
                                }
                                receiver.await
                            }
                        }
                    } else {
                        receiver.await
                    };
                    if let Some(queued) = &mut queued {
                        queued.disarm();
                    }
                    match received {
                        Ok(Ok(outcome)) => Ok(outcome),
                        Ok(Err(error)) => Err(RocDispatchError::Execution(error)),
                        Err(_) => Err(RocDispatchError::CompletionLost),
                    }
                }
            };

            match handled {
                Err(RocDispatchError::Admission(AdmissionError::Full)) => {
                    telemetry.reject(RejectionReason::HandlerOverload);
                    overloaded()
                }
                Err(RocDispatchError::Admission(AdmissionError::Stopping)) => {
                    telemetry.reject(RejectionReason::Shutdown);
                    service_unavailable()
                }
                Err(RocDispatchError::Execution(RocExecutionError::Panic)) => {
                    telemetry.reject(RejectionReason::RocPanic);
                    eprintln!("Recovered from calling Roc");
                    safe_internal_server_error(&response_semantics)
                }
                Err(RocDispatchError::CompletionLost) => {
                    telemetry.reject(RejectionReason::HostPanic);
                    eprintln!("Roc executor lost a completion");
                    safe_internal_server_error(&response_semantics)
                }
                Ok(RocOutcome::Ordinary(response, stop_code)) => {
                    request_stop_after(&context.shutdown, stop_code);
                    match response {
                        Ok(response) => response,
                        Err(error) => {
                            telemetry.reject(RejectionReason::InvalidRocResponse);
                            eprintln!("Invalid Roc response: {error}");
                            safe_internal_server_error(&response_semantics)
                        }
                    }
                }
                Ok(RocOutcome::File(plan)) => {
                    telemetry.set_destination(Destination::NativeFile);
                    let (response, failure) = context
                        .config
                        .files
                        .serve(plan, file_method, file_headers, Arc::clone(&active_request))
                        .await;
                    record_file_failure(&telemetry, failure);
                    response
                }
                Ok(RocOutcome::Stream { source, coding }) => {
                    if coding == StreamingContentCoding::NotAcceptable {
                        no_acceptable_sse_content_coding()
                    } else {
                        match Arc::clone(&context.stream_slots).try_acquire_owned() {
                            Ok(stream_slot) => {
                                let lane = if coding == StreamingContentCoding::Brotli {
                                    match context.brotli.try_admit(BrotliProfile::Scale) {
                                        Some(lane) => Some(lane),
                                        None => {
                                            telemetry.reject(RejectionReason::HandlerOverload);
                                            return finalize_and_track_response(
                                                overloaded(),
                                                &response_semantics,
                                                Some(active_request),
                                                http1_activity,
                                                Some(body_idle_timeout),
                                                &telemetry,
                                            );
                                        }
                                    }
                                } else {
                                    None
                                };
                                let source = RocSseItemSource::new(
                                    source,
                                    context.roc_executor.clone(),
                                    context.telemetry.metrics(),
                                    context.config.handler_queue_timeout,
                                    Arc::clone(&active_request),
                                    stream_slot,
                                );
                                match source.precommit(context.config.max_sse_event_bytes).await {
                                    Ok(source) => sse_response(
                                        source,
                                        context.config.max_sse_event_bytes,
                                        lane,
                                    ),
                                    Err(error) => {
                                        drop(lane);
                                        match &error {
                                            SseTransitionError::Admission(AdmissionError::Full)
                                            | SseTransitionError::QueueTimedOut => {
                                                telemetry.reject(RejectionReason::HandlerOverload);
                                                overloaded()
                                            }
                                            SseTransitionError::Admission(
                                                AdmissionError::Stopping,
                                            ) => {
                                                telemetry.reject(RejectionReason::Shutdown);
                                                service_unavailable()
                                            }
                                            SseTransitionError::Panic => {
                                                telemetry.reject(RejectionReason::RocPanic);
                                                eprintln!(
                                                    "Roc SSE transition panicked before response commitment"
                                                );
                                                safe_internal_server_error(&response_semantics)
                                            }
                                            SseTransitionError::Application(_)
                                            | SseTransitionError::Oversized { .. } => {
                                                telemetry
                                                    .reject(RejectionReason::InvalidRocResponse);
                                                eprintln!(
                                                    "Roc SSE source failed before response commitment: {error}"
                                                );
                                                safe_internal_server_error(&response_semantics)
                                            }
                                        }
                                    }
                                }
                            }
                            Err(_) => {
                                telemetry.reject(RejectionReason::HandlerOverload);
                                overloaded()
                            }
                        }
                    }
                }
                Ok(RocOutcome::Invalid(detail)) => {
                    telemetry.reject(RejectionReason::InvalidRocResponse);
                    eprintln!("Invalid Roc response plan: {detail}");
                    safe_internal_server_error(&response_semantics)
                }
            }
        }
    };

    finalize_and_track_response(
        response,
        &response_semantics,
        Some(active_request),
        http1_activity,
        body_idle_timeout,
        &telemetry,
    )
}

fn record_file_failure(
    telemetry: &crate::telemetry::RequestTelemetry,
    failure: Option<FileServeFailure>,
) {
    match failure {
        Some(FileServeFailure::Overloaded) => {
            telemetry.reject_for_destination(Destination::NativeFile, RejectionReason::FileOverload)
        }
        Some(FileServeFailure::InvalidPlan) => telemetry
            .reject_for_destination(Destination::NativeFile, RejectionReason::InvalidRocResponse),
        Some(FileServeFailure::StartFailed) => {
            telemetry.reject_for_destination(Destination::NativeFile, RejectionReason::FileFailure)
        }
        None => {}
    }
}

async fn handle_panics(
    future: impl Future<Output = ServerResponse>,
    response_semantics: RequestSemantics,
    http1_activity: Option<Http1Activity>,
    body_idle_timeout: Option<Duration>,
    telemetry: crate::telemetry::RequestTelemetry,
) -> Result<ServerResponse, Infallible> {
    let response = match AssertUnwindSafe(future).catch_unwind().await {
        Ok(response) => response,
        Err(_) => {
            telemetry.reject(RejectionReason::HostPanic);
            finalize_and_track_response(
                safe_internal_server_error(&response_semantics),
                &response_semantics,
                None,
                http1_activity,
                body_idle_timeout,
                &telemetry,
            )
        }
    };
    Ok(telemetry.instrument(response))
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
    let mut builder = hyper::server::conn::http1::Builder::new();
    builder
        .max_headers(context.config.request_metadata.max_header_fields())
        .max_buf_size(HTTP1_MAX_HEAD_BYTES);
    let connection = builder.serve_connection(
        io,
        hyper::service::service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
            service_activity.request_started();
            let telemetry = service_context
                .telemetry
                .start_request(request.method(), request.uri().path());
            let response_semantics = RequestSemantics::from_request(&request);
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
                    response_semantics.clone(),
                    telemetry.clone(),
                ),
                response_semantics,
                Some(service_activity.clone()),
                Some(service_context.config.response_idle_timeout),
                telemetry,
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
    mut responder: h2::server::SendResponse<ServerData>,
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
                if !data.has_remaining() {
                    continue;
                }
                if data.is_pooled() {
                    // A pooled frame must stay one owned value so its Drop can
                    // return the vector exactly once. Wait for positive flow
                    // capacity, then let h2 consume the remainder incrementally.
                    // The frame pool and h2's configured send-buffer ceiling
                    // bound the bytes retained beyond the current grant.
                    sender.reserve_capacity(data.remaining());
                    match tokio::time::timeout_at(
                        deadline,
                        futures::future::poll_fn(|context| sender.poll_capacity(context)),
                    )
                    .await
                    {
                        Ok(Some(Ok(capacity))) if capacity > 0 => {}
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
                    }
                    let end_stream = body.is_end_stream();
                    sender
                        .send_data(data, end_stream)
                        .map_err(|error| error.to_string())?;
                    deadline = tokio::time::Instant::now() + idle_timeout;
                    if end_stream {
                        return Ok(());
                    }
                    continue;
                }
                while data.has_remaining() {
                    sender.reserve_capacity(data.remaining());
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
                    let count = capacity.min(data.remaining());
                    let chunk = data.split_bytes_to(count);
                    let end_stream = !data.has_remaining() && body.is_end_stream();
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
                    .send_data(ServerData::empty(), true)
                    .map_err(|error| error.to_string())?;
                return Ok(());
            }
        }
    }
}

fn spawn_h2_request(
    tasks: &mut JoinSet<()>,
    request: hyper::Request<h2::RecvStream>,
    responder: h2::server::SendResponse<ServerData>,
    context: ServerContext,
) {
    tasks.spawn(async move {
        let telemetry = context
            .telemetry
            .start_request(request.method(), request.uri().path());
        let response_semantics = RequestSemantics::from_request(&request);
        let (parts, body) = request.into_parts();
        let response = handle_panics(
            handle_req(
                parts,
                h2_request_body(body),
                context.clone(),
                None,
                response_semantics.clone(),
                telemetry.clone(),
            ),
            response_semantics,
            None,
            None,
            telemetry,
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
        .max_header_list_size(context.config.request_metadata.http2_max_header_list_size())
        // The response sender reserves exact flow-control capacity before
        // handing bytes to h2; one 64 KiB flow-control grant is sufficient.
        .max_send_buffer_size(64 * 1024);
    let handshake = builder.handshake::<_, ServerData>(stream);
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
    let _connection_metrics = context.telemetry.connection_started();
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

        // A synchronous Roc invocation already running on the fixed executor
        // cannot be safely preempted. Running the shutdown hook or dropping
        // the context while one may still use it would be unsound, so the
        // configured drain deadline is a hard process deadline and
        // intentionally skips application shutdown cleanup.
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
    debug_assert_eq!(
        context.config.body_sinks.active_sinks(),
        0,
        "all request-body sinks must drain before shutdown"
    );
    if context.config.body_sinks.high_water_sinks() > 0 {
        eprintln!(
            "Request-body sink high-water mark: {}",
            context.config.body_sinks.high_water_sinks()
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
    use crate::response_body::{ResponseFramePool, SseBody, SseItemSource};
    use std::io::Read;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn initialize_test_host() {
        crate::abi::initialize_test_roc_host();
    }

    fn no_compression() -> AcceptedEncodings {
        AcceptedEncodings::from_headers(&hyper::HeaderMap::new())
    }

    fn get_http1_semantics() -> RequestSemantics {
        RequestSemantics {
            method: hyper::Method::GET,
            version: hyper::Version::HTTP_11,
        }
    }

    fn ordinary_response(
        body: RocListWith<u8, false>,
        status: u16,
        stop: bool,
        exit_code: i64,
    ) -> ServerOrdinaryResponse {
        ServerOrdinaryResponse {
            exit_code,
            body,
            headers: RocList::empty(),
            status,
            stop,
        }
    }

    #[cfg(not(target_pointer_width = "32"))]
    fn ordinary_outcome(response: ServerOrdinaryResponse) -> RocServerResponse {
        RocServerResponse {
            payload: InternalServerOutcomeToHostPayload {
                ordinary: core::mem::ManuallyDrop::new(response),
            },
            tag: ServerResponseTag::Ordinary,
        }
    }

    struct OneShotSseSource {
        item: Option<Bytes>,
        cancellations: Arc<AtomicUsize>,
    }

    impl SseItemSource for OneShotSseSource {
        fn poll_item(mut self: Pin<&mut Self>, _context: &mut Context<'_>) -> SseSourcePoll {
            match self.item.take() {
                Some(item) => SseSourcePoll::Item(SseItem::new(item)),
                None => SseSourcePoll::End,
            }
        }

        fn item_drained(self: Pin<&mut Self>) {}

        fn cancel(self: Pin<&mut Self>) {
            self.cancellations.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn one_shot_sse_source(item: Bytes) -> (Arc<AtomicUsize>, OneShotSseSource) {
        let cancellations = Arc::new(AtomicUsize::new(0));
        (
            Arc::clone(&cancellations),
            OneShotSseSource {
                item: Some(item),
                cancellations,
            },
        )
    }

    fn decode_brotli(input: &[u8]) -> Vec<u8> {
        let mut decoded = Vec::new();
        brotli::Decompressor::new(input, 4096)
            .read_to_end(&mut decoded)
            .expect("normally finished Brotli stream should decode");
        decoded
    }

    fn large_sse_item() -> Bytes {
        Bytes::from(
            [
                b"event: datastar-patch-elements\n".as_slice(),
                b"data: selector #todos\n",
                b"data: elements <ul>",
                "<li>bounded listener transaction</li>"
                    .repeat(2048)
                    .as_bytes(),
                b"</ul>\n\n",
            ]
            .concat(),
        )
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

    #[tokio::test]
    async fn request_metadata_and_escaped_response_body_share_hyper_storage() {
        initialize_test_host();

        let request = hyper::Request::builder()
            .method("PROPFIND")
            .uri("/a/long/request/target?with=a-query")
            .header(hyper::header::HOST, "metadata.example:8443")
            .header("x-long-request-header", "a sufficiently long header value")
            .body(())
            .unwrap();
        let metadata = RequestMetadata::validate(&request).unwrap();
        let original_target_ptr = request.uri().path_and_query().unwrap().as_str().as_ptr();
        let original_query_ptr = request.uri().query().unwrap().as_ptr();
        let original_authority_ptr = request
            .headers()
            .get(hyper::header::HOST)
            .unwrap()
            .as_bytes()
            .as_ptr();
        let original_headers: Vec<(*const u8, *const u8)> = request
            .headers()
            .iter()
            .map(|(name, value)| (name.as_str().as_ptr(), value.as_bytes().as_ptr()))
            .collect();
        let (parts, _) = request.into_parts();

        let roc_request = request_to_roc(parts, metadata, core::ptr::null_mut(), 4096, None);
        assert_eq!(crate::request_parts::active_backings(), 1);
        assert!(roc_request.target_path.is_seamless_slice());
        assert_eq!(roc_request.target_path.as_u8_ptr(), original_target_ptr);
        assert!(roc_request.target_query.is_seamless_slice());
        assert_eq!(roc_request.target_query.as_u8_ptr(), original_query_ptr);
        assert!(roc_request.authority_host.is_seamless_slice());
        assert_eq!(
            roc_request.authority_host.as_u8_ptr(),
            original_authority_ptr
        );
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
                roc_request.target_path.capacity_or_alloc_ptr
            );
            assert_eq!(
                header.value.capacity_or_alloc_ptr,
                roc_request.target_path.capacity_or_alloc_ptr
            );
        }

        // Model Roc returning `Str.to_utf8(resource.raw_path)`: the output list
        // owns one additional reference to the same request-parts backing.
        let target = roc_request.target_path;
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

        let roc_response = ordinary_response(escaped_body, 200, false, 0);
        let response = response_to_hyper(
            RocResponseOwner {
                response: roc_response,
            },
            no_compression(),
            &get_http1_semantics(),
        )
        .unwrap();
        assert_eq!(crate::request_parts::active_backings(), 1);

        let body = response
            .into_body()
            .frame()
            .await
            .unwrap()
            .unwrap()
            .into_data()
            .unwrap()
            .into_bytes()
            .expect("an ordinary Roc response retains its Bytes body");
        assert_eq!(body.as_ptr(), escaped_ptr);
        assert_eq!(body.as_ref(), b"/a/long/request/target");
        assert_eq!(crate::request_parts::active_backings(), 1);
        drop(body);
        assert_eq!(
            crate::request_parts::active_backings(),
            0,
            "Hyper's final Bytes drop must release the escaped Roc slice"
        );
    }

    #[test]
    fn asterisk_request_without_metadata_has_no_seamless_fields() {
        initialize_test_host();
        let request = hyper::Request::builder()
            .method(hyper::Method::OPTIONS)
            .uri("*")
            .version(hyper::Version::HTTP_10)
            .body(())
            .unwrap();
        let metadata = RequestMetadata::validate(&request).unwrap();
        let (parts, _) = request.into_parts();

        let roc_request = request_to_roc(parts, metadata, core::ptr::null_mut(), 4096, None);

        assert_eq!(roc_request.target_tag, 2);
        assert!(roc_request.headers.is_empty());
        assert!(!roc_request.method_ext.is_seamless_slice());
        assert!(!roc_request.target_path.is_seamless_slice());
        assert!(!roc_request.target_query.is_seamless_slice());
        assert!(!roc_request.target_authority_host.is_seamless_slice());
        assert!(!roc_request.authority_host.is_seamless_slice());
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
        let response = ordinary_response(
            crate::request_body::seamless_chunk_for_test(bytes),
            200,
            false,
            0,
        );

        let response = response_to_hyper(
            RocResponseOwner { response },
            no_compression(),
            &get_http1_semantics(),
        )
        .unwrap();
        assert_eq!(drops.load(Ordering::Acquire), 0);
        let transmitted = response
            .into_body()
            .frame()
            .await
            .unwrap()
            .unwrap()
            .into_data()
            .unwrap()
            .into_bytes()
            .expect("an ordinary Roc response retains its Bytes body");
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
        let response = ordinary_response(
            unsafe { RocListWith::<u8, false>::from_slice(&original, roc_host()) },
            200,
            false,
            0,
        );
        let mut request_headers = hyper::HeaderMap::new();
        request_headers.insert(
            hyper::header::ACCEPT_ENCODING,
            "gzip, br, zstd".parse().unwrap(),
        );

        let response = response_to_hyper(
            RocResponseOwner { response },
            AcceptedEncodings::from_headers(&request_headers),
            &get_http1_semantics(),
        )
        .unwrap();
        let response = finalize_response(response, &get_http1_semantics()).unwrap();
        assert_eq!(response.headers()[hyper::header::CONTENT_ENCODING], "zstd");
        assert_eq!(response.headers()[hyper::header::VARY], "Accept-Encoding");
        let transmitted_length = response.headers()[CONTENT_LENGTH]
            .to_str()
            .unwrap()
            .parse::<usize>()
            .unwrap();
        let encoded = response.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(encoded.len(), transmitted_length);
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
        let pending_frames =
            futures::stream::pending::<Result<Frame<ServerData>, std::io::Error>>();
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
    fn invalid_stop_after_keeps_its_shutdown_intent_and_uses_normal_validation() {
        initialize_test_host();
        let response = ordinary_outcome(ordinary_response(
            unsafe { RocListWith::<u8, false>::from_slice(b"not allowed", roc_host()) },
            204,
            true,
            17,
        ));

        let RocOutcome::Ordinary(response, stop_code) =
            outcome_from_roc(response, no_compression(), &get_http1_semantics())
        else {
            panic!("StopAfter must remain an ordinary response");
        };
        assert_eq!(stop_code, Some(17));
        assert_eq!(
            response.unwrap_err().to_string(),
            "status 204 No Content forbids response content"
        );

        let shutdown = ShutdownController::new();
        request_stop_after(&shutdown, stop_code);
        assert_eq!(
            shutdown.reason(),
            Some(ShutdownReason::ApplicationRequested { exit_code: 17 })
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

    #[test]
    fn reusable_sse_completion_tracks_queue_promotion_and_cancel() {
        let slot = SseCompletionSlot::new();
        let mut context = Context::from_waker(futures::task::noop_waker_ref());

        assert!(matches!(slot.poll(&mut context), SseCompletionPoll::Idle));
        slot.begin();
        slot.mark_queued();
        assert!(matches!(slot.poll(&mut context), SseCompletionPoll::Queued));
        assert!(slot.start_running(true));
        assert!(matches!(slot.poll(&mut context), SseCompletionPoll::Active));
        slot.cancel();
        assert!(matches!(
            slot.poll(&mut context),
            SseCompletionPoll::Cancelled
        ));
    }

    #[test]
    fn cancelled_queued_sse_completion_cannot_start() {
        let slot = SseCompletionSlot::new();
        slot.begin();
        slot.mark_queued();
        slot.cancel();
        assert!(!slot.start_running(true));
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
    fn metadata_limit_responses_are_protocol_neutral() {
        let target = request_target_too_long(64);
        assert_eq!(target.status(), hyper::StatusCode::URI_TOO_LONG);
        assert!(!target.headers().contains_key(hyper::header::CONNECTION));

        let headers = request_headers_too_large(256, 4);
        assert_eq!(
            headers.status(),
            hyper::StatusCode::REQUEST_HEADER_FIELDS_TOO_LARGE
        );
        assert!(!headers.headers().contains_key(hyper::header::CONNECTION));
    }

    #[test]
    fn http2_stream_limit_reserves_bounded_native_probe_headroom() {
        let metrics = Metrics::new();
        let files = FileService::activate(Vec::new(), 1, 1024, Arc::clone(&metrics)).unwrap();
        let routes =
            NativeRouter::activate(&files, Vec::new(), Vec::new(), Vec::new(), None).unwrap();
        let config = RuntimeConfig {
            host: "127.0.0.1".to_owned(),
            port: 8000,
            max_connections: 256,
            max_handlers: 32,
            max_queued_handlers: 64,
            max_sse_streams: 256,
            max_sse_event_bytes: 1024 * 1024,
            request_metadata: RequestMetadataLimits::new(8192, 32 * 1024, 100).unwrap(),
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
            body_sinks: BodySinkService::activate(Vec::new(), 1, Duration::from_secs(30)).unwrap(),
            telemetry: TelemetryConfig { access_log: None },
            metrics,
        };
        assert_eq!(config.max_http2_streams_per_connection(), 98);
    }

    #[tokio::test]
    async fn stalled_http2_response_resets_only_its_stream() {
        let (client_io, server_io) = tokio::io::duplex(4096);
        let server = tokio::spawn(async move {
            let mut connection = h2::server::Builder::new()
                .handshake::<_, ServerData>(server_io)
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
    async fn pooled_http2_frame_survives_incremental_flow_control_and_returns_its_slot() {
        let pool = ResponseFramePool::new(1, 4096);
        let payload = (0..4096)
            .map(|index| (index % 251) as u8)
            .collect::<Vec<_>>();
        let mut reservation = futures::future::poll_fn(|context| pool.poll_reserve(context)).await;
        reservation.output_mut().copy_from_slice(&payload);
        let body = Full::new(ServerData::from(reservation.commit(payload.len())))
            .map_err(|never| match never {})
            .boxed_unsync();
        let response = hyper::Response::new(body);
        assert_eq!(pool.stats().in_use_slots, 1);

        let (client_io, server_io) = tokio::io::duplex(4096);
        let server = tokio::spawn(async move {
            let mut connection = h2::server::Builder::new()
                .handshake::<_, ServerData>(server_io)
                .await
                .expect("HTTP/2 server handshake should succeed");
            let (_, responder) = connection
                .accept()
                .await
                .expect("client should open one stream")
                .expect("request should be valid");
            let mut response_task = Box::pin(send_h2_response(
                responder,
                response,
                Duration::from_secs(1),
            ));
            let response_result = loop {
                tokio::select! {
                    result = &mut response_task => break result,
                    accepted = connection.accept() => {
                        assert!(
                            accepted.is_some(),
                            "client connection should remain open while the response is active"
                        );
                    }
                }
            };

            // Keep driving h2 until the client has consumed the queued frame
            // and closed the connection. That is when h2 releases its Buf.
            while connection.accept().await.is_some() {}
            response_result
        });

        let mut builder = h2::client::Builder::new();
        builder.initial_window_size(7);
        let (mut sender, connection) = builder
            .handshake::<_, Bytes>(client_io)
            .await
            .expect("HTTP/2 client handshake should succeed");
        let client = tokio::spawn(connection);
        sender = sender.ready().await.expect("client should become ready");
        let (response, _) = sender
            .send_request(hyper::Request::new(()), true)
            .expect("request should be accepted");
        let mut body = response
            .await
            .expect("response headers should arrive")
            .into_body();
        let mut received = Vec::with_capacity(payload.len());
        while let Some(data) = body.data().await {
            let data = data.expect("pooled response stream should remain healthy");
            received.extend_from_slice(&data);
            body.flow_control()
                .release_capacity(data.len())
                .expect("client flow-control capacity should be released");
        }
        assert_eq!(received, payload);

        drop(body);
        drop(sender);
        client.abort();
        server
            .await
            .expect("server task should not panic")
            .expect("pooled response should complete");
        assert_eq!(pool.stats().in_use_slots, 0);
        assert_eq!(pool.stats().free_slots, 1);
    }

    #[tokio::test]
    async fn bounded_brotli_sse_finishes_through_the_real_http1_path() {
        let payload = large_sse_item();
        let (cancellations, source) = one_shot_sse_source(payload.clone());
        let executor = BrotliExecutor::new(2, 1).unwrap();
        let lane = executor.try_admit(BrotliProfile::Compression).unwrap();
        let (handle, body) = SseBody::new_bounded_brotli(source, 128 * 1024, 1, 7, lane);
        let mut response = hyper::Response::new(body.boxed_unsync());
        response
            .headers_mut()
            .insert("content-type", "text/event-stream".parse().unwrap());
        response
            .headers_mut()
            .insert("content-encoding", "br".parse().unwrap());
        let response = finalize_response(response, &get_http1_semantics()).unwrap();
        let response = Arc::new(std::sync::Mutex::new(Some(response)));

        let (client_io, server_io) = tokio::io::duplex(4096);
        let server = tokio::spawn(async move {
            let service_response = Arc::clone(&response);
            let service = hyper::service::service_fn(move |_request| {
                let response = service_response
                    .lock()
                    .expect("test response mutex poisoned")
                    .take()
                    .expect("test serves exactly one response");
                async move { Ok::<_, Infallible>(response) }
            });
            hyper::server::conn::http1::Builder::new()
                .serve_connection(TokioIo::new(server_io), service)
                .await
                .expect("HTTP/1.1 server connection should succeed");
        });

        let (mut sender, connection) =
            hyper::client::conn::http1::handshake(TokioIo::new(client_io))
                .await
                .expect("HTTP/1.1 client handshake should succeed");
        let client = tokio::spawn(connection);
        let response = sender
            .send_request(hyper::Request::new(Full::new(Bytes::new())))
            .await
            .expect("HTTP/1.1 SSE request should succeed");
        assert_eq!(response.headers()["content-encoding"], "br");
        let encoded = response
            .into_body()
            .collect()
            .await
            .expect("HTTP/1.1 SSE body should succeed")
            .to_bytes();
        assert_eq!(decode_brotli(&encoded), payload);

        drop(sender);
        client.await.expect("client task should not panic").unwrap();
        server.await.expect("server task should not panic");
        assert_eq!(cancellations.load(Ordering::Relaxed), 0);
        assert!(handle.stats().finished);
        assert_eq!(handle.stats().frames.in_use_slots, 0);
        assert_eq!(handle.stats().frames.high_water_slots, 1);
        assert_eq!(executor.stats().active_lanes, 0);
        assert_eq!(executor.stats().lane_high_water, 1);
    }

    #[tokio::test]
    async fn bounded_brotli_sse_finishes_through_incremental_http2_flow_control() {
        let payload = large_sse_item();
        let (cancellations, source) = one_shot_sse_source(payload.clone());
        let executor = BrotliExecutor::new(2, 1).unwrap();
        let lane = executor.try_admit(BrotliProfile::Compression).unwrap();
        let (handle, body) = SseBody::new_bounded_brotli(source, 128 * 1024, 1, 7, lane);
        let mut response = hyper::Response::new(body.boxed_unsync());
        response
            .headers_mut()
            .insert("content-type", "text/event-stream".parse().unwrap());
        response
            .headers_mut()
            .insert("content-encoding", "br".parse().unwrap());
        let response = finalize_response(
            response,
            &RequestSemantics {
                method: hyper::Method::GET,
                version: hyper::Version::HTTP_2,
            },
        )
        .unwrap();

        let (client_io, server_io) = tokio::io::duplex(4096);
        let server = tokio::spawn(async move {
            let mut connection = h2::server::Builder::new()
                .handshake::<_, ServerData>(server_io)
                .await
                .expect("HTTP/2 server handshake should succeed");
            let (_, responder) = connection
                .accept()
                .await
                .expect("client should open one stream")
                .expect("request should be valid");
            let mut response_task = Box::pin(send_h2_response(
                responder,
                response,
                Duration::from_secs(1),
            ));
            let response_result = loop {
                tokio::select! {
                    result = &mut response_task => break result,
                    accepted = connection.accept() => {
                        assert!(accepted.is_some(), "client must stay open during response");
                    }
                }
            };
            while connection.accept().await.is_some() {}
            response_result
        });

        let mut builder = h2::client::Builder::new();
        builder.initial_window_size(7);
        let (mut sender, connection) = builder
            .handshake::<_, Bytes>(client_io)
            .await
            .expect("HTTP/2 client handshake should succeed");
        let client = tokio::spawn(connection);
        sender = sender.ready().await.expect("client should become ready");
        let (response, _) = sender
            .send_request(hyper::Request::new(()), true)
            .expect("request should be accepted");
        let response = response.await.expect("response headers should arrive");
        assert_eq!(response.headers()["content-encoding"], "br");
        let mut body = response.into_body();
        let mut encoded = Vec::new();
        while let Some(data) = body.data().await {
            let data = data.expect("SSE response stream should remain healthy");
            encoded.extend_from_slice(&data);
            body.flow_control()
                .release_capacity(data.len())
                .expect("client flow-control capacity should be released");
        }
        assert_eq!(decode_brotli(&encoded), payload);

        drop(body);
        drop(sender);
        client.abort();
        server
            .await
            .expect("server task should not panic")
            .expect("SSE response should complete");
        assert_eq!(cancellations.load(Ordering::Relaxed), 0);
        assert!(handle.stats().finished);
        assert_eq!(handle.stats().frames.in_use_slots, 0);
        assert_eq!(handle.stats().frames.high_water_slots, 1);
        assert_eq!(executor.stats().active_lanes, 0);
        assert_eq!(executor.stats().available_lanes, 1);
    }

    #[tokio::test]
    async fn stalled_http2_sse_reader_aborts_without_finish_and_releases_everything() {
        let payload = large_sse_item();
        let (cancellations, source) = one_shot_sse_source(payload);
        let executor = BrotliExecutor::new(2, 1).unwrap();
        let lane = executor.try_admit(BrotliProfile::Compression).unwrap();
        let (handle, body) = SseBody::new_bounded_brotli(source, 128 * 1024, 1, 7, lane);
        let response = hyper::Response::new(body.boxed_unsync());

        let (client_io, server_io) = tokio::io::duplex(4096);
        let server = tokio::spawn(async move {
            let mut connection = h2::server::Builder::new()
                .handshake::<_, ServerData>(server_io)
                .await
                .expect("HTTP/2 server handshake should succeed");
            let (_, responder) = connection
                .accept()
                .await
                .expect("client should open one stream")
                .expect("request should be valid");
            let mut response_task = Box::pin(send_h2_response(
                responder,
                response,
                Duration::from_millis(30),
            ));
            let result = loop {
                tokio::select! {
                    result = &mut response_task => break result,
                    accepted = connection.accept() => {
                        assert!(accepted.is_some(), "client must stay open during response");
                    }
                }
            };
            let _ = tokio::time::timeout(Duration::from_millis(10), connection.accept()).await;
            result
        });

        let mut builder = h2::client::Builder::new();
        builder.initial_window_size(7);
        let (mut sender, connection) = builder
            .handshake::<_, Bytes>(client_io)
            .await
            .expect("HTTP/2 client handshake should succeed");
        let client = tokio::spawn(connection);
        sender = sender.ready().await.expect("client should become ready");
        let (response, _) = sender
            .send_request(hyper::Request::new(()), true)
            .expect("request should be accepted");
        let body = response
            .await
            .expect("response headers should arrive")
            .into_body();

        assert!(server.await.expect("server task should not panic").is_err());
        assert_eq!(cancellations.load(Ordering::Relaxed), 1);
        let stats = handle.stats();
        assert!(stats.cancelled);
        assert!(!stats.finished);
        assert!(!stats.active_encoder);
        assert_eq!(stats.pending_item_bytes, 0);
        assert_eq!(stats.frames.in_use_slots, 0);
        assert_eq!(stats.frames.free_slots, 1);
        assert_eq!(stats.frames.high_water_slots, 1);
        let deadline = std::time::Instant::now() + Duration::from_secs(5);
        while executor.stats().available_lanes != 1 && std::time::Instant::now() < deadline {
            std::thread::yield_now();
        }
        assert_eq!(executor.stats().active_lanes, 0);
        assert_eq!(executor.stats().available_lanes, 1);

        drop(body);
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
