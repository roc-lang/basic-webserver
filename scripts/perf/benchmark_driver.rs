use bytes::Bytes;
use http_body_util::{BodyExt, Empty};
use hyper::client::conn::{http1, http2};
use hyper::{Request, StatusCode};
use hyper_util::rt::{TokioExecutor, TokioIo};
use serde::{Deserialize, Serialize};
use std::env;
use std::error::Error;
use std::fmt;
use std::fs;
use std::io::{self, Write};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::net::TcpStream;
use tokio::sync::Barrier;
use tokio::task::JoinHandle;
use tokio::time::timeout;

type DynError = Box<dyn Error + Send + Sync>;

const SCHEMA_VERSION: u32 = 1;
const MAX_CONCURRENCY: usize = 100_000;
const MAX_CLIENT_THREADS: usize = 256;
const MAX_DURATION: Duration = Duration::from_secs(24 * 60 * 60);

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
enum Protocol {
    Http1,
    Http2,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
enum WorkloadKind {
    #[default]
    Request,
    Sse,
    SseHold,
}

impl Protocol {
    fn parse(value: &str) -> Result<Self, CliError> {
        match value {
            "http1" => Ok(Self::Http1),
            "http2" => Ok(Self::Http2),
            _ => Err(CliError(format!(
                "unsupported protocol {value:?}; use http1 or http2"
            ))),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Http1 => "http1",
            Self::Http2 => "http2",
        }
    }
}

#[derive(Clone, Debug)]
struct Config {
    name: String,
    workload: WorkloadKind,
    protocol: Protocol,
    address: String,
    routes: Vec<Route>,
    duration: Duration,
    request_timeout: Duration,
    concurrency: usize,
    connections: usize,
    threads: usize,
    allow_errors: bool,
    error_backoff: Duration,
    jsonl: bool,
    expected_events: usize,
    accept_encoding: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct Route {
    path: String,
    weight: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ScenarioFile {
    schema_version: u32,
    name: String,
    #[serde(default)]
    workload: WorkloadKind,
    protocol: Protocol,
    #[serde(default = "default_address")]
    address: String,
    routes: Vec<Route>,
    duration_ms: u64,
    #[serde(default = "default_request_timeout_ms")]
    request_timeout_ms: u64,
    concurrency: usize,
    #[serde(default = "default_connections")]
    connections: usize,
    #[serde(default = "default_threads")]
    threads: usize,
    #[serde(default)]
    allow_errors: bool,
    #[serde(default)]
    error_backoff_ms: u64,
    #[serde(default)]
    expected_events: usize,
    #[serde(default = "default_accept_encoding")]
    accept_encoding: String,
}

fn default_address() -> String {
    "127.0.0.1:8000".to_owned()
}

fn default_request_timeout_ms() -> u64 {
    5_000
}

fn default_connections() -> usize {
    1
}

fn default_threads() -> usize {
    4
}

fn default_accept_encoding() -> String {
    "identity".to_owned()
}

#[derive(Debug)]
struct CliError(String);

impl fmt::Display for CliError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl Error for CliError {}

#[derive(Clone, Debug)]
struct LatencyHistogram {
    buckets: Vec<u64>,
    count: u64,
    sum_ns: u128,
    max_ns: u64,
}

impl Default for LatencyHistogram {
    fn default() -> Self {
        Self {
            // 1 us buckets through 1 ms, 10 us through 10 ms, 100 us through
            // 100 ms, 1 ms through 1 s, and 10 ms through 10 s, plus overflow.
            buckets: vec![0; 4_602],
            count: 0,
            sum_ns: 0,
            max_ns: 0,
        }
    }
}

impl LatencyHistogram {
    fn record(&mut self, nanoseconds: u64) {
        let micros = nanoseconds.saturating_add(999) / 1_000;
        let index = latency_bucket(micros).min(self.buckets.len() - 1);
        self.buckets[index] = self.buckets[index].saturating_add(1);
        self.count = self.count.saturating_add(1);
        self.sum_ns = self.sum_ns.saturating_add(u128::from(nanoseconds));
        self.max_ns = self.max_ns.max(nanoseconds);
    }

    fn merge(&mut self, other: &Self) {
        for (target, source) in self.buckets.iter_mut().zip(&other.buckets) {
            *target = target.saturating_add(*source);
        }
        self.count = self.count.saturating_add(other.count);
        self.sum_ns = self.sum_ns.saturating_add(other.sum_ns);
        self.max_ns = self.max_ns.max(other.max_ns);
    }

    fn mean_ms(&self) -> f64 {
        if self.count == 0 {
            0.0
        } else {
            self.sum_ns as f64 / self.count as f64 / 1_000_000.0
        }
    }

    fn percentile_ms(&self, percentile: f64) -> f64 {
        if self.count == 0 {
            return 0.0;
        }
        if percentile >= 100.0 {
            return self.max_ns as f64 / 1_000_000.0;
        }
        let wanted = ((self.count as f64 * percentile / 100.0).ceil() as u64).max(1);
        let mut observed = 0u64;
        for (index, count) in self.buckets.iter().enumerate() {
            observed = observed.saturating_add(*count);
            if observed >= wanted {
                if index == self.buckets.len() - 1 {
                    return self.max_ns as f64 / 1_000_000.0;
                }
                return latency_bucket_upper_micros(index) as f64 / 1_000.0;
            }
        }
        self.max_ns as f64 / 1_000_000.0
    }
}

fn latency_bucket(micros: u64) -> usize {
    match micros {
        0..=1_000 => micros as usize,
        1_001..=10_000 => 1_001 + ((micros - 1_001) / 10) as usize,
        10_001..=100_000 => 1_901 + ((micros - 10_001) / 100) as usize,
        100_001..=1_000_000 => 2_801 + ((micros - 100_001) / 1_000) as usize,
        1_000_001..=10_000_000 => 3_701 + ((micros - 1_000_001) / 10_000) as usize,
        _ => 4_601,
    }
}

fn latency_bucket_upper_micros(index: usize) -> u64 {
    match index {
        0..=1_000 => index as u64,
        1_001..=1_900 => 1_010 + (index as u64 - 1_001) * 10,
        1_901..=2_800 => 10_100 + (index as u64 - 1_901) * 100,
        2_801..=3_700 => 101_000 + (index as u64 - 2_801) * 1_000,
        3_701..=4_600 => 1_010_000 + (index as u64 - 3_701) * 10_000,
        _ => u64::MAX,
    }
}

#[derive(Default)]
struct RouteResult {
    latencies: LatencyHistogram,
    errors: u64,
}

struct WorkerResult {
    routes: Vec<RouteResult>,
}

#[derive(Serialize)]
struct EnvironmentRecord<'a> {
    schema_version: u32,
    kind: &'static str,
    scenario: &'a str,
    protocol: Protocol,
    address: &'a str,
    concurrency: usize,
    connections: usize,
    client_threads: usize,
    os: &'static str,
    arch: &'static str,
}

#[derive(Serialize)]
struct MeasurementRecord<'a> {
    schema_version: u32,
    kind: &'static str,
    scenario: &'a str,
    protocol: Protocol,
    route: &'a str,
    requests: u64,
    errors: u64,
    elapsed_ms: f64,
    requests_per_second: f64,
    latency_ms_mean: f64,
    latency_ms_p50: f64,
    latency_ms_p95: f64,
    latency_ms_p99: f64,
    latency_ms_max: f64,
}

impl WorkerResult {
    fn new(route_count: usize) -> Self {
        Self {
            routes: (0..route_count).map(|_| RouteResult::default()).collect(),
        }
    }

