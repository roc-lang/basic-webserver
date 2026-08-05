//! Declarative, real-Roc server simulation used only by instrumented hosts.

use crate::allocation_benchmark::{self, AllocationSnapshot};
use crate::http_server::{self, ServerContext, ServerListener};
use crate::shutdown::{ShutdownController, ShutdownReason};
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::client::conn::{http1, http2};
use hyper::{Request, StatusCode};
use hyper_util::rt::{TokioExecutor, TokioIo};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::io::{self, Read};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::DuplexStream;
use tokio::sync::{mpsc, Barrier};

const SCHEMA_VERSION: u32 = 1;
const MAX_SIMULATED_CONNECTIONS: usize = 10_000;
const MAX_REQUEST_TEMPLATES: usize = 128;
const MAX_REPEATS: usize = 100_000;
const MAX_RECORDED_ERRORS: usize = 32;
const MAX_RESPONSE_BYTES: usize = 64 * 1024 * 1024;
const MAX_PHASE_TIMEOUT_MS: u64 = 5 * 60 * 1_000;

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum SimulationProtocol {
    Http1,
    Http2,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SimulatedRequest {
    #[serde(default = "default_method")]
    method: String,
    target: String,
    #[serde(default)]
    headers: BTreeMap<String, String>,
    #[serde(default)]
    body: String,
    #[serde(default = "default_status")]
    expect_status: u16,
    #[serde(default)]
    expect_body: Option<String>,
    #[serde(default)]
    body_contains: Vec<String>,
    #[serde(default)]
    expect_headers: BTreeMap<String, String>,
    #[serde(default)]
    expect_sse_events: Option<usize>,
}

fn default_method() -> String {
    "GET".to_owned()
}

fn default_status() -> u16 {
    200
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SimulationScenario {
    schema_version: u32,
    name: String,
    protocol: SimulationProtocol,
    pub(crate) concurrency: usize,
    #[serde(default = "default_repeats")]
    repeats: usize,
    #[serde(default)]
    warmup_repeats: usize,
    #[serde(default = "default_duplex_bytes")]
    duplex_bytes: usize,
    #[serde(default = "default_response_bytes")]
    max_response_bytes: usize,
    #[serde(default = "default_phase_timeout_ms")]
    phase_timeout_ms: u64,
    requests: Vec<SimulatedRequest>,
}

fn default_repeats() -> usize {
    1
}

fn default_duplex_bytes() -> usize {
    64 * 1024
}

fn default_response_bytes() -> usize {
    8 * 1024 * 1024
}

fn default_phase_timeout_ms() -> u64 {
    60 * 1_000
}

impl SimulationScenario {
    fn validate(&self) -> Result<(), String> {
        if self.schema_version != SCHEMA_VERSION {
            return Err(format!(
                "unsupported simulation schema version {}; expected {SCHEMA_VERSION}",
                self.schema_version
            ));
        }
        if self.name.is_empty() {
            return Err("simulation name must not be empty".to_owned());
        }
        if !(1..=MAX_SIMULATED_CONNECTIONS).contains(&self.concurrency) {
            return Err(format!(
                "simulation concurrency must be between 1 and {MAX_SIMULATED_CONNECTIONS}"
            ));
        }
        if self.requests.is_empty() || self.requests.len() > MAX_REQUEST_TEMPLATES {
            return Err(format!(
                "simulation must contain between 1 and {MAX_REQUEST_TEMPLATES} request templates"
            ));
        }
        if self.repeats == 0 || self.repeats > MAX_REPEATS || self.warmup_repeats > MAX_REPEATS {
            return Err(format!(
                "simulation repeat counts must be between 1 and {MAX_REPEATS}"
            ));
        }
        if !(1024..=1024 * 1024).contains(&self.duplex_bytes) {
            return Err("duplex buffer must be between 1 KiB and 1 MiB".to_owned());
        }
        if !(1024..=MAX_RESPONSE_BYTES).contains(&self.max_response_bytes) {
            return Err(format!(
                "maximum response bytes must be between 1 KiB and {MAX_RESPONSE_BYTES}"
            ));
        }
        if !(1..=MAX_PHASE_TIMEOUT_MS).contains(&self.phase_timeout_ms) {
            return Err(format!(
                "phase timeout must be between 1 ms and {MAX_PHASE_TIMEOUT_MS} ms"
            ));
        }
        for request in &self.requests {
            if !request.target.starts_with('/') {
                return Err(format!(
                    "simulated request target must begin with '/': {:?}",
                    request.target
                ));
            }
            if StatusCode::from_u16(request.expect_status).is_err() {
                return Err(format!("invalid expected status {}", request.expect_status));
            }
        }
        Ok(())
    }

    fn validate_server_limits(&self, max_connections: usize) -> Result<(), String> {
        if self.concurrency > max_connections {
            return Err(format!(
                "simulation concurrency {} exceeds the application's {max_connections}-connection limit",
                self.concurrency
            ));
        }
        Ok(())
    }
}

pub(crate) fn read_scenario() -> Result<SimulationScenario, String> {
    let mut bytes = Vec::new();
    io::stdin()
        .lock()
        .take(8 * 1024 * 1024)
        .read_to_end(&mut bytes)
        .map_err(|error| format!("failed to read simulation scenario: {error}"))?;
    let scenario: SimulationScenario = serde_json::from_slice(&bytes)
        .map_err(|error| format!("invalid simulation scenario: {error}"))?;
    scenario.validate()?;
    Ok(scenario)
}

pub(crate) struct SimulationListener {
    receiver: mpsc::Receiver<DuplexStream>,
}

impl ServerListener for SimulationListener {
    type Stream = DuplexStream;

    async fn accept(&mut self) -> io::Result<Self::Stream> {
        self.accept().await
    }
}

impl SimulationListener {
    pub(crate) async fn accept(&mut self) -> io::Result<DuplexStream> {
        self.receiver
            .recv()
            .await
            .ok_or_else(|| io::Error::new(io::ErrorKind::BrokenPipe, "simulation listener stopped"))
    }
}

#[derive(Default)]
struct WorkerResult {
    requests: u64,
    errors: Vec<String>,
}

impl WorkerResult {
    fn failure(&mut self, detail: String) {
        if self.errors.len() < MAX_RECORDED_ERRORS {
            self.errors.push(detail);
        }
    }

    fn merge(&mut self, mut other: Self) {
        self.requests = self.requests.saturating_add(other.requests);
        let remaining = MAX_RECORDED_ERRORS.saturating_sub(self.errors.len());
        let count = remaining.min(other.errors.len());
        self.errors.extend(other.errors.drain(..count));
    }
}

#[derive(Debug, Serialize)]
pub(crate) struct SimulationReport {
    schema_version: u32,
    kind: &'static str,
    scenario: String,
    protocol: SimulationProtocol,
    concurrency: usize,
    requests: u64,
    errors: Vec<String>,
    allocations: AllocationSnapshot,
    resources: Option<crate::telemetry::OperationalMetricsSnapshot>,
}

impl SimulationReport {
    pub(crate) fn set_resources(
        &mut self,
        resources: crate::telemetry::OperationalMetricsSnapshot,
    ) {
        self.resources = Some(resources);
    }
}

pub(crate) fn channel(concurrency: usize) -> (mpsc::Sender<DuplexStream>, SimulationListener) {
    let (sender, receiver) = mpsc::channel(concurrency.min(1024).max(1));
    (sender, SimulationListener { receiver })
}

pub(crate) fn start() -> i32 {
    let scenario = match read_scenario() {
        Ok(scenario) => scenario,
        Err(error) => {
            eprintln!("BENCHMARK_SIMULATION_ERROR {error}");
            return 1;
        }
    };
    http_server::start_with_runner(move |context| run_server(scenario, context))
}

async fn run_server(scenario: SimulationScenario, context: ServerContext) -> ShutdownReason {
    if let Err(error) = scenario.validate_server_limits(context.max_connections()) {
        eprintln!("BENCHMARK_SIMULATION_ERROR {error}");
        return ShutdownReason::StartupFailed(error);
    }

    let (sender, listener) = channel(scenario.concurrency);
    let drive_shutdown = context.shutdown_controller();
    let drive = async move {
        let result = drive(scenario, sender, drive_shutdown.clone()).await;
        if let Err(error) = &result {
            drive_shutdown.request(ShutdownReason::RuntimeFailed(error.clone()));
        }
        result
    };
    let (reason, report) = tokio::join!(
        http_server::run_server_with_listener(context.clone(), listener),
        drive
    );
    match report {
        Ok(mut report) => {
            report.set_resources(context.operational_metrics());
            match serde_json::to_string(&report) {
                Ok(json) => println!("BENCHMARK_SIMULATION {json}"),
                Err(error) => eprintln!("BENCHMARK_SIMULATION_ERROR {error}"),
            }
        }
        Err(error) => eprintln!("BENCHMARK_SIMULATION_ERROR {error}"),
    }
    reason
}

pub(crate) async fn drive(
    scenario: SimulationScenario,
    sender: mpsc::Sender<DuplexStream>,
    shutdown: ShutdownController,
) -> Result<SimulationReport, String> {
    let ready = Arc::new(Barrier::new(scenario.concurrency + 1));
    let start = Arc::new(Barrier::new(scenario.concurrency + 1));
    let measured = Arc::new(Barrier::new(scenario.concurrency + 1));
    let close = Arc::new(Barrier::new(scenario.concurrency + 1));
    let scenario = Arc::new(scenario);
    let mut workers = Vec::with_capacity(scenario.concurrency);

    for worker_index in 0..scenario.concurrency {
        let worker_scenario = Arc::clone(&scenario);
        let worker_sender = sender.clone();
        let worker_ready = Arc::clone(&ready);
        let worker_start = Arc::clone(&start);
        let worker_measured = Arc::clone(&measured);
        let worker_close = Arc::clone(&close);
        workers.push(tokio::spawn(allocation_benchmark::scope_harness(
            async move {
                worker(
                    worker_index,
                    worker_scenario,
                    worker_sender,
                    worker_ready,
                    worker_start,
                    worker_measured,
                    worker_close,
                )
                .await
            },
        )));
    }
    drop(sender);

    let phase_timeout = Duration::from_millis(scenario.phase_timeout_ms);
    if let Err(error) = wait_for_phase(&ready, phase_timeout, "warmup readiness").await {
        abort_workers(&workers);
        shutdown.request(ShutdownReason::RuntimeFailed(error.clone()));
        return Err(error);
    }
    if let Err(error) = allocation_benchmark::begin_epoch().map_err(str::to_owned) {
        abort_workers(&workers);
        shutdown.request(ShutdownReason::RuntimeFailed(error.clone()));
        return Err(error);
    }
    if let Err(error) = wait_for_phase(&start, phase_timeout, "measurement start").await {
        abort_workers(&workers);
        let _ = allocation_benchmark::end_epoch();
        shutdown.request(ShutdownReason::RuntimeFailed(error.clone()));
        return Err(error);
    }
    if let Err(error) = wait_for_phase(&measured, phase_timeout, "measured work").await {
        abort_workers(&workers);
        let _ = allocation_benchmark::end_epoch();
        shutdown.request(ShutdownReason::RuntimeFailed(error.clone()));
        return Err(error);
    }
    let allocations = match allocation_benchmark::end_epoch().map_err(str::to_owned) {
        Ok(allocations) => allocations,
        Err(error) => {
            abort_workers(&workers);
            shutdown.request(ShutdownReason::RuntimeFailed(error.clone()));
            return Err(error);
        }
    };
    if let Err(error) = wait_for_phase(&close, phase_timeout, "connection release").await {
        abort_workers(&workers);
        shutdown.request(ShutdownReason::RuntimeFailed(error.clone()));
        return Err(error);
    }

    let mut aggregate = WorkerResult::default();
    for worker in workers {
        match worker.await {
            Ok(result) => aggregate.merge(result),
            Err(error) => aggregate.failure(format!("simulation worker failed: {error}")),
        }
    }
    if aggregate.errors.is_empty() {
        shutdown.request(ShutdownReason::ApplicationRequested { exit_code: 0 });
    } else {
        shutdown.request(ShutdownReason::RuntimeFailed(
            "deterministic simulation assertions failed".to_owned(),
        ));
    }

    Ok(SimulationReport {
        schema_version: SCHEMA_VERSION,
        kind: "simulation",
        scenario: scenario.name.clone(),
        protocol: scenario.protocol,
        concurrency: scenario.concurrency,
        requests: aggregate.requests,
        errors: aggregate.errors,
        allocations,
        resources: None,
    })
}

async fn wait_for_phase(
    barrier: &Barrier,
    timeout: Duration,
    phase: &'static str,
) -> Result<(), String> {
    tokio::time::timeout(timeout, barrier.wait())
        .await
        .map(|_| ())
        .map_err(|_| format!("simulation {phase} exceeded {timeout:?}"))
}

fn abort_workers(workers: &[tokio::task::JoinHandle<WorkerResult>]) {
    for worker in workers {
        worker.abort();
    }
}

async fn worker(
    worker_index: usize,
    scenario: Arc<SimulationScenario>,
    sender: mpsc::Sender<DuplexStream>,
    ready: Arc<Barrier>,
    start: Arc<Barrier>,
    measured: Arc<Barrier>,
    close: Arc<Barrier>,
) -> WorkerResult {
    let (client, server) = tokio::io::duplex(scenario.duplex_bytes);
    let mut result = WorkerResult::default();
    if sender.send(server).await.is_err() {
        result.failure("simulation listener closed before connection admission".to_owned());
        ready.wait().await;
        start.wait().await;
        measured.wait().await;
        close.wait().await;
        return result;
    }

    match scenario.protocol {
        SimulationProtocol::Http1 => {
            let handshake = http1::handshake(TokioIo::new(client)).await;
            let Ok((mut request_sender, connection)) = handshake else {
                result.failure(format!("worker {worker_index} HTTP/1 handshake failed"));
                ready.wait().await;
                start.wait().await;
                measured.wait().await;
                close.wait().await;
                return result;
            };
            let connection = tokio::spawn(allocation_benchmark::scope_harness(connection));
            run_rounds(
                &scenario,
                scenario.warmup_repeats,
                |request| request_sender.send_request(request),
                false,
                &mut result,
            )
            .await;
            ready.wait().await;
            start.wait().await;
            run_rounds(
                &scenario,
                scenario.repeats,
                |request| request_sender.send_request(request),
                true,
                &mut result,
            )
            .await;
            measured.wait().await;
            close.wait().await;
            connection.abort();
        }
        SimulationProtocol::Http2 => {
            let handshake = http2::handshake(TokioExecutor::new(), TokioIo::new(client)).await;
            let Ok((mut request_sender, connection)) = handshake else {
                result.failure(format!("worker {worker_index} HTTP/2 handshake failed"));
                ready.wait().await;
                start.wait().await;
                measured.wait().await;
                close.wait().await;
                return result;
            };
            let connection = tokio::spawn(allocation_benchmark::scope_harness(connection));
            run_rounds(
                &scenario,
                scenario.warmup_repeats,
                |request| request_sender.send_request(request),
                false,
                &mut result,
            )
            .await;
            ready.wait().await;
            start.wait().await;
            run_rounds(
                &scenario,
                scenario.repeats,
                |request| request_sender.send_request(request),
                true,
                &mut result,
            )
            .await;
            measured.wait().await;
            close.wait().await;
            connection.abort();
        }
    }
    result
}

async fn run_rounds<F, Fut, B>(
    scenario: &SimulationScenario,
    repeats: usize,
    mut send: F,
    measured: bool,
    result: &mut WorkerResult,
) where
    F: FnMut(Request<Full<Bytes>>) -> Fut,
    Fut: std::future::Future<Output = Result<hyper::Response<B>, hyper::Error>>,
    B: hyper::body::Body<Data = Bytes> + Unpin,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    for index in 0..repeats {
        let template = &scenario.requests[index % scenario.requests.len()];
        let request = match build_request(scenario.protocol, template) {
            Ok(request) => request,
            Err(error) => {
                result.failure(error);
                continue;
            }
        };
        match send(request).await {
            Ok(response) => {
                validate_response(
                    template,
                    response,
                    scenario.max_response_bytes,
                    measured,
                    result,
                )
                .await
            }
            Err(error) => result.failure(format!("request exchange failed: {error}")),
        }
    }
}

fn build_request(
    protocol: SimulationProtocol,
    template: &SimulatedRequest,
) -> Result<Request<Full<Bytes>>, String> {
    let uri = match protocol {
        SimulationProtocol::Http1 => template.target.clone(),
        SimulationProtocol::Http2 => format!("http://simulation{}", template.target),
    };
    let mut builder = Request::builder()
        .method(template.method.as_str())
        .uri(uri)
        .header("host", "simulation");
    for (name, value) in &template.headers {
        builder = builder.header(name, value);
    }
    builder
        .body(Full::new(Bytes::copy_from_slice(template.body.as_bytes())))
        .map_err(|error| format!("failed to build simulated request: {error}"))
}

async fn validate_response<B>(
    template: &SimulatedRequest,
    response: hyper::Response<B>,
    max_response_bytes: usize,
    measured: bool,
    result: &mut WorkerResult,
) where
    B: hyper::body::Body<Data = Bytes> + Unpin,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    let status = response.status();
    let content_encoding = response
        .headers()
        .get(hyper::header::CONTENT_ENCODING)
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned);
    for (name, expected) in &template.expect_headers {
        let found = response
            .headers()
            .get(name)
            .and_then(|value| value.to_str().ok());
        if found != Some(expected.as_str()) {
            result.failure(format!(
                "{} response header {:?} was {:?}, expected {:?}",
                template.target, name, found, expected
            ));
        }
    }
    let encoded = match read_bounded_body(response.into_body(), max_response_bytes).await {
        Ok(body) => body,
        Err(error) => {
            result.failure(format!("response body failed: {error}"));
            return;
        }
    };
    let body = match decode_body(&encoded, content_encoding.as_deref(), max_response_bytes) {
        Ok(body) => body,
        Err(error) => {
            result.failure(format!("response body failed: {error}"));
            return;
        }
    };
    if measured {
        result.requests = result.requests.saturating_add(1);
    }
    if status.as_u16() != template.expect_status {
        result.failure(format!(
            "{} expected status {}, received {}",
            template.target, template.expect_status, status
        ));
    }
    let text = String::from_utf8_lossy(&body);
    if let Some(expected) = &template.expect_body {
        if text != expected.as_str() {
            result.failure(format!("{} response body did not match", template.target));
        }
    }
    for expected in &template.body_contains {
        if !text.contains(expected) {
            result.failure(format!(
                "{} response body did not contain {:?}",
                template.target, expected
            ));
        }
    }
    if let Some(expected) = template.expect_sse_events {
        let events = text
            .lines()
            .filter(|line| line.trim_end_matches('\r') == "event: datastar-patch-elements")
            .count();
        if events != expected {
            result.failure(format!(
                "{} expected {expected} SSE events, received {events}",
                template.target
            ));
        }
    }
}

