//! Bounded host-owned request completion telemetry and operational metrics.
//!
//! A request remains active until its response body reaches end-of-stream,
//! fails, or is dropped. The body wrapper below is the single terminal-event
//! boundary for Roc responses, native responses, and host rejections.

#[cfg(test)]
use crate::response::empty_body;
use crate::response::{full_body, ServerBody, ServerResponse};
use bytes::Bytes;
use http_body_util::BodyExt;
use hyper::body::{Body, Frame, SizeHint};
use hyper::header::{HeaderValue, CACHE_CONTROL, CONTENT_LENGTH, CONTENT_TYPE};
use hyper::{Method, StatusCode};
use serde::Serialize;
use std::fmt::Write as _;
use std::io::{self, BufWriter, Write as _};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::task::{Context, Poll};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const MAX_LOGGED_PATH_BYTES: usize = 2 * 1024;
const ACCESS_LOG_DRAIN_TIMEOUT: Duration = Duration::from_secs(1);
const OPENMETRICS_CONTENT_TYPE: &str = "application/openmetrics-text; version=1.0.0; charset=utf-8";
const DURATION_BUCKETS_SECONDS: [f64; 14] = [
    0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0,
];
const DURATION_BUCKETS_MICROS: [u64; 14] = [
    5_000, 10_000, 25_000, 50_000, 75_000, 100_000, 250_000, 500_000, 750_000, 1_000_000,
    2_500_000, 5_000_000, 7_500_000, 10_000_000,
];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum LogTarget {
    None,
    PathWithoutQuery,
}