    fn record(
        &mut self,
        route_index: usize,
        started: Instant,
        result: Result<StatusCode, DynError>,
    ) -> bool {
        let route = &mut self.routes[route_index];
        match result {
            Ok(StatusCode::OK) => {
                route
                    .latencies
                    .record(u64::try_from(started.elapsed().as_nanos()).unwrap_or(u64::MAX));
                true
            }
            Ok(_) | Err(_) => {
                route.errors += 1;
                false
            }
        }
    }
}

fn usage() -> &'static str {
    "Usage: benchmark-driver [options]

Options:
  --scenario-file PATH       Read a versioned JSON scenario
  --jsonl                    Emit versioned JSONL records on stdout
  --name NAME                Stable scenario name for result records
  --sse-events COUNT         Read one finite SSE response per worker
  --sse-hold                 Hold each SSE response open for --duration
  --accept-encoding VALUE    identity or br for SSE responses
  --protocol http1|http2
  --address HOST:PORT
  --path /PATH
  --mixed                    80% /fast, 10% /effect-10, 10% /effect-50
  --routes /PATH=WEIGHT,...  Arbitrary weighted route mixture
  --allow-errors             Report non-200 responses without exiting nonzero
  --error-backoff-ms COUNT   Pause a worker after a failed request
  --duration SECONDS
  --timeout SECONDS
  --concurrency COUNT
  --connections COUNT       HTTP/2 TCP connections (ignored for HTTP/1.1)
  --threads COUNT
  --help
"
}

fn parse_value<T>(flag: &str, value: Option<String>) -> Result<T, CliError>
where
    T: std::str::FromStr,
    T::Err: fmt::Display,
{
    let value = value.ok_or_else(|| CliError(format!("{flag} requires a value")))?;
    value
        .parse()
        .map_err(|error| CliError(format!("invalid {flag} value {value:?}: {error}")))
}

fn parse_args() -> Result<Config, CliError> {
    let mut config = Config {
        name: "ad-hoc".to_owned(),
        workload: WorkloadKind::Request,
        protocol: Protocol::Http1,
        address: "127.0.0.1:8000".to_owned(),
        routes: vec![Route {
            path: "/fast".to_owned(),
            weight: 1,
        }],
        duration: Duration::from_secs(10),
        request_timeout: Duration::from_secs(5),
        concurrency: 64,
        connections: 1,
        threads: 4,
        allow_errors: false,
        error_backoff: Duration::ZERO,
        jsonl: false,
        expected_events: 0,
        accept_encoding: "identity".to_owned(),
    };
    let mut args = env::args().skip(1);
    while let Some(flag) = args.next() {
        match flag.as_str() {
            "--scenario-file" => {
                let path = args
                    .next()
                    .ok_or_else(|| CliError("--scenario-file requires a value".to_owned()))?;
                let bytes = fs::read(&path).map_err(|error| {
                    CliError(format!("failed to read scenario {path:?}: {error}"))
                })?;
                let scenario: ScenarioFile = serde_json::from_slice(&bytes)
                    .map_err(|error| CliError(format!("invalid scenario {path:?}: {error}")))?;
                if scenario.schema_version != SCHEMA_VERSION {
                    return Err(CliError(format!(
                        "unsupported scenario schema version {}; expected {SCHEMA_VERSION}",
                        scenario.schema_version
                    )));
                }
                config = Config::from(scenario);
            }
            "--jsonl" => config.jsonl = true,
            "--name" => {
                config.name = args
                    .next()
                    .ok_or_else(|| CliError("--name requires a value".to_owned()))?;
            }
            "--sse-events" => {
                config.workload = WorkloadKind::Sse;
                config.expected_events = parse_value(&flag, args.next())?;
            }
            "--sse-hold" => {
                config.workload = WorkloadKind::SseHold;
                config.expected_events = 1;
            }
            "--accept-encoding" => {
                config.accept_encoding = args
                    .next()
                    .ok_or_else(|| CliError("--accept-encoding requires a value".to_owned()))?;
            }
            "--protocol" => {
                let value = args
                    .next()
                    .ok_or_else(|| CliError("--protocol requires a value".to_owned()))?;
                config.protocol = Protocol::parse(&value)?;
            }
            "--address" => {
                config.address = args
                    .next()
                    .ok_or_else(|| CliError("--address requires a value".to_owned()))?;
            }
            "--path" => {
                let path = args
                    .next()
                    .ok_or_else(|| CliError("--path requires a value".to_owned()))?;
                config.routes = vec![Route { path, weight: 1 }];
            }
            "--mixed" => {
                config.routes = vec![
                    Route {
                        path: "/fast".to_owned(),
                        weight: 80,
                    },
                    Route {
                        path: "/effect-10".to_owned(),
                        weight: 10,
                    },
                    Route {
                        path: "/effect-50".to_owned(),
                        weight: 10,
                    },
                ];
            }
            "--routes" => {
                let routes = args
                    .next()
                    .ok_or_else(|| CliError("--routes requires a value".to_owned()))?;
                config.routes = parse_routes(&routes)?;
            }
            "--allow-errors" => config.allow_errors = true,
            "--error-backoff-ms" => {
                config.error_backoff = Duration::from_millis(parse_value(&flag, args.next())?);
            }
            "--duration" => {
                config.duration = Duration::from_secs(parse_value(&flag, args.next())?);
            }
            "--timeout" => {
                config.request_timeout = Duration::from_secs(parse_value(&flag, args.next())?);
            }
            "--concurrency" => config.concurrency = parse_value(&flag, args.next())?,
            "--connections" => config.connections = parse_value(&flag, args.next())?,
            "--threads" => config.threads = parse_value(&flag, args.next())?,
            "--help" | "-h" => {
                print!("{}", usage());
                std::process::exit(0);
            }
            _ => {
                return Err(CliError(format!(
                    "unknown argument {flag:?}\n\n{}",
                    usage()
                )))
            }
        }
    }

    if config.name.is_empty() || config.address.is_empty() {
        return Err(CliError(
            "scenario name and server address must not be empty".to_owned(),
        ));
    }
    if config.routes.is_empty()
        || config
            .routes
            .iter()
            .any(|route| !route.path.starts_with('/') || route.weight == 0)
    {
        return Err(CliError(
            "at least one route is required; paths begin with '/' and weights are positive"
                .to_owned(),
        ));
    }
    config
        .routes
        .iter()
        .try_fold(0u64, |total, route| total.checked_add(route.weight))
        .ok_or_else(|| CliError("route weights overflow u64".to_owned()))?;
    if config.duration.is_zero()
        || config.request_timeout.is_zero()
        || config.concurrency == 0
        || config.connections == 0
        || config.threads == 0
    {
        return Err(CliError(
            "duration, timeout, concurrency, connections, and threads must be positive".to_owned(),
        ));
    }
    if config.connections > config.concurrency {
        return Err(CliError(
            "--connections cannot exceed --concurrency".to_owned(),
        ));
    }
    if config.concurrency > MAX_CONCURRENCY || config.threads > MAX_CLIENT_THREADS {
        return Err(CliError(format!(
            "concurrency must not exceed {MAX_CONCURRENCY} and threads must not exceed {MAX_CLIENT_THREADS}"
        )));
    }
    if config.duration > MAX_DURATION || config.request_timeout > MAX_DURATION {
        return Err(CliError(
            "duration and request timeout must not exceed 24 hours".to_owned(),
        ));
    }
    if matches!(config.workload, WorkloadKind::Sse | WorkloadKind::SseHold) {
        if config.routes.len() != 1 || config.expected_events == 0 {
            return Err(CliError(
                "SSE scenarios require one route and a positive expected event count".to_owned(),
            ));
        }
        if !matches!(config.accept_encoding.as_str(), "identity" | "br") {
            return Err(CliError(
                "SSE --accept-encoding must be identity or br".to_owned(),
            ));
        }
    }
    Ok(config)
}