async fn read_bounded_body<B>(mut body: B, limit: usize) -> Result<Vec<u8>, String>
where
    B: hyper::body::Body<Data = Bytes> + Unpin,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    let mut bytes = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|error| error.to_string())?;
        if let Ok(data) = frame.into_data() {
            let next = bytes
                .len()
                .checked_add(data.len())
                .ok_or_else(|| "response size overflow".to_owned())?;
            if next > limit {
                return Err(format!("encoded response exceeded {limit} bytes"));
            }
            bytes.extend_from_slice(&data);
        }
    }
    Ok(bytes)
}

fn decode_body(encoded: &[u8], encoding: Option<&str>, limit: usize) -> Result<Vec<u8>, String> {
    match encoding {
        None | Some("identity") => Ok(encoded.to_vec()),
        Some("br") => {
            let decoder = brotli::Decompressor::new(encoded, 16 * 1024);
            let mut bounded = decoder.take((limit as u64).saturating_add(1));
            let mut decoded = Vec::new();
            bounded
                .read_to_end(&mut decoded)
                .map_err(|error| format!("Brotli decoding failed: {error}"))?;
            if decoded.len() > limit {
                return Err(format!("decoded response exceeded {limit} bytes"));
            }
            Ok(decoded)
        }
        Some(other) => Err(format!("unsupported simulated response coding {other:?}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scenario_validation_is_bounded() {
        let scenario: SimulationScenario = serde_json::from_str(
            r#"{
                "schema_version": 1,
                "name": "smoke",
                "protocol": "http1",
                "concurrency": 2,
                "requests": [{"target": "/", "expect_body": "ok"}]
            }"#,
        )
        .unwrap();
        assert!(scenario.validate().is_ok());
        assert!(scenario.validate_server_limits(2).is_ok());
        assert_eq!(
            scenario.validate_server_limits(1).unwrap_err(),
            "simulation concurrency 2 exceeds the application's 1-connection limit"
        );
    }

    #[test]
    fn simulated_brotli_body_is_fully_decoded_and_bounded() {
        let plain = b"event: datastar-patch-elements\ndata: ok\n\n";
        let encoded =
            crate::compression::encode_bytes(crate::compression::ContentCoding::Brotli, plain)
                .unwrap();
        assert_eq!(decode_body(&encoded, Some("br"), 1024).unwrap(), plain);
        assert!(decode_body(&encoded, Some("br"), 8).is_err());
        assert!(decode_body(&encoded[..encoded.len() - 1], Some("br"), 1024).is_err());
    }
}