#[derive(Clone, Debug)]
pub(crate) struct TelemetryConfig {
    pub(crate) access_log: Option<AccessLogConfig>,
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct AccessLogConfig {
    pub(crate) target: LogTarget,
    pub(crate) buffer_events: usize,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Destination {
    Roc,
    NativeFile,
    NativeProbe,
    NativeMetrics,
    HostRejection,
}

impl Destination {
    const COUNT: usize = 5;

    fn index(self) -> usize {
        match self {
            Self::Roc => 0,
            Self::NativeFile => 1,
            Self::NativeProbe => 2,
            Self::NativeMetrics => 3,
            Self::HostRejection => 4,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Roc => "roc",
            Self::NativeFile => "native_file",
            Self::NativeProbe => "native_probe",
            Self::NativeMetrics => "native_metrics",
            Self::HostRejection => "host_rejection",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum RejectionReason {
    Shutdown,
    InvalidHeaders,
    BodyTooLarge,
    HandlerOverload,
    FileOverload,
    InvalidRocResponse,
    RocPanic,
    HostPanic,
    FileFailure,
}

impl RejectionReason {
    const COUNT: usize = 9;
    const ALL: [Self; Self::COUNT] = [
        Self::Shutdown,
        Self::InvalidHeaders,
        Self::BodyTooLarge,
        Self::HandlerOverload,
        Self::FileOverload,
        Self::InvalidRocResponse,
        Self::RocPanic,
        Self::HostPanic,
        Self::FileFailure,
    ];

    fn index(self) -> usize {
        match self {
            Self::Shutdown => 0,
            Self::InvalidHeaders => 1,
            Self::BodyTooLarge => 2,
            Self::HandlerOverload => 3,
            Self::FileOverload => 4,
            Self::InvalidRocResponse => 5,
            Self::RocPanic => 6,
            Self::HostPanic => 7,
            Self::FileFailure => 8,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Shutdown => "shutdown",
            Self::InvalidHeaders => "invalid_headers",
            Self::BodyTooLarge => "body_too_large",
            Self::HandlerOverload => "handler_overload",
            Self::FileOverload => "file_overload",
            Self::InvalidRocResponse => "invalid_roc_response",
            Self::RocPanic => "roc_panic",
            Self::HostPanic => "host_panic",
            Self::FileFailure => "file_failure",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Completion {
    EndOfStream,
    BodyFailure,
    BodyDropped,
}

impl Completion {
    const COUNT: usize = 3;
    const ALL: [Self; Self::COUNT] = [Self::EndOfStream, Self::BodyFailure, Self::BodyDropped];

    fn index(self) -> usize {
        match self {
            Self::EndOfStream => 0,
            Self::BodyFailure => 1,
            Self::BodyDropped => 2,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::EndOfStream => "end_of_stream",
            Self::BodyFailure => "body_failure",
            Self::BodyDropped => "body_dropped",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum MethodClass {
    Connect,
    Delete,
    Get,
    Head,
    Options,
    Patch,
    Post,
    Put,
    Trace,
    Query,
    Other,
}

impl MethodClass {
    const COUNT: usize = 11;
    const ALL: [Self; Self::COUNT] = [
        Self::Connect,
        Self::Delete,
        Self::Get,
        Self::Head,
        Self::Options,
        Self::Patch,
        Self::Post,
        Self::Put,
        Self::Trace,
        Self::Query,
        Self::Other,
    ];

    fn from_method(method: &Method) -> Self {
        match *method {
            Method::CONNECT => Self::Connect,
            Method::DELETE => Self::Delete,
            Method::GET => Self::Get,
            Method::HEAD => Self::Head,
            Method::OPTIONS => Self::Options,
            Method::PATCH => Self::Patch,
            Method::POST => Self::Post,
            Method::PUT => Self::Put,
            Method::TRACE => Self::Trace,
            _ if method.as_str() == "QUERY" => Self::Query,
            _ => Self::Other,
        }
    }

    fn index(self) -> usize {
        match self {
            Self::Connect => 0,
            Self::Delete => 1,
            Self::Get => 2,
            Self::Head => 3,
            Self::Options => 4,
            Self::Patch => 5,
            Self::Post => 6,
            Self::Put => 7,
            Self::Trace => 8,
            Self::Query => 9,
            Self::Other => 10,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Connect => "CONNECT",
            Self::Delete => "DELETE",
            Self::Get => "GET",
            Self::Head => "HEAD",
            Self::Options => "OPTIONS",
            Self::Patch => "PATCH",
            Self::Post => "POST",
            Self::Put => "PUT",
            Self::Trace => "TRACE",
            Self::Query => "QUERY",
            Self::Other => "_OTHER",
        }
    }
}

#[derive(Debug, Default)]
struct ActiveGauge {
    current: AtomicUsize,
    high_water: AtomicUsize,
}

impl ActiveGauge {
    fn increment(&self) {
        let current = self.current.fetch_add(1, Ordering::AcqRel) + 1;
        self.high_water.fetch_max(current, Ordering::AcqRel);
    }

    fn guard(self: &Arc<Self>) -> ActiveGaugeGuard {
        self.increment();
        ActiveGaugeGuard {
            gauge: Arc::clone(self),
        }
    }

    fn decrement(&self) {
        let previous = self.current.fetch_sub(1, Ordering::AcqRel);
        debug_assert!(previous > 0, "operational metric accounting underflow");
    }

    fn current(&self) -> usize {
        self.current.load(Ordering::Acquire)
    }

    fn high_water(&self) -> usize {
        self.high_water.load(Ordering::Acquire)
    }
}

pub(crate) struct ActiveGaugeGuard {
    gauge: Arc<ActiveGauge>,
}

impl Drop for ActiveGaugeGuard {
    fn drop(&mut self) {
        self.gauge.decrement();
    }
}

#[derive(Debug)]
struct Histogram {
    buckets: [AtomicU64; DURATION_BUCKETS_MICROS.len()],
    count: AtomicU64,
    sum_micros: AtomicU64,
}

impl Default for Histogram {
    fn default() -> Self {
        Self {
            buckets: std::array::from_fn(|_| AtomicU64::new(0)),
            count: AtomicU64::new(0),
            sum_micros: AtomicU64::new(0),
        }
    }
}

impl Histogram {
    fn record(&self, duration: Duration) {
        let micros = duration.as_micros().min(u64::MAX as u128) as u64;
        self.count.fetch_add(1, Ordering::Relaxed);
        self.sum_micros.fetch_add(micros, Ordering::Relaxed);
        for (upper, bucket) in DURATION_BUCKETS_MICROS.iter().zip(&self.buckets) {
            if micros <= *upper {
                bucket.fetch_add(1, Ordering::Relaxed);
            }
        }
    }

    fn render(&self, output: &mut String, name: &str, help: &str) {
        let _ = writeln!(output, "# HELP {name} {help}");
        let _ = writeln!(output, "# TYPE {name} histogram");
        for (upper, bucket) in DURATION_BUCKETS_SECONDS.iter().zip(&self.buckets) {
            let _ = writeln!(
                output,
                "{name}_bucket{{le=\"{upper}\"}} {}",
                bucket.load(Ordering::Acquire)
            );
        }
        let count = self.count.load(Ordering::Acquire);
        let _ = writeln!(output, "{name}_bucket{{le=\"+Inf\"}} {count}");
        let sum = self.sum_micros.load(Ordering::Acquire) as f64 / 1_000_000.0;
        let _ = writeln!(output, "{name}_sum {sum}");
        let _ = writeln!(output, "{name}_count {count}");
    }
}

#[derive(Debug)]
pub(crate) struct Metrics {
    requests: Arc<ActiveGauge>,
    connections: Arc<ActiveGauge>,
    handlers_active: Arc<ActiveGauge>,
    handlers_queued: Arc<ActiveGauge>,
    file_transfers: Arc<ActiveGauge>,
    request_totals: Box<[AtomicU64]>,
    response_bytes: [AtomicU64; Destination::COUNT],
    rejections: [AtomicU64; RejectionReason::COUNT],
    request_duration: Histogram,
    handler_queue_wait: Histogram,
    handler_duration: Histogram,
    access_log_dropped: AtomicU64,
    access_log_write_failures: AtomicU64,
}

impl Metrics {
    pub(crate) fn new() -> Arc<Self> {
        let request_series = Destination::COUNT * MethodClass::COUNT * Completion::COUNT;
        Arc::new(Self {
            requests: Arc::new(ActiveGauge::default()),
            connections: Arc::new(ActiveGauge::default()),
            handlers_active: Arc::new(ActiveGauge::default()),
            handlers_queued: Arc::new(ActiveGauge::default()),
            file_transfers: Arc::new(ActiveGauge::default()),
            request_totals: (0..request_series).map(|_| AtomicU64::new(0)).collect(),
            response_bytes: std::array::from_fn(|_| AtomicU64::new(0)),
            rejections: std::array::from_fn(|_| AtomicU64::new(0)),
            request_duration: Histogram::default(),
            handler_queue_wait: Histogram::default(),
            handler_duration: Histogram::default(),
            access_log_dropped: AtomicU64::new(0),
            access_log_write_failures: AtomicU64::new(0),
        })
    }

    pub(crate) fn connection_started(&self) -> ActiveGaugeGuard {
        self.connections.guard()
    }

    pub(crate) fn handler_started(&self) -> ActiveGaugeGuard {
        self.handlers_active.guard()
    }

    pub(crate) fn handler_queued(&self) -> ActiveGaugeGuard {
        self.handlers_queued.guard()
    }

    pub(crate) fn file_transfer_started(&self) -> ActiveGaugeGuard {
        self.file_transfers.guard()
    }

    pub(crate) fn active_file_transfers(&self) -> usize {
        self.file_transfers.current()
    }

    pub(crate) fn high_water_file_transfers(&self) -> usize {
        self.file_transfers.high_water()
    }

    pub(crate) fn record_handler_queue_wait(&self, duration: Duration) {
        self.handler_queue_wait.record(duration);
    }

    pub(crate) fn record_handler_duration(&self, duration: Duration) {
        self.handler_duration.record(duration);
    }

    fn request_started(&self) {
        self.requests.increment();
    }

    fn request_finished(
        &self,
        method: MethodClass,
        destination: Destination,
        completion: Completion,
        rejection: Option<RejectionReason>,
        duration: Duration,
        response_bytes: u64,
    ) {
        let index = ((destination.index() * MethodClass::COUNT + method.index())
            * Completion::COUNT)
            + completion.index();
        self.request_totals[index].fetch_add(1, Ordering::Relaxed);
        self.response_bytes[destination.index()].fetch_add(response_bytes, Ordering::Relaxed);
        if let Some(rejection) = rejection {
            self.rejections[rejection.index()].fetch_add(1, Ordering::Relaxed);
        }
        self.request_duration.record(duration);
        self.requests.decrement();
    }

    fn render_openmetrics(&self) -> String {
        // The number of series and labels is compile-time fixed. Reserving a
        // conservative bound avoids repeated growth while rendering.
        let mut output = String::with_capacity(24 * 1024);
        render_gauge(
            &mut output,
            "basic_webserver_http_requests_active",
            "HTTP requests whose response bodies have not reached a terminal state.",
            &self.requests,
        );
        render_gauge(
            &mut output,
            "basic_webserver_connections_active",
            "Accepted HTTP connections currently owned by the server.",
            &self.connections,
        );
        render_gauge(
            &mut output,
            "basic_webserver_roc_handlers_active",
            "Roc handlers currently executing.",
            &self.handlers_active,
        );
        render_gauge(
            &mut output,
            "basic_webserver_roc_handlers_queued",
            "Requests waiting for Roc handler admission.",
            &self.handlers_queued,
        );
        render_gauge(
            &mut output,
            "basic_webserver_native_file_transfers_active",
            "Host-managed file transfers currently active.",
            &self.file_transfers,
        );

        output.push_str(
            "# HELP basic_webserver_http_requests_total Terminal HTTP response body outcomes.\n\
             # TYPE basic_webserver_http_requests_total counter\n",
        );
        for destination in [
            Destination::Roc,
            Destination::NativeFile,
            Destination::NativeProbe,
            Destination::NativeMetrics,
            Destination::HostRejection,
        ] {
            for method in MethodClass::ALL {
                for completion in Completion::ALL {
                    let index = ((destination.index() * MethodClass::COUNT + method.index())
                        * Completion::COUNT)
                        + completion.index();
                    let _ = writeln!(
                        output,
                        "basic_webserver_http_requests_total{{method=\"{}\",destination=\"{}\",completion=\"{}\"}} {}",
                        method.label(),
                        destination.label(),
                        completion.label(),
                        self.request_totals[index].load(Ordering::Acquire)
                    );
                }
            }
        }

        output.push_str(
            "# HELP basic_webserver_http_response_body_bytes_total Response representation bytes produced by body streams.\n\
             # TYPE basic_webserver_http_response_body_bytes_total counter\n",
        );
        for destination in [
            Destination::Roc,
            Destination::NativeFile,
            Destination::NativeProbe,
            Destination::NativeMetrics,
            Destination::HostRejection,
        ] {
            let _ = writeln!(
                output,
                "basic_webserver_http_response_body_bytes_total{{destination=\"{}\"}} {}",
                destination.label(),
                self.response_bytes[destination.index()].load(Ordering::Acquire)
            );
        }

        output.push_str(
            "# HELP basic_webserver_rejections_total Requests rejected by a finite host reason.\n\
             # TYPE basic_webserver_rejections_total counter\n",
        );
        for reason in RejectionReason::ALL {
            let _ = writeln!(
                output,
                "basic_webserver_rejections_total{{reason=\"{}\"}} {}",
                reason.label(),
                self.rejections[reason.index()].load(Ordering::Acquire)
            );
        }

        self.request_duration.render(
            &mut output,
            "basic_webserver_http_request_duration_seconds",
            "Time from HTTP request construction to response body terminal state.",
        );
        self.handler_queue_wait.render(
            &mut output,
            "basic_webserver_roc_handler_queue_wait_seconds",
            "Time a request waited for Roc handler admission.",
        );
        self.handler_duration.render(
            &mut output,
            "basic_webserver_roc_handler_duration_seconds",
            "Time spent synchronously executing a Roc request handler.",
        );

        output.push_str(
            "# HELP basic_webserver_access_log_dropped_total Access log events dropped because the finite queue was full.\n\
             # TYPE basic_webserver_access_log_dropped_total counter\n",
        );
        let _ = writeln!(
            output,
            "basic_webserver_access_log_dropped_total {}",
            self.access_log_dropped.load(Ordering::Acquire)
        );
        output.push_str(
            "# HELP basic_webserver_access_log_write_failures_total Access log events lost after the log sink failed.\n\
             # TYPE basic_webserver_access_log_write_failures_total counter\n",
        );
        let _ = writeln!(
            output,
            "basic_webserver_access_log_write_failures_total {}",
            self.access_log_write_failures.load(Ordering::Acquire)
        );
        output.push_str("# EOF\n");
        output
    }
}

fn render_gauge(output: &mut String, name: &str, help: &str, gauge: &ActiveGauge) {
    let _ = writeln!(output, "# HELP {name} {help}");
    let _ = writeln!(output, "# TYPE {name} gauge");
    let _ = writeln!(output, "{name} {}", gauge.current());
    let high_water_name = format!("{name}_high_water");
    let _ = writeln!(
        output,
        "# HELP {high_water_name} Highest observed value of {name}."
    );
    let _ = writeln!(output, "# TYPE {high_water_name} gauge");
    let _ = writeln!(output, "{high_water_name} {}", gauge.high_water());
}

struct LogSender {
    sender: mpsc::SyncSender<String>,
    metrics: Arc<Metrics>,
}

impl LogSender {
    fn send(&self, event: &AccessLogEvent) {
        let encoded = match serde_json::to_string(event) {
            Ok(encoded) => encoded,
            Err(_) => {
                self.metrics
                    .access_log_write_failures
                    .fetch_add(1, Ordering::Relaxed);
                return;
            }
        };
        match self.sender.try_send(encoded) {
            Ok(()) => {}
            Err(mpsc::TrySendError::Full(_)) => {
                self.metrics
                    .access_log_dropped
                    .fetch_add(1, Ordering::Relaxed);
            }
            Err(mpsc::TrySendError::Disconnected(_)) => {
                self.metrics
                    .access_log_write_failures
                    .fetch_add(1, Ordering::Relaxed);
            }
        }
    }
}

struct Shared {
    metrics: Arc<Metrics>,
    logger: Option<LogSender>,
    log_target: LogTarget,
    next_request_id: AtomicU64,
    request_id_prefix: u64,
}

#[derive(Clone)]
pub(crate) struct TelemetryHandle {
    shared: Arc<Shared>,
}

pub(crate) struct Telemetry {
    shared: Option<Arc<Shared>>,
    log_worker: Option<LogWorker>,
}

struct LogWorker {
    join: Option<JoinHandle<()>>,
}

impl LogWorker {
    fn stop(mut self) {
        let deadline = Instant::now() + ACCESS_LOG_DRAIN_TIMEOUT;
        let join = self
            .join
            .as_ref()
            .expect("access log worker must own its join handle");
        while !join.is_finished() {
            let now = Instant::now();
            if now >= deadline {
                break;
            }
            std::thread::sleep((deadline - now).min(Duration::from_millis(1)));
        }
        if join.is_finished() {
            let _ = self.join.take().expect("join handle checked above").join();
        }
        // A sink such as a full stderr pipe may block inside the operating
        // system indefinitely. Dropping the JoinHandle detaches only this
        // context-free writer thread; server shutdown remains bounded and
        // process exit reclaims it.
    }
}

impl Telemetry {
    pub(crate) fn activate(config: TelemetryConfig, metrics: Arc<Metrics>) -> Result<Self, String> {
        let (logger, log_worker, log_target) = match config.access_log {
            Some(access_log) => {
                if access_log.buffer_events == 0 {
                    return Err("access log buffer capacity must be non-zero".to_owned());
                }
                let (sender, receiver) = mpsc::sync_channel(access_log.buffer_events);
                let worker_metrics = Arc::clone(&metrics);
                let join = std::thread::Builder::new()
                    .name("basic-webserver-access-log".to_owned())
                    .spawn(move || {
                        write_access_log(receiver, worker_metrics);
                    })
                    .map_err(|error| format!("failed to start access log writer: {error}"))?;
                (
                    Some(LogSender {
                        sender,
                        metrics: Arc::clone(&metrics),
                    }),
                    Some(LogWorker { join: Some(join) }),
                    access_log.target,
                )
            }
            None => (None, None, LogTarget::None),
        };
        let prefix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos() as u64
            ^ u64::from(std::process::id()).rotate_left(32);
        Ok(Self {
            shared: Some(Arc::new(Shared {
                metrics,
                logger,
                log_target,
                next_request_id: AtomicU64::new(1),
                request_id_prefix: prefix,
            })),
            log_worker,
        })
    }

    pub(crate) fn handle(&self) -> TelemetryHandle {
        TelemetryHandle {
            shared: Arc::clone(
                self.shared
                    .as_ref()
                    .expect("telemetry handle requested after shutdown"),
            ),
        }
    }

    pub(crate) fn shutdown(mut self) {
        debug_assert_eq!(
            Arc::strong_count(
                self.shared
                    .as_ref()
                    .expect("telemetry shutdown called more than once")
            ),
            1,
            "all request and connection telemetry handles must drain before shutdown"
        );
        drop(self.shared.take());
        if let Some(worker) = self.log_worker.take() {
            worker.stop();
        }
    }
}

impl Drop for Telemetry {
    fn drop(&mut self) {
        // Normal server shutdown calls `shutdown` after all response bodies
        // drain. This fallback still avoids detaching the writer on startup
        // errors.
        drop(self.shared.take());
        if let Some(worker) = self.log_worker.take() {
            worker.stop();
        }
    }
}

fn write_access_log(receiver: mpsc::Receiver<String>, metrics: Arc<Metrics>) {
    let stderr = io::stderr();
    let mut writer = BufWriter::new(stderr.lock());
    while let Ok(line) = receiver.recv() {
        if writeln!(writer, "{line}")
            .and_then(|()| writer.flush())
            .is_err()
        {
            metrics
                .access_log_write_failures
                .fetch_add(1, Ordering::Relaxed);
            while receiver.recv().is_ok() {
                metrics
                    .access_log_write_failures
                    .fetch_add(1, Ordering::Relaxed);
            }
            return;
        }
    }
    if writer.flush().is_err() {
        metrics
            .access_log_write_failures
            .fetch_add(1, Ordering::Relaxed);
    }
}

impl TelemetryHandle {
    pub(crate) fn metrics(&self) -> Arc<Metrics> {
        Arc::clone(&self.shared.metrics)
    }

    pub(crate) fn start_request(&self, method: &Method, path: &str) -> RequestTelemetry {
        self.shared.metrics.request_started();
        let sequence = self.shared.next_request_id.fetch_add(1, Ordering::Relaxed);
        let target = match self.shared.log_target {
            LogTarget::None => None,
            LogTarget::PathWithoutQuery => Some(bounded_path(path)),
        };
        RequestTelemetry {
            inner: Arc::new(RequestInner {
                shared: Arc::clone(&self.shared),
                started: Instant::now(),
                timestamp: SystemTime::now(),
                request_id_prefix: self.shared.request_id_prefix,
                request_id_sequence: sequence,
                method: MethodClass::from_method(method),
                target,
                details: Mutex::new(RequestDetails::default()),
                finished: AtomicBool::new(false),
            }),
        }
    }

    pub(crate) fn metrics_response(&self, method: &Method) -> ServerResponse {
        if method != Method::GET && method != Method::HEAD {
            let mut response =
                hyper::Response::new(full_body(Bytes::from_static(b"Method Not Allowed")));
            *response.status_mut() = StatusCode::METHOD_NOT_ALLOWED;
            response
                .headers_mut()
                .insert(hyper::header::ALLOW, HeaderValue::from_static("GET, HEAD"));
            response
                .headers_mut()
                .insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
            return response;
        }
        let rendered = self.shared.metrics.render_openmetrics();
        let representation_length = rendered.len();
        let bytes = if method == Method::HEAD {
            Bytes::new()
        } else {
            Bytes::from(rendered)
        };
        let mut response = hyper::Response::new(full_body(bytes));
        response.headers_mut().insert(
            CONTENT_TYPE,
            HeaderValue::from_static(OPENMETRICS_CONTENT_TYPE),
        );
        response
            .headers_mut()
            .insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
        response.headers_mut().insert(
            CONTENT_LENGTH,
            representation_length
                .to_string()
                .parse()
                .expect("bounded metrics representation length is a valid header"),
        );
        response
    }

    pub(crate) fn connection_started(&self) -> ActiveGaugeGuard {
        self.shared.metrics.connection_started()
    }
}

#[derive(Default)]
struct RequestDetails {
    destination: Option<Destination>,
    rejection: Option<RejectionReason>,
    status: Option<u16>,
    handler_queue_wait: Option<Duration>,
    handler_duration: Option<Duration>,
}

#[derive(Clone)]
pub(crate) struct RequestTelemetry {
    inner: Arc<RequestInner>,
}

struct RequestInner {
    shared: Arc<Shared>,
    started: Instant,
    timestamp: SystemTime,
    request_id_prefix: u64,
    request_id_sequence: u64,
    method: MethodClass,
    target: Option<String>,
    details: Mutex<RequestDetails>,
    finished: AtomicBool,
}

impl RequestTelemetry {
    pub(crate) fn set_destination(&self, destination: Destination) {
        self.inner
            .details
            .lock()
            .expect("request telemetry mutex poisoned")
            .destination = Some(destination);
    }

    pub(crate) fn reject(&self, reason: RejectionReason) {
        let mut details = self
            .inner
            .details
            .lock()
            .expect("request telemetry mutex poisoned");
        details.destination = Some(Destination::HostRejection);
        details.rejection = Some(reason);
    }

    pub(crate) fn reject_for_destination(&self, destination: Destination, reason: RejectionReason) {
        let mut details = self
            .inner
            .details
            .lock()
            .expect("request telemetry mutex poisoned");
        details.destination = Some(destination);
        details.rejection = Some(reason);
    }

    pub(crate) fn record_handler(&self, queue_wait: Duration, handler_duration: Duration) {
        let mut details = self
            .inner
            .details
            .lock()
            .expect("request telemetry mutex poisoned");
        details.handler_queue_wait = Some(queue_wait);
        details.handler_duration = Some(handler_duration);
    }

    pub(crate) fn instrument(self, response: ServerResponse) -> ServerResponse {
        self.inner
            .details
            .lock()
            .expect("request telemetry mutex poisoned")
            .status = Some(response.status().as_u16());
        let (parts, body) = response.into_parts();
        let body = CompletionBody::new(body, self).boxed_unsync();
        hyper::Response::from_parts(parts, body)
    }

    #[cfg(test)]
    fn finish_for_test(&self, completion: Completion, response_bytes: u64) {
        self.inner.finish(completion, response_bytes);
    }
}

impl RequestInner {
    fn finish(&self, completion: Completion, response_bytes: u64) {
        if self
            .finished
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return;
        }
        let duration = self.started.elapsed();
        let details = self
            .details
            .lock()
            .expect("request telemetry mutex poisoned");
        let destination = details.destination.unwrap_or(Destination::HostRejection);
        self.shared.metrics.request_finished(
            self.method,
            destination,
            completion,
            details.rejection,
            duration,
            response_bytes,
        );
        if let Some(logger) = &self.shared.logger {
            let timestamp_unix_ms = self
                .timestamp
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis()
                .min(u64::MAX as u128) as u64;
            logger.send(&AccessLogEvent {
                timestamp_unix_ms,
                duration_us: duration.as_micros().min(u64::MAX as u128) as u64,
                request_id: format!(
                    "{:016x}{:016x}",
                    self.request_id_prefix, self.request_id_sequence
                ),
                method: self.method.label(),
                status: details.status,
                destination: destination.label(),
                completion: completion.label(),
                rejection: details.rejection.map(RejectionReason::label),
                handler_queue_wait_us: details
                    .handler_queue_wait
                    .map(|value| value.as_micros().min(u64::MAX as u128) as u64),
                roc_handler_duration_us: details
                    .handler_duration
                    .map(|value| value.as_micros().min(u64::MAX as u128) as u64),
                response_body_bytes: response_bytes,
                target_path: self.target.as_deref(),
            });
        }
    }
}

impl Drop for RequestInner {
    fn drop(&mut self) {
        self.finish(Completion::BodyDropped, 0);
    }
}

#[derive(Serialize)]
struct AccessLogEvent<'a> {
    timestamp_unix_ms: u64,
    duration_us: u64,
    request_id: String,
    method: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    status: Option<u16>,
    destination: &'static str,
    completion: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    rejection: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    handler_queue_wait_us: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    roc_handler_duration_us: Option<u64>,
    response_body_bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    target_path: Option<&'a str>,
}

fn bounded_path(path: &str) -> String {
    if path.len() <= MAX_LOGGED_PATH_BYTES {
        return path.to_owned();
    }
    let mut end = MAX_LOGGED_PATH_BYTES;
    while !path.is_char_boundary(end) {
        end -= 1;
    }
    path[..end].to_owned()
}

struct CompletionBody {
    inner: ServerBody,
    telemetry: RequestTelemetry,
    response_bytes: u64,
    finished: bool,
}

impl CompletionBody {
    fn new(inner: ServerBody, telemetry: RequestTelemetry) -> Self {
        let finished = inner.is_end_stream();
        if finished {
            telemetry.inner.finish(Completion::EndOfStream, 0);
        }
        Self {
            inner,
            telemetry,
            response_bytes: 0,
            finished,
        }
    }

    fn finish(&mut self, completion: Completion) {
        if !self.finished {
            self.finished = true;
            self.telemetry.inner.finish(completion, self.response_bytes);
        }
    }
}

impl Body for CompletionBody {
    type Data = Bytes;
    type Error = io::Error;

    fn poll_frame(
        mut self: Pin<&mut Self>,
        context: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        match Pin::new(&mut self.inner).poll_frame(context) {
            Poll::Ready(Some(Ok(frame))) => {
                if let Some(data) = frame.data_ref() {
                    self.response_bytes = self
                        .response_bytes
                        .saturating_add(data.len().try_into().unwrap_or(u64::MAX));
                }
                // Hyper is allowed to stop polling as soon as `is_end_stream`
                // becomes true. A body such as `Full` reaches that state while
                // yielding its final data frame, so waiting for a later
                // `poll_frame(None)` would misclassify successful responses as
                // dropped.
                if self.inner.is_end_stream() {
                    self.finish(Completion::EndOfStream);
                }
                Poll::Ready(Some(Ok(frame)))
            }
            Poll::Ready(Some(Err(error))) => {
                self.finish(Completion::BodyFailure);
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(None) => {
                self.finish(Completion::EndOfStream);
                Poll::Ready(None)
            }
            Poll::Pending => Poll::Pending,
        }
    }

    fn is_end_stream(&self) -> bool {
        self.finished || self.inner.is_end_stream()
    }

    fn size_hint(&self) -> SizeHint {
        self.inner.size_hint()
    }
}

impl Drop for CompletionBody {
    fn drop(&mut self) {
        self.finish(Completion::BodyDropped);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::stream;
    use http_body_util::{BodyExt, StreamBody};
    use std::collections::BTreeSet;
    use std::convert::Infallible;

    fn telemetry(access_log: Option<AccessLogConfig>, _metrics_path: Option<&str>) -> Telemetry {
        Telemetry::activate(TelemetryConfig { access_log }, Metrics::new()).unwrap()
    }

    #[tokio::test]
    async fn response_body_emits_exactly_one_end_of_stream_event() {
        let telemetry = telemetry(None, None);
        let handle = telemetry.handle();
        let request = handle.start_request(&Method::GET, "/");
        request.set_destination(Destination::Roc);
        let response = request
            .clone()
            .instrument(hyper::Response::new(full_body(Bytes::from_static(b"abc"))));
        assert_eq!(
            response.into_body().collect().await.unwrap().to_bytes(),
            "abc"
        );
        request.finish_for_test(Completion::BodyDropped, 99);

        let rendered = handle.shared.metrics.render_openmetrics();
        assert!(rendered.contains(
            "basic_webserver_http_requests_total{method=\"GET\",destination=\"roc\",completion=\"end_of_stream\"} 1"
        ));
        assert!(rendered.contains(
            "basic_webserver_http_requests_total{method=\"GET\",destination=\"roc\",completion=\"body_dropped\"} 0"
        ));
        assert!(rendered.contains("basic_webserver_http_requests_active 0"));
        drop(request);
        drop(handle);
        telemetry.shutdown();
    }

    #[tokio::test]
    async fn body_failure_and_drop_are_distinct_terminal_states() {
        let telemetry = telemetry(None, None);
        let handle = telemetry.handle();
        let failed = handle.start_request(&Method::GET, "/failed");
        failed.set_destination(Destination::NativeFile);
        let error_body = StreamBody::new(stream::iter([Err::<Frame<Bytes>, _>(io::Error::other(
            "read failed",
        ))]))
        .boxed_unsync();
        let response = failed.instrument(hyper::Response::new(error_body));
        assert!(response.into_body().frame().await.unwrap().is_err());

        let dropped = handle.start_request(&Method::GET, "/dropped");
        dropped.set_destination(Destination::Roc);
        let response = dropped.instrument(hyper::Response::new(full_body(Bytes::from_static(
            b"not polled",
        ))));
        drop(response);

        let rendered = handle.shared.metrics.render_openmetrics();
        assert!(rendered.contains(
            "basic_webserver_http_requests_total{method=\"GET\",destination=\"native_file\",completion=\"body_failure\"} 1"
        ));
        assert!(rendered.contains(
            "basic_webserver_http_requests_total{method=\"GET\",destination=\"roc\",completion=\"body_dropped\"} 1"
        ));
        assert!(rendered.contains("basic_webserver_http_requests_active 0"));
        drop(handle);
        telemetry.shutdown();
    }

    #[test]
    fn method_and_target_cardinality_are_bounded() {
        let telemetry = telemetry(None, None);
        let handle = telemetry.handle();
        for index in 0..1_000 {
            let method = Method::from_bytes(format!("X-{index}").as_bytes()).unwrap();
            let request = handle.start_request(&method, &format!("/unique/{index}"));
            request.set_destination(Destination::Roc);
            request.finish_for_test(Completion::EndOfStream, 0);
        }
        let rendered = handle.shared.metrics.render_openmetrics();
        assert!(rendered.contains(
            "basic_webserver_http_requests_total{method=\"_OTHER\",destination=\"roc\",completion=\"end_of_stream\"} 1000"
        ));
        assert!(!rendered.contains("/unique/"));
        drop(handle);
        telemetry.shutdown();
    }

    #[test]
    fn every_rejection_reason_has_one_fixed_metric_series() {
        let telemetry = telemetry(None, None);
        let handle = telemetry.handle();
        for reason in RejectionReason::ALL {
            let request = handle.start_request(&Method::GET, "/untrusted");
            request.reject(reason);
            request.finish_for_test(Completion::EndOfStream, 0);
        }
        let rendered = handle.shared.metrics.render_openmetrics();
        for reason in RejectionReason::ALL {
            assert!(rendered.contains(&format!(
                "basic_webserver_rejections_total{{reason=\"{}\"}} 1",
                reason.label()
            )));
        }
        assert!(rendered.contains("basic_webserver_http_requests_active 0"));
        drop(handle);
        telemetry.shutdown();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_terminal_events_return_active_requests_to_zero() {
        let telemetry = telemetry(None, None);
        let handle = telemetry.handle();
        let mut tasks = Vec::new();
        let barrier = Arc::new(tokio::sync::Barrier::new(129));
        for _ in 0..128 {
            let request = handle.start_request(&Method::POST, "/same");
            request.set_destination(Destination::Roc);
            let barrier = Arc::clone(&barrier);
            tasks.push(tokio::spawn(async move {
                barrier.wait().await;
                request.finish_for_test(Completion::EndOfStream, 1);
            }));
        }
        barrier.wait().await;
        for task in tasks {
            task.await.unwrap();
        }
        let rendered = handle.shared.metrics.render_openmetrics();
        assert!(rendered.contains("basic_webserver_http_requests_active 0"));
        assert!(rendered.contains("basic_webserver_http_requests_active_high_water 128"));
        assert!(rendered.contains(
            "basic_webserver_http_requests_total{method=\"POST\",destination=\"roc\",completion=\"end_of_stream\"} 128"
        ));
        drop(handle);
        telemetry.shutdown();
    }

    #[test]
    fn structured_encoding_prevents_log_injection_and_bounds_paths() {
        let event = AccessLogEvent {
            timestamp_unix_ms: 1,
            duration_us: 2,
            request_id: "id".to_owned(),
            method: "GET",
            status: Some(200),
            destination: "roc",
            completion: "end_of_stream",
            rejection: None,
            handler_queue_wait_us: None,
            roc_handler_duration_us: None,
            response_body_bytes: 3,
            target_path: Some("/bad\n{\"forged\":true}"),
        };
        let encoded = serde_json::to_string(&event).unwrap();
        assert!(!encoded.contains('\n'));
        assert!(encoded.contains("\\n"));
        assert_eq!(
            bounded_path(&"é".repeat(2_000)).len(),
            MAX_LOGGED_PATH_BYTES
        );
    }

    #[test]
    fn request_ids_are_host_generated_and_unique_within_a_process() {
        let telemetry = telemetry(None, None);
        let handle = telemetry.handle();
        let mut ids = BTreeSet::new();
        for _ in 0..100 {
            let request = handle.start_request(&Method::GET, "/");
            ids.insert((
                request.inner.request_id_prefix,
                request.inner.request_id_sequence,
            ));
            request.finish_for_test(Completion::EndOfStream, 0);
        }
        assert_eq!(ids.len(), 100);
        drop(handle);
        telemetry.shutdown();
    }

    #[tokio::test]
    async fn metrics_endpoint_has_openmetrics_headers_and_no_store() {
        let telemetry = telemetry(None, Some("/metrics"));
        let handle = telemetry.handle();
        let response = handle.metrics_response(&Method::GET);
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers()[CONTENT_TYPE], OPENMETRICS_CONTENT_TYPE);
        assert_eq!(response.headers()[CACHE_CONTROL], "no-store");
        let body = response.into_body().collect().await.unwrap().to_bytes();
        assert!(body.ends_with(b"# EOF\n"));

        let head = handle.metrics_response(&Method::HEAD);
        assert_eq!(head.status(), StatusCode::OK);
        assert_eq!(head.headers()[CONTENT_LENGTH], body.len().to_string());
        assert!(head
            .into_body()
            .collect()
            .await
            .unwrap()
            .to_bytes()
            .is_empty());
        drop(handle);
        telemetry.shutdown();
    }

    #[test]
    fn log_queue_overflow_is_non_blocking_and_counted() {
        let metrics = Metrics::new();
        let (sender, _receiver) = mpsc::sync_channel(1);
        let logger = LogSender {
            sender,
            metrics: Arc::clone(&metrics),
        };
        let event = AccessLogEvent {
            timestamp_unix_ms: 1,
            duration_us: 1,
            request_id: "1".to_owned(),
            method: "GET",
            status: Some(200),
            destination: "roc",
            completion: "end_of_stream",
            rejection: None,
            handler_queue_wait_us: None,
            roc_handler_duration_us: None,
            response_body_bytes: 0,
            target_path: None,
        };
        logger.send(&event);
        logger.send(&event);
        assert_eq!(metrics.access_log_dropped.load(Ordering::Acquire), 1);
    }

    #[test]
    fn empty_body_is_complete_without_transport_polling() {
        let telemetry = telemetry(None, None);
        let handle = telemetry.handle();
        let request = handle.start_request(&Method::HEAD, "/");
        request.set_destination(Destination::Roc);
        let body = empty_body();
        let response = request.instrument(hyper::Response::new(body));
        drop(response);
        assert!(handle
            .shared
            .metrics
            .render_openmetrics()
            .contains("basic_webserver_http_requests_active 0"));
        drop(handle);
        telemetry.shutdown();
    }

    #[test]
    fn infallible_marker_is_used_by_test_bodies() {
        let _: Option<Infallible> = None;
    }
}