impl From<ScenarioFile> for Config {
    fn from(scenario: ScenarioFile) -> Self {
        Self {
            name: scenario.name,
            workload: scenario.workload,
            protocol: scenario.protocol,
            address: scenario.address,
            routes: scenario.routes,
            duration: Duration::from_millis(scenario.duration_ms),
            request_timeout: Duration::from_millis(scenario.request_timeout_ms),
            concurrency: scenario.concurrency,
            connections: scenario.connections,
            threads: scenario.threads,
            allow_errors: scenario.allow_errors,
            error_backoff: Duration::from_millis(scenario.error_backoff_ms),
            jsonl: true,
            expected_events: scenario.expected_events,
            accept_encoding: scenario.accept_encoding,
        }
    }
}

fn parse_routes(value: &str) -> Result<Vec<Route>, CliError> {
    let mut routes = Vec::new();
    for raw_route in value.split(',') {
        let (path, raw_weight) = raw_route.rsplit_once('=').ok_or_else(|| {
            CliError(format!(
                "invalid weighted route {raw_route:?}; expected /PATH=WEIGHT"
            ))
        })?;
        if !path.starts_with('/') {
            return Err(CliError(format!(
                "route path must begin with '/': {path:?}"
            )));
        }
        let weight = raw_weight.parse::<u64>().map_err(|error| {
            CliError(format!(
                "invalid route weight {raw_weight:?} for {path:?}: {error}"
            ))
        })?;
        if weight == 0 {
            return Err(CliError(format!(
                "route weight must be positive for {path:?}"
            )));
        }
        routes.push(Route {
            path: path.to_owned(),
            weight,
        });
    }
    if routes.is_empty() {
        return Err(CliError(
            "--routes must contain at least one route".to_owned(),
        ));
    }
    Ok(routes)
}

fn request(config: &Config, path: &str) -> Result<Request<Empty<Bytes>>, DynError> {
    let uri = match config.protocol {
        Protocol::Http1 => path.to_owned(),
        Protocol::Http2 => format!("http://{}{path}", config.address),
    };
    let mut builder = Request::builder()
        .method("GET")
        .uri(uri)
        .header("host", &config.address);
    if matches!(config.workload, WorkloadKind::Sse | WorkloadKind::SseHold) {
        builder = builder
            .header("accept", "text/event-stream")
            .header("accept-encoding", config.accept_encoding.as_str());
    }
    Ok(builder.body(Empty::new())?)
}

fn select_route(config: &Config, random: &mut u64) -> usize {
    *random ^= *random << 13;
    *random ^= *random >> 7;
    *random ^= *random << 17;
    let total_weight = config.routes.iter().map(|route| route.weight).sum::<u64>();
    let sample = *random % total_weight;
    let mut boundary = 0;
    for (index, route) in config.routes.iter().enumerate() {
        boundary += route.weight;
        if sample < boundary {
            return index;
        }
    }
    unreachable!("positive route weights cover every sample")
}

async fn exchange<B>(
    response: Result<hyper::Response<B>, hyper::Error>,
) -> Result<StatusCode, DynError>
where
    B: hyper::body::Body<Data = Bytes> + Unpin,
    B::Error: Error + Send + Sync + 'static,
{
    let response = response?;
    let status = response.status();
    response.into_body().collect().await?;
    Ok(status)
}

async fn http1_worker(
    mut sender: http1::SendRequest<Empty<Bytes>>,
    config: Arc<Config>,
    barrier: Arc<Barrier>,
    seed: u64,
) -> WorkerResult {
    let mut result = WorkerResult::new(config.routes.len());
    let mut random = seed;
    barrier.wait().await;
    let deadline = Instant::now() + config.duration;
    while Instant::now() < deadline {
        let route_index = select_route(&config, &mut random);
        let started = Instant::now();
        let exchange = async {
            let request = request(&config, &config.routes[route_index].path)?;
            exchange(sender.send_request(request).await).await
        };
        let succeeded = match timeout(config.request_timeout, exchange).await {
            Ok(outcome) => result.record(route_index, started, outcome),
            Err(error) => result.record(route_index, started, Err(Box::new(error))),
        };
        if !succeeded && !config.error_backoff.is_zero() {
            tokio::time::sleep(config.error_backoff).await;
        }
    }
    result
}

