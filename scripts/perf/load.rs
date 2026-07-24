use bytes::Bytes;
use http_body_util::{BodyExt, Empty};
use hyper::client::conn::{http1, http2};
use hyper::{Request, StatusCode};
use hyper_util::rt::{TokioExecutor, TokioIo};
use std::env;
use std::error::Error;
use std::fmt;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::net::TcpStream;
use tokio::sync::Barrier;
use tokio::task::JoinHandle;
use tokio::time::timeout;

type DynError = Box<dyn Error + Send + Sync>;

#[derive(Clone, Copy, Debug)]
enum Protocol {
    Http1,
    Http2,
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
}

#[derive(Clone, Debug)]
struct Route {
    path: String,
    weight: u64,
}

#[derive(Debug)]
struct CliError(String);

impl fmt::Display for CliError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl Error for CliError {}

#[derive(Default)]
struct RouteResult {
    latencies_ns: Vec<u64>,
    errors: u64,
}

struct WorkerResult {
    routes: Vec<RouteResult>,
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
                    .latencies_ns
                    .push(u64::try_from(started.elapsed().as_nanos()).unwrap_or(u64::MAX));
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
    "Usage: local-load [options]

Options:
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
    };
    let mut args = env::args().skip(1);
    while let Some(flag) = args.next() {
        match flag.as_str() {
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

    if config
        .routes
        .iter()
        .any(|route| !route.path.starts_with('/'))
    {
        return Err(CliError("request paths must begin with '/'".to_owned()));
    }
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
    Ok(config)
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
    Ok(Request::builder()
        .method("GET")
        .uri(uri)
        .header("host", &config.address)
        .body(Empty::new())?)
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
    B: hyper::body::Body,
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
        for (aggregate, mut route) in route_results.iter_mut().zip(result.routes) {
            aggregate.latencies_ns.append(&mut route.latencies_ns);
            aggregate.errors += route.errors;
        }
    }
    let elapsed = started.elapsed();
    for task in connection_tasks {
        task.abort();
    }

    let mut latencies = route_results
        .iter()
        .flat_map(|route| route.latencies_ns.iter().copied())
        .collect::<Vec<_>>();
    let errors = route_results.iter().map(|route| route.errors).sum::<u64>();
    latencies.sort_unstable();
    println!(
        "protocol={} workload={} concurrency={} connections={} elapsed_s={:.3}",
        config.protocol.name(),
        if config.routes.len() == 1 {
            config.routes[0].path.as_str()
        } else {
            "mixed"
        },
        config.concurrency,
        match config.protocol {
            Protocol::Http1 => config.concurrency,
            Protocol::Http2 => config.connections,
        },
        elapsed.as_secs_f64(),
    );
    print_result("all", &latencies, errors, elapsed);
    if config.routes.len() > 1 {
        let total_weight = config.routes.iter().map(|route| route.weight).sum::<u64>();
        for (route, result) in config.routes.iter().zip(&mut route_results) {
            result.latencies_ns.sort_unstable();
            print_result(
                &format!(
                    "{}@{:.1}%",
                    route.path,
                    route.weight as f64 * 100.0 / total_weight as f64
                ),
                &result.latencies_ns,
                result.errors,
                elapsed,
            );
        }
    }
    if errors > 0 && !config.allow_errors {
        return Err(CliError(format!("{errors} requests failed")).into());
    }
    Ok(())
}

fn print_result(label: &str, sorted_ns: &[u64], errors: u64, elapsed: Duration) {
    let requests = u64::try_from(sorted_ns.len()).unwrap_or(u64::MAX);
    let rps = requests as f64 / elapsed.as_secs_f64();
    let mean = if sorted_ns.is_empty() {
        0.0
    } else {
        sorted_ns.iter().map(|value| *value as f64).sum::<f64>()
            / sorted_ns.len() as f64
            / 1_000_000.0
    };
    println!(
        "route={} requests={} errors={} rps={:.1} latency_ms_mean={:.3} \
         p50={:.3} p95={:.3} p99={:.3} max={:.3}",
        label,
        requests,
        errors,
        rps,
        mean,
        percentile(sorted_ns, 50.0),
        percentile(sorted_ns, 95.0),
        percentile(sorted_ns, 99.0),
        percentile(sorted_ns, 100.0),
    );
}

fn percentile(sorted_ns: &[u64], percentile: f64) -> f64 {
    if sorted_ns.is_empty() {
        return 0.0;
    }
    let rank = ((percentile / 100.0) * (sorted_ns.len() - 1) as f64).round() as usize;
    sorted_ns[rank] as f64 / 1_000_000.0
}

fn main() -> Result<(), DynError> {
    let config = parse_args()?;
    let threads = config.threads;
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(threads)
        .enable_all()
        .build()?
        .block_on(run(config))
}