async fn http2_worker(
    mut sender: http2::SendRequest<Empty<Bytes>>,
    config: Arc<Config>,
    barrier: Arc<Barrier>,
    seed: u64,
) -> WorkerResult {
    let mut result = WorkerResult::new(config.routes.len());
    let mut random = seed;
    barrier.wait().await;
    let deadline = Instant::now() + config.duration;
    while Instant::now() < deadline {
        let route_index = select_route(&config, &mut random);
        let started = Instant::now();
        let exchange = async {
            let request = request(&config, &config.routes[route_index].path)?;
            exchange(sender.send_request(request).await).await
        };
        let succeeded = match timeout(config.request_timeout, exchange).await {
            Ok(outcome) => result.record(route_index, started, outcome),
            Err(error) => result.record(route_index, started, Err(Box::new(error))),
        };
        if !succeeded && !config.error_backoff.is_zero() {
            tokio::time::sleep(config.error_backoff).await;
        }
    }
    result
}

async fn open_http1(
    config: &Config,
) -> Result<
    (
        http1::SendRequest<Empty<Bytes>>,
        JoinHandle<Result<(), hyper::Error>>,
    ),
    DynError,
> {
    let stream = TcpStream::connect(&config.address).await?;
    stream.set_nodelay(true)?;
    let (sender, connection) = http1::handshake(TokioIo::new(stream)).await?;
    let task = tokio::spawn(connection);
    Ok((sender, task))
}

async fn open_http2(
    config: &Config,
) -> Result<
    (
        http2::SendRequest<Empty<Bytes>>,
        JoinHandle<Result<(), hyper::Error>>,
    ),
    DynError,
> {
    let stream = TcpStream::connect(&config.address).await?;
    stream.set_nodelay(true)?;
    let (sender, connection) = http2::handshake(TokioExecutor::new(), TokioIo::new(stream)).await?;
    let task = tokio::spawn(connection);
    Ok((sender, task))
}

#[derive(Default)]
struct SseWorkerResult {
    first_event: LatencyHistogram,
    inter_event_gap: LatencyHistogram,
    completion: LatencyHistogram,
    streams: u64,
    events: u64,
    encoded_bytes: u64,
    decoded_bytes: u64,
    errors: u64,
    first_error: Option<String>,
}

impl SseWorkerResult {
    fn merge(&mut self, other: &Self) {
        self.first_event.merge(&other.first_event);
        self.inter_event_gap.merge(&other.inter_event_gap);
        self.completion.merge(&other.completion);
        self.streams = self.streams.saturating_add(other.streams);
        self.events = self.events.saturating_add(other.events);
        self.encoded_bytes = self.encoded_bytes.saturating_add(other.encoded_bytes);
        self.decoded_bytes = self.decoded_bytes.saturating_add(other.decoded_bytes);
        self.errors = self.errors.saturating_add(other.errors);
        if self.first_error.is_none() {
            self.first_error.clone_from(&other.first_error);
        }
    }
}

struct SseEventCounter {
    pending: Vec<u8>,
    events: usize,
    decoded_bytes: usize,
    started: Instant,
    last_event: Option<Instant>,
    first_event: LatencyHistogram,
    inter_event_gap: LatencyHistogram,
}

impl SseEventCounter {
    fn new(started: Instant) -> Self {
        Self {
            pending: Vec::with_capacity(16 * 1024),
            events: 0,
            decoded_bytes: 0,
            started,
            last_event: None,
            first_event: LatencyHistogram::default(),
            inter_event_gap: LatencyHistogram::default(),
        }
    }

    fn finish(mut self) -> Result<Self, io::Error> {
        if self.pending.iter().any(|byte| !byte.is_ascii_whitespace()) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "SSE response ended with an incomplete frame",
            ));
        }
        self.pending.clear();
        Ok(self)
    }

    fn parse_pending(&mut self) -> Result<(), io::Error> {
        let mut consumed = 0;
        while let Some((relative_end, delimiter_bytes)) =
            next_sse_delimiter(&self.pending[consumed..])
        {
            let frame_end = consumed + relative_end;
            if validate_sse_frame(&self.pending[consumed..frame_end])? {
                let now = Instant::now();
                if let Some(previous) = self.last_event {
                    self.inter_event_gap.record(
                        u64::try_from(now.duration_since(previous).as_nanos()).unwrap_or(u64::MAX),
                    );
                } else {
                    self.first_event.record(
                        u64::try_from(now.duration_since(self.started).as_nanos())
                            .unwrap_or(u64::MAX),
                    );
                }
                self.last_event = Some(now);
                self.events += 1;
            }
            consumed = frame_end + delimiter_bytes;
        }
        if consumed > 0 {
            self.pending.drain(..consumed);
        }
        if self.pending.len() > 32 * 1024 * 1024 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "SSE frame exceeds the benchmark driver's 32 MiB safety bound",
            ));
        }
        Ok(())
    }
}

impl Write for SseEventCounter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.decoded_bytes = self.decoded_bytes.saturating_add(bytes.len());
        self.pending.extend_from_slice(bytes);
        self.parse_pending()?;
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

fn next_sse_delimiter(bytes: &[u8]) -> Option<(usize, usize)> {
    for index in 0..bytes.len() {
        if bytes[index..].starts_with(b"\r\n\r\n") {
            return Some((index, 4));
        }
        if bytes[index..].starts_with(b"\n\n") {
            return Some((index, 2));
        }
    }
    None
}

fn validate_sse_frame(bytes: &[u8]) -> Result<bool, io::Error> {
    if bytes.is_empty() || bytes.starts_with(b":") {
        return Ok(false);
    }
    let text = std::str::from_utf8(bytes)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
    let has_event = text
        .lines()
        .any(|line| line.trim_end_matches('\r') == "event: benchmark-event");
    let has_data = text
        .lines()
        .any(|line| line.trim_end_matches('\r').starts_with("data: "));
    if !has_event || !has_data {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "unexpected SSE frame: {:?}",
                text.chars().take(120).collect::<String>()
            ),
        ));
    }
    Ok(true)
}

fn validate_sse_response_headers<B>(
    response: &hyper::Response<B>,
    config: &Config,
) -> Result<Option<String>, DynError> {
    if response.status() != StatusCode::OK {
        return Err(CliError(format!(
            "SSE response returned status {}",
            response.status()
        ))
        .into());
    }
    let content_type = response
        .headers()
        .get(hyper::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    if !content_type.starts_with("text/event-stream") {
        return Err(CliError(format!(
            "SSE response has unexpected content type {content_type:?}"
        ))
        .into());
    }
    let encoding = response
        .headers()
        .get(hyper::header::CONTENT_ENCODING)
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned);
    match (config.accept_encoding.as_str(), encoding.as_deref()) {
        ("identity", None) | ("identity", Some("identity")) | ("br", Some("br")) => {}
        _ => {
            return Err(CliError(format!(
                "SSE response encoding {encoding:?} does not match requested {:?}",
                config.accept_encoding
            ))
            .into())
        }
    }
    Ok(encoding)
}

async fn read_sse_response<B>(
    response: hyper::Response<B>,
    config: &Config,
    started: Instant,
) -> Result<(SseEventCounter, usize), DynError>
where
    B: hyper::body::Body<Data = Bytes> + Unpin,
    B::Error: Error + Send + Sync + 'static,
{
    let encoding = validate_sse_response_headers(&response, config)?;
    let mut body = response.into_body();
    let mut encoded_bytes = 0usize;
    let counter = if encoding.as_deref() == Some("br") {
        let mut decoder = brotli::DecompressorWriter::new(SseEventCounter::new(started), 64 * 1024);
        while let Some(frame) = body.frame().await {
            let frame = frame?;
            if let Ok(data) = frame.into_data() {
                encoded_bytes = encoded_bytes.saturating_add(data.len());
                decoder.write_all(&data)?;
            }
        }
        decoder.close()?;
        decoder
            .into_inner()
            .map_err(|_| CliError("failed to finish Brotli SSE decoding".to_owned()))?
            .finish()?
    } else {
        let mut counter = SseEventCounter::new(started);
        while let Some(frame) = body.frame().await {
            let frame = frame?;
            if let Ok(data) = frame.into_data() {
                encoded_bytes = encoded_bytes.saturating_add(data.len());
                counter.write_all(&data)?;
            }
        }
        counter.finish()?
    };
    if counter.events != config.expected_events {
        return Err(CliError(format!(
            "expected {} SSE events, received {}",
            config.expected_events, counter.events
        ))
        .into());
    }
    Ok((counter, encoded_bytes))
}

async fn http1_sse_worker(
    mut sender: http1::SendRequest<Empty<Bytes>>,
    config: Arc<Config>,
    barrier: Arc<Barrier>,
) -> SseWorkerResult {
    let mut result = SseWorkerResult::default();
    barrier.wait().await;
    let started = Instant::now();
    let exchange = async {
        let request = request(&config, &config.routes[0].path)?;
        let response = sender.send_request(request).await?;
        read_sse_response(response, &config, started).await
    };
    match timeout(config.request_timeout, exchange).await {
        Ok(Ok((counter, encoded_bytes))) => {
            result.streams = 1;
            result.events = counter.events as u64;
            result.encoded_bytes = encoded_bytes as u64;
            result.decoded_bytes = counter.decoded_bytes as u64;
            result.first_event = counter.first_event;
            result.inter_event_gap = counter.inter_event_gap;
            result
                .completion
                .record(u64::try_from(started.elapsed().as_nanos()).unwrap_or(u64::MAX));
        }
        Ok(Err(error)) => {
            result.errors = 1;
            result.first_error = Some(error.to_string());
        }
        Err(error) => {
            result.errors = 1;
            result.first_error = Some(error.to_string());
        }
    }
    result
}

async fn http2_sse_worker(
    mut sender: http2::SendRequest<Empty<Bytes>>,
    config: Arc<Config>,
    barrier: Arc<Barrier>,
) -> SseWorkerResult {
    let mut result = SseWorkerResult::default();
    barrier.wait().await;
    let started = Instant::now();
    let exchange = async {
        let request = request(&config, &config.routes[0].path)?;
        let response = sender.send_request(request).await?;
        read_sse_response(response, &config, started).await
    };
    match timeout(config.request_timeout, exchange).await {
        Ok(Ok((counter, encoded_bytes))) => {
            result.streams = 1;
            result.events = counter.events as u64;
            result.encoded_bytes = encoded_bytes as u64;
            result.decoded_bytes = counter.decoded_bytes as u64;
            result.first_event = counter.first_event;
            result.inter_event_gap = counter.inter_event_gap;
            result
                .completion
                .record(u64::try_from(started.elapsed().as_nanos()).unwrap_or(u64::MAX));
        }
        Ok(Err(error)) => {
            result.errors = 1;
            result.first_error = Some(error.to_string());
        }
        Err(error) => {
            result.errors = 1;
            result.first_error = Some(error.to_string());
        }
    }
    result
}

#[derive(Default)]
struct SseHoldWorkerResult {
    first_byte: LatencyHistogram,
    streams: u64,
    encoded_bytes: u64,
    errors: u64,
    first_error: Option<String>,
}

impl SseHoldWorkerResult {
    fn merge(&mut self, other: &Self) {
        self.first_byte.merge(&other.first_byte);
        self.streams = self.streams.saturating_add(other.streams);
        self.encoded_bytes = self.encoded_bytes.saturating_add(other.encoded_bytes);
        self.errors = self.errors.saturating_add(other.errors);
        if self.first_error.is_none() {
            self.first_error.clone_from(&other.first_error);
        }
    }
}

async fn hold_open_response<B>(
    response: hyper::Response<B>,
    config: &Config,
) -> Result<(B, usize), DynError>
where
    B: hyper::body::Body<Data = Bytes> + Unpin,
    B::Error: Error + Send + Sync + 'static,
{
    validate_sse_response_headers(&response, config)?;
    let mut body = response.into_body();
    let mut encoded_bytes = 0usize;
    while let Some(frame) = body.frame().await {
        let frame = frame?;
        if let Ok(data) = frame.into_data() {
            encoded_bytes = encoded_bytes.saturating_add(data.len());
            if !data.is_empty() {
                return Ok((body, encoded_bytes));
            }
        }
    }
    Err(CliError("SSE response ended before its first body bytes".to_owned()).into())
}

async fn http1_sse_hold_worker(
    mut sender: http1::SendRequest<Empty<Bytes>>,
    config: Arc<Config>,
    start: Arc<Barrier>,
    ready: Arc<Barrier>,
    release: Arc<Barrier>,
    opened: Arc<AtomicUsize>,
) -> SseHoldWorkerResult {
    let mut result = SseHoldWorkerResult::default();
    start.wait().await;
    let started = Instant::now();
    let exchange = async {
        let request = request(&config, &config.routes[0].path)?;
        let response = sender.send_request(request).await?;
        hold_open_response(response, &config).await
    };
    let held_body = match timeout(config.request_timeout, exchange).await {
        Ok(Ok((body, encoded_bytes))) => {
            result.streams = 1;
            result.encoded_bytes = encoded_bytes as u64;
            result
                .first_byte
                .record(u64::try_from(started.elapsed().as_nanos()).unwrap_or(u64::MAX));
            opened.fetch_add(1, Ordering::Relaxed);
            Some(body)
        }
        Ok(Err(error)) => {
            result.errors = 1;
            result.first_error = Some(error.to_string());
            None
        }
        Err(error) => {
            result.errors = 1;
            result.first_error = Some(error.to_string());
            None
        }
    };
    ready.wait().await;
    release.wait().await;
    drop(held_body);
    result
}

async fn http2_sse_hold_worker(
    mut sender: http2::SendRequest<Empty<Bytes>>,
    config: Arc<Config>,
    start: Arc<Barrier>,
    ready: Arc<Barrier>,
    release: Arc<Barrier>,
    opened: Arc<AtomicUsize>,
) -> SseHoldWorkerResult {
    let mut result = SseHoldWorkerResult::default();
    start.wait().await;
    let started = Instant::now();
    let exchange = async {
        let request = request(&config, &config.routes[0].path)?;
        let response = sender.send_request(request).await?;
        hold_open_response(response, &config).await
    };
    let held_body = match timeout(config.request_timeout, exchange).await {
        Ok(Ok((body, encoded_bytes))) => {
            result.streams = 1;
            result.encoded_bytes = encoded_bytes as u64;
            result
                .first_byte
                .record(u64::try_from(started.elapsed().as_nanos()).unwrap_or(u64::MAX));
            opened.fetch_add(1, Ordering::Relaxed);
            Some(body)
        }
        Ok(Err(error)) => {
            result.errors = 1;
            result.first_error = Some(error.to_string());
            None
        }
        Err(error) => {
            result.errors = 1;
            result.first_error = Some(error.to_string());
            None
        }
    };
    ready.wait().await;
    release.wait().await;
    drop(held_body);
    result
}

#[derive(Serialize)]
struct PhaseRecord<'a> {
    schema_version: u32,
    kind: &'static str,
    scenario: &'a str,
    phase: &'static str,
    streams: usize,
}

#[derive(Serialize)]
struct SseHoldMeasurementRecord<'a> {
    schema_version: u32,
    kind: &'static str,
    scenario: &'a str,
    protocol: Protocol,
    route: &'a str,
    requested_streams: usize,
    opened_streams: u64,
    errors: u64,
    error_sample: Option<&'a str>,
    encoded_bytes_before_hold: u64,
    open_elapsed_ms: f64,
    hold_ms: f64,
    first_byte_ms_p50: f64,
    first_byte_ms_p95: f64,
    first_byte_ms_p99: f64,
    first_byte_ms_max: f64,
}

async fn run_sse_hold(config: Config) -> Result<(), DynError> {
    let config = Arc::new(config);
    let start = Arc::new(Barrier::new(config.concurrency + 1));
    let ready = Arc::new(Barrier::new(config.concurrency + 1));
    let release = Arc::new(Barrier::new(config.concurrency + 1));
    let opened = Arc::new(AtomicUsize::new(0));
    let mut connection_tasks = Vec::new();
    let mut workers = Vec::with_capacity(config.concurrency);
    match config.protocol {
        Protocol::Http1 => {
            for _ in 0..config.concurrency {
                let (sender, connection) = open_http1(&config).await?;
                connection_tasks.push(connection);
                workers.push(tokio::spawn(http1_sse_hold_worker(
                    sender,
                    Arc::clone(&config),
                    Arc::clone(&start),
                    Arc::clone(&ready),
                    Arc::clone(&release),
                    Arc::clone(&opened),
                )));
            }
        }
        Protocol::Http2 => {
            let mut senders = Vec::with_capacity(config.connections);
            for _ in 0..config.connections {
                let (sender, connection) = open_http2(&config).await?;
                senders.push(sender);
                connection_tasks.push(connection);
            }
            for index in 0..config.concurrency {
                workers.push(tokio::spawn(http2_sse_hold_worker(
                    senders[index % senders.len()].clone(),
                    Arc::clone(&config),
                    Arc::clone(&start),
                    Arc::clone(&ready),
                    Arc::clone(&release),
                    Arc::clone(&opened),
                )));
            }
        }
    }

    let opened_at = Instant::now();
    start.wait().await;
    ready.wait().await;
    let open_elapsed = opened_at.elapsed();
    if config.jsonl {
        emit_json(&EnvironmentRecord {
            schema_version: SCHEMA_VERSION,
            kind: "environment",
            scenario: &config.name,
            protocol: config.protocol,
            address: &config.address,
            concurrency: config.concurrency,
            connections: match config.protocol {
                Protocol::Http1 => config.concurrency,
                Protocol::Http2 => config.connections,
            },
            client_threads: config.threads,
            os: env::consts::OS,
            arch: env::consts::ARCH,
        })?;
        emit_json(&PhaseRecord {
            schema_version: SCHEMA_VERSION,
            kind: "phase",
            scenario: &config.name,
            phase: "streams_ready",
            streams: opened.load(Ordering::Relaxed),
        })?;
    }
    let hold_started = Instant::now();
    tokio::time::sleep(config.duration).await;
    let held_for = hold_started.elapsed();
    release.wait().await;

    let mut aggregate = SseHoldWorkerResult::default();
    for worker in workers {
        aggregate.merge(&worker.await?);
    }
    for task in connection_tasks {
        task.abort();
    }
    let record = SseHoldMeasurementRecord {
        schema_version: SCHEMA_VERSION,
        kind: "sse_hold_measurement",
        scenario: &config.name,
        protocol: config.protocol,
        route: &config.routes[0].path,
        requested_streams: config.concurrency,
        opened_streams: aggregate.streams,
        errors: aggregate.errors,
        error_sample: aggregate.first_error.as_deref(),
        encoded_bytes_before_hold: aggregate.encoded_bytes,
        open_elapsed_ms: open_elapsed.as_secs_f64() * 1_000.0,
        hold_ms: held_for.as_secs_f64() * 1_000.0,
        first_byte_ms_p50: aggregate.first_byte.percentile_ms(50.0),
        first_byte_ms_p95: aggregate.first_byte.percentile_ms(95.0),
        first_byte_ms_p99: aggregate.first_byte.percentile_ms(99.0),
        first_byte_ms_max: aggregate.first_byte.percentile_ms(100.0),
    };
    if config.jsonl {
        emit_json(&record)?;
    }
    human_line(
        config.jsonl,
        format_args!(
            "sse-hold route={} opened={}/{} errors={} open_ms={:.1} first_byte_ms_p99={:.3}",
            record.route,
            record.opened_streams,
            record.requested_streams,
            record.errors,
            record.open_elapsed_ms,
            record.first_byte_ms_p99,
        ),
    )?;
    if aggregate.errors > 0 && !config.allow_errors {
        return Err(CliError(format!("{} SSE streams failed to open", aggregate.errors)).into());
    }
    Ok(())
}

#[derive(Serialize)]
struct SseMeasurementRecord<'a> {
    schema_version: u32,
    kind: &'static str,
    scenario: &'a str,
    protocol: Protocol,
    route: &'a str,
    streams: u64,
    events: u64,
    errors: u64,
    error_sample: Option<&'a str>,
    encoded_bytes: u64,
    decoded_bytes: u64,
    elapsed_ms: f64,
    events_per_second: f64,
    completion_ms_p50: f64,
    completion_ms_p95: f64,
    completion_ms_p99: f64,
    completion_ms_max: f64,
    first_event_ms_p50: f64,
    first_event_ms_p95: f64,
    first_event_ms_p99: f64,
    inter_event_gap_ms_p50: f64,
    inter_event_gap_ms_p95: f64,
    inter_event_gap_ms_p99: f64,
}

async fn run_sse(config: Config) -> Result<(), DynError> {
    let config = Arc::new(config);
    let barrier = Arc::new(Barrier::new(config.concurrency + 1));
    let mut connection_tasks = Vec::new();
    let mut workers = Vec::with_capacity(config.concurrency);
    match config.protocol {
        Protocol::Http1 => {
            for _ in 0..config.concurrency {
                let (sender, connection) = open_http1(&config).await?;
                connection_tasks.push(connection);
                workers.push(tokio::spawn(http1_sse_worker(
                    sender,
                    Arc::clone(&config),
                    Arc::clone(&barrier),
                )));
            }
        }
        Protocol::Http2 => {
            let mut senders = Vec::with_capacity(config.connections);
            for _ in 0..config.connections {
                let (sender, connection) = open_http2(&config).await?;
                senders.push(sender);
                connection_tasks.push(connection);
            }
            for index in 0..config.concurrency {
                workers.push(tokio::spawn(http2_sse_worker(
                    senders[index % senders.len()].clone(),
                    Arc::clone(&config),
                    Arc::clone(&barrier),
                )));
            }
        }
    }
    let started = Instant::now();
    barrier.wait().await;
    if config.jsonl {
        emit_json(&PhaseRecord {
            schema_version: SCHEMA_VERSION,
            kind: "phase",
            scenario: &config.name,
            phase: "load_started",
            streams: config.concurrency,
        })?;
    }
    let mut aggregate = SseWorkerResult::default();
    for worker in workers {
        aggregate.merge(&worker.await?);
    }
    let elapsed = started.elapsed();
    for task in connection_tasks {
        task.abort();
    }
    let record = SseMeasurementRecord {
        schema_version: SCHEMA_VERSION,
        kind: "sse_measurement",
        scenario: &config.name,
        protocol: config.protocol,
        route: &config.routes[0].path,
        streams: aggregate.streams,
        events: aggregate.events,
        errors: aggregate.errors,
        error_sample: aggregate.first_error.as_deref(),
        encoded_bytes: aggregate.encoded_bytes,
        decoded_bytes: aggregate.decoded_bytes,
        elapsed_ms: elapsed.as_secs_f64() * 1_000.0,
        events_per_second: aggregate.events as f64 / elapsed.as_secs_f64(),
        completion_ms_p50: aggregate.completion.percentile_ms(50.0),
        completion_ms_p95: aggregate.completion.percentile_ms(95.0),
        completion_ms_p99: aggregate.completion.percentile_ms(99.0),
        completion_ms_max: aggregate.completion.percentile_ms(100.0),
        first_event_ms_p50: aggregate.first_event.percentile_ms(50.0),
        first_event_ms_p95: aggregate.first_event.percentile_ms(95.0),
        first_event_ms_p99: aggregate.first_event.percentile_ms(99.0),
        inter_event_gap_ms_p50: aggregate.inter_event_gap.percentile_ms(50.0),
        inter_event_gap_ms_p95: aggregate.inter_event_gap.percentile_ms(95.0),
        inter_event_gap_ms_p99: aggregate.inter_event_gap.percentile_ms(99.0),
    };
    if config.jsonl {
        emit_json(&EnvironmentRecord {
            schema_version: SCHEMA_VERSION,
            kind: "environment",
            scenario: &config.name,
            protocol: config.protocol,
            address: &config.address,
            concurrency: config.concurrency,
            connections: match config.protocol {
                Protocol::Http1 => config.concurrency,
                Protocol::Http2 => config.connections,
            },
            client_threads: config.threads,
            os: env::consts::OS,
            arch: env::consts::ARCH,
        })?;
        emit_json(&record)?;
    }
    human_line(
        config.jsonl,
        format_args!(
            "sse route={} streams={} events={} errors={} events_per_second={:.1} completion_ms_p99={:.3}",
            record.route,
            record.streams,
            record.events,
            record.errors,
            record.events_per_second,
            record.completion_ms_p99,
        ),
    )?;
    if aggregate.errors > 0 && !config.allow_errors {
        return Err(CliError(format!("{} SSE streams failed", aggregate.errors)).into());
    }
    Ok(())
}

async fn run(config: Config) -> Result<(), DynError> {
    let config = Arc::new(config);
    let barrier = Arc::new(Barrier::new(config.concurrency + 1));
    let mut connection_tasks = Vec::new();
    let mut workers = Vec::with_capacity(config.concurrency);

    match config.protocol {
        Protocol::Http1 => {
            for index in 0..config.concurrency {
                let (sender, connection) = open_http1(&config).await?;
                connection_tasks.push(connection);
                workers.push(tokio::spawn(http1_worker(
                    sender,
                    Arc::clone(&config),
                    Arc::clone(&barrier),
                    index as u64 + 1,
                )));
            }
        }
        Protocol::Http2 => {
            let mut senders = Vec::with_capacity(config.connections);
            for _ in 0..config.connections {
                let (sender, connection) = open_http2(&config).await?;
                senders.push(sender);
                connection_tasks.push(connection);
            }
            for index in 0..config.concurrency {
                workers.push(tokio::spawn(http2_worker(
                    senders[index % senders.len()].clone(),
                    Arc::clone(&config),
                    Arc::clone(&barrier),
                    index as u64 + 1,
                )));
            }
        }
    }

    let started = Instant::now();
    barrier.wait().await;
    let mut route_results = (0..config.routes.len())
        .map(|_| RouteResult::default())
        .collect::<Vec<_>>();
    for worker in workers {
        let result = worker.await?;
        for (aggregate, route) in route_results.iter_mut().zip(result.routes) {
            aggregate.latencies.merge(&route.latencies);
            aggregate.errors += route.errors;
        }
    }
    let elapsed = started.elapsed();
    for task in connection_tasks {
        task.abort();
    }

    let mut all_latencies = LatencyHistogram::default();
    for route in &route_results {
        all_latencies.merge(&route.latencies);
    }
    let errors = route_results.iter().map(|route| route.errors).sum::<u64>();
    let connection_count = match config.protocol {
        Protocol::Http1 => config.concurrency,
        Protocol::Http2 => config.connections,
    };
    if config.jsonl {
        emit_json(&EnvironmentRecord {
            schema_version: SCHEMA_VERSION,
            kind: "environment",
            scenario: &config.name,
            protocol: config.protocol,
            address: &config.address,
            concurrency: config.concurrency,
            connections: connection_count,
            client_threads: config.threads,
            os: env::consts::OS,
            arch: env::consts::ARCH,
        })?;
    }
    human_line(
        config.jsonl,
        format_args!(
            "protocol={} workload={} concurrency={} connections={} elapsed_s={:.3}",
            config.protocol.name(),
            if config.routes.len() == 1 {
                config.routes[0].path.as_str()
            } else {
                "mixed"
            },
            config.concurrency,
            connection_count,
            elapsed.as_secs_f64(),
        ),
    )?;
    print_result(&config, "all", &all_latencies, errors, elapsed)?;
    if config.routes.len() > 1 {
        let total_weight = config.routes.iter().map(|route| route.weight).sum::<u64>();
        for (route, result) in config.routes.iter().zip(&route_results) {
            print_result(
                &config,
                &format!(
                    "{}@{:.1}%",
                    route.path,
                    route.weight as f64 * 100.0 / total_weight as f64
                ),
                &result.latencies,
                result.errors,
                elapsed,
            )?;
        }
    }
    if errors > 0 && !config.allow_errors {
        return Err(CliError(format!("{errors} requests failed")).into());
    }
    Ok(())
}

fn print_result(
    config: &Config,
    label: &str,
    latencies: &LatencyHistogram,
    errors: u64,
    elapsed: Duration,
) -> Result<(), DynError> {
    let requests = latencies.count;
    let rps = requests as f64 / elapsed.as_secs_f64();
    let record = MeasurementRecord {
        schema_version: SCHEMA_VERSION,
        kind: "measurement",
        scenario: &config.name,
        protocol: config.protocol,
        route: label,
        requests,
        errors,
        elapsed_ms: elapsed.as_secs_f64() * 1_000.0,
        requests_per_second: rps,
        latency_ms_mean: latencies.mean_ms(),
        latency_ms_p50: latencies.percentile_ms(50.0),
        latency_ms_p95: latencies.percentile_ms(95.0),
        latency_ms_p99: latencies.percentile_ms(99.0),
        latency_ms_max: latencies.percentile_ms(100.0),
    };
    if config.jsonl {
        emit_json(&record)?;
    }
    human_line(
        config.jsonl,
        format_args!(
            "route={} requests={} errors={} rps={:.1} latency_ms_mean={:.3} \
         p50={:.3} p95={:.3} p99={:.3} max={:.3}",
            label,
            requests,
            errors,
            rps,
            record.latency_ms_mean,
            record.latency_ms_p50,
            record.latency_ms_p95,
            record.latency_ms_p99,
            record.latency_ms_max,
        ),
    )?;
    Ok(())
}

fn emit_json(value: &impl Serialize) -> Result<(), DynError> {
    let mut stdout = io::stdout().lock();
    serde_json::to_writer(&mut stdout, value)?;
    stdout.write_all(b"\n")?;
    Ok(())
}

fn human_line(jsonl: bool, arguments: fmt::Arguments<'_>) -> Result<(), DynError> {
    if jsonl {
        let mut stderr = io::stderr().lock();
        stderr.write_fmt(arguments)?;
        stderr.write_all(b"\n")?;
    } else {
        let mut stdout = io::stdout().lock();
        stdout.write_fmt(arguments)?;
        stdout.write_all(b"\n")?;
    }
    Ok(())
}

fn main() -> Result<(), DynError> {
    let config = parse_args()?;
    let threads = config.threads;
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(threads)
        .enable_all()
        .build()?
        .block_on(async move {
            match config.workload {
                WorkloadKind::Request => run(config).await,
                WorkloadKind::Sse => run_sse(config).await,
                WorkloadKind::SseHold => run_sse_hold(config).await,
            }
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounded_histogram_tracks_percentiles_and_merges() {
        let mut left = LatencyHistogram::default();
        left.record(1_000);
        left.record(1_000_000);
        let mut right = LatencyHistogram::default();
        right.record(10_000_000);
        left.merge(&right);

        assert_eq!(left.count, 3);
        assert_eq!(left.max_ns, 10_000_000);
        assert_eq!(left.percentile_ms(50.0), 1.0);
        assert_eq!(left.percentile_ms(100.0), 10.0);

        let mut overflow = LatencyHistogram::default();
        overflow.record(11_000_000_000);
        assert_eq!(overflow.percentile_ms(99.0), 11_000.0);
    }

    #[test]
    fn sse_parser_accepts_crlf_and_lf_frames() {
        let mut counter = SseEventCounter::new(Instant::now());
        counter
            .write_all(b"event: benchmark-event\r\ndata: one\r")
            .unwrap();
        counter
            .write_all(b"\n\r\nevent: benchmark-event\ndata: two\n\n")
            .unwrap();
        assert_eq!(counter.finish().unwrap().events, 2);
    }

    #[test]
    fn sse_parser_rejects_unexpected_events() {
        let mut counter = SseEventCounter::new(Instant::now());
        let error = counter
            .write_all(b"event: other\ndata: one\n\n")
            .unwrap_err();
        assert!(error.to_string().contains("unexpected SSE frame"));
    }

    #[test]
    fn scenario_schema_is_strict_and_versioned() {
        let scenario: ScenarioFile = serde_json::from_str(
            r#"{
                "schema_version": 1,
                "name": "fast",
                "protocol": "http1",
                "routes": [{"path": "/fast", "weight": 1}],
                "duration_ms": 100,
                "concurrency": 2
            }"#,
        )
        .unwrap();
        let config = Config::from(scenario);
        assert_eq!(config.name, "fast");
        assert_eq!(config.concurrency, 2);
        assert!(config.jsonl);

        assert!(serde_json::from_str::<ScenarioFile>(
            r#"{
                "schema_version": 1,
                "name": "bad",
                "protocol": "http1",
                "routes": [],
                "duration_ms": 1,
                "concurrency": 1,
                "unexpected": true
            }"#,
        )
        .is_err());
    }
}
