//! Immutable native file routes and host-owned, bounded file responses.

use crate::compression::{
    apply_content_coding, encoded_etag, response_is_compressible, vary_on_accept_encoding,
    AcceptedEncodings, ContentCoding, ContentEncoder,
};
use crate::shutdown::ActiveRequest;
use crate::telemetry::{ActiveGaugeGuard, Metrics};
use bytes::Bytes;
use cap_primitives::fs::{open, open_ambient_dir, open_dir_nofollow, FollowSymlinks, OpenOptions};
use http_body_util::{combinators::UnsyncBoxBody, BodyExt, Empty, Full};
use hyper::body::{Body, Frame, SizeHint};
use hyper::header::{
    ACCEPT_RANGES, ALLOW, CACHE_CONTROL, CONTENT_DISPOSITION, CONTENT_ENCODING, CONTENT_LENGTH,
    CONTENT_RANGE, CONTENT_TYPE, ETAG, IF_MATCH, IF_MODIFIED_SINCE, IF_NONE_MATCH, IF_RANGE,
    IF_UNMODIFIED_SINCE, LAST_MODIFIED, RANGE,
};
use hyper::{HeaderMap, Method, StatusCode};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::{mpsc, oneshot, OwnedSemaphorePermit, Semaphore};

pub(crate) type ServerBody = UnsyncBoxBody<Bytes, io::Error>;
pub(crate) type ServerResponse = hyper::Response<ServerBody>;

const MAX_FILE_ROOTS: usize = 64;
const MAX_NATIVE_ROUTES: usize = 128;
const MAX_ROUTE_PATH_BYTES: usize = 4 * 1024;
const MAX_RELATIVE_PATH_BYTES: usize = 4 * 1024;
const MAX_DOWNLOAD_NAME_CHARS: usize = 150;

pub(crate) fn full_body(bytes: Bytes) -> ServerBody {
    Full::new(bytes)
        .map_err(|never| match never {})
        .boxed_unsync()
}

pub(crate) fn empty_body() -> ServerBody {
    Empty::<Bytes>::new()
        .map_err(|never| match never {})
        .boxed_unsync()
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CachePolicy {
    NoStore,
    Revalidate,
    PrivateFor(u32),
    PublicFor(u32),
}

impl CachePolicy {
    pub(crate) fn from_abi(tag: u8, max_age_seconds: u32) -> Result<Self, String> {
        match tag {
            0 if max_age_seconds == 0 => Ok(Self::NoStore),
            1 if max_age_seconds == 0 => Ok(Self::Revalidate),
            2 => Ok(Self::PrivateFor(max_age_seconds)),
            3 => Ok(Self::PublicFor(max_age_seconds)),
            _ => Err("invalid file cache policy".to_owned()),
        }
    }

    fn header_value(self) -> String {
        match self {
            Self::NoStore => "no-store".to_owned(),
            Self::Revalidate => "no-cache".to_owned(),
            Self::PrivateFor(seconds) => format!("private, max-age={seconds}"),
            Self::PublicFor(seconds) => format!("public, max-age={seconds}"),
        }
    }
}

#[derive(Debug)]
pub(crate) struct FileRootSpec {
    pub(crate) id: String,
    pub(crate) path: PathBuf,
    pub(crate) cache: CachePolicy,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum NativeRouteKind {
    Prefix,
    Exact,
}

#[derive(Debug)]
pub(crate) struct NativeRouteSpec {
    pub(crate) at: String,
    pub(crate) root_id: String,
    pub(crate) kind: NativeRouteKind,
    pub(crate) relative: String,
    pub(crate) cache: Option<CachePolicy>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum Disposition {
    Inline,
    Attachment(String),
}

#[derive(Clone, Debug)]
pub(crate) struct FilePlan {
    root_id: String,
    relative: String,
    encoded_uri_path: bool,
    disposition: Disposition,
    cache: Option<CachePolicy>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum FileServeFailure {
    Overloaded,
    InvalidPlan,
    StartFailed,
}

impl FilePlan {
    pub(crate) fn authorized(
        root_id: String,
        relative: String,
        disposition: Disposition,
        cache: Option<CachePolicy>,
    ) -> Self {
        Self {
            root_id,
            relative,
            encoded_uri_path: false,
            disposition,
            cache,
        }
    }
}

#[derive(Debug)]
struct FileRoot {
    handle: File,
    cache: CachePolicy,
}

#[derive(Clone, Debug)]
struct NativeRoute {
    at: String,
    root_id: String,
    kind: NativeRouteKind,
    relative: String,
    cache: Option<CachePolicy>,
}

#[derive(Clone, Debug)]
pub(crate) struct FileService {
    roots: Arc<BTreeMap<String, Arc<FileRoot>>>,
    exact_routes: Arc<BTreeMap<String, NativeRoute>>,
    prefix_routes: Arc<Vec<NativeRoute>>,
    transfers: Arc<Semaphore>,
    chunk_bytes: usize,
    metrics: Arc<Metrics>,
}

impl FileService {
    pub(crate) fn activate(
        root_specs: Vec<FileRootSpec>,
        route_specs: Vec<NativeRouteSpec>,
        max_concurrent: usize,
        chunk_bytes: usize,
        metrics: Arc<Metrics>,
    ) -> Result<Self, String> {
        if root_specs.len() > MAX_FILE_ROOTS {
            return Err(format!(
                "at most {MAX_FILE_ROOTS} file roots may be declared"
            ));
        }
        if route_specs.len() > MAX_NATIVE_ROUTES {
            return Err(format!(
                "at most {MAX_NATIVE_ROUTES} native routes may be declared"
            ));
        }
        if max_concurrent == 0 {
            return Err("maximum concurrent file transfers must be non-zero".to_owned());
        }
        if chunk_bytes == 0 {
            return Err("file transfer chunk size must be non-zero".to_owned());
        }

        let mut roots = BTreeMap::new();
        for spec in root_specs {
            validate_root_id(&spec.id)?;
            if roots.contains_key(&spec.id) {
                return Err(format!("duplicate file root identifier {:?}", spec.id));
            }
            let handle = open_ambient_dir(&spec.path, cap_primitives::ambient_authority())
                .map_err(|error| {
                    format!(
                        "file root {:?} is missing, inaccessible, or not a directory: {error}",
                        spec.id
                    )
                })?;
            let metadata = handle
                .metadata()
                .map_err(|error| format!("failed to inspect file root {:?}: {error}", spec.id))?;
            if !metadata.is_dir() {
                return Err(format!("file root {:?} is not a directory", spec.id));
            }
            roots.insert(
                spec.id,
                Arc::new(FileRoot {
                    handle,
                    cache: spec.cache,
                }),
            );
        }

        let mut exact_routes = BTreeMap::new();
        let mut prefix_routes = Vec::new();
        let mut prefix_paths = BTreeSet::new();
        for spec in route_specs {
            validate_route_path(&spec.at)?;
            if !roots.contains_key(&spec.root_id) {
                return Err(format!(
                    "native route {:?} references undeclared file root {:?}",
                    spec.at, spec.root_id
                ));
            }
            if spec.kind == NativeRouteKind::Exact {
                validate_relative_path(&spec.relative)?;
            } else if !spec.relative.is_empty() {
                return Err(format!(
                    "static mount {:?} supplied an unexpected relative file",
                    spec.at
                ));
            }
            let route = NativeRoute {
                at: spec.at.clone(),
                root_id: spec.root_id,
                kind: spec.kind,
                relative: spec.relative,
                cache: spec.cache,
            };
            match spec.kind {
                NativeRouteKind::Exact => {
                    if exact_routes.insert(spec.at.clone(), route).is_some() {
                        return Err(format!("duplicate exact native route {:?}", spec.at));
                    }
                }
                NativeRouteKind::Prefix => {
                    if !prefix_paths.insert(spec.at.clone()) {
                        return Err(format!("duplicate native route prefix {:?}", spec.at));
                    }
                    prefix_routes.push(route);
                }
            }
        }
        prefix_routes.sort_by(|left, right| {
            right
                .at
                .len()
                .cmp(&left.at.len())
                .then_with(|| left.at.cmp(&right.at))
        });

        Ok(Self {
            roots: Arc::new(roots),
            exact_routes: Arc::new(exact_routes),
            prefix_routes: Arc::new(prefix_routes),
            transfers: Arc::new(Semaphore::new(max_concurrent)),
            chunk_bytes,
            metrics,
        })
    }

    pub(crate) fn route(&self, uri_path: &str) -> Option<FilePlan> {
        if let Some(route) = self.exact_routes.get(uri_path) {
            return Some(route.plan(route.relative.clone(), false));
        }
        for route in self.prefix_routes.iter() {
            let relative = if route.at == "/" {
                match uri_path.strip_prefix('/') {
                    Some(relative) => relative,
                    None => continue,
                }
            } else if uri_path == route.at {
                ""
            } else {
                match uri_path
                    .strip_prefix(&route.at)
                    .and_then(|suffix| suffix.strip_prefix('/'))
                {
                    Some(relative) => relative,
                    None => continue,
                }
            };
            return Some(route.plan(relative.to_owned(), true));
        }
        None
    }

    pub(crate) async fn serve(
        &self,
        plan: FilePlan,
        method: Method,
        headers: HeaderMap,
        active_request: Arc<ActiveRequest>,
    ) -> (ServerResponse, Option<FileServeFailure>) {
        if method != Method::GET && method != Method::HEAD {
            return (
                simple_response(
                    StatusCode::METHOD_NOT_ALLOWED,
                    &[(ALLOW, "GET, HEAD")],
                    Bytes::from_static(b"Method Not Allowed"),
                ),
                None,
            );
        }
        let root = match self.roots.get(&plan.root_id) {
            Some(root) => Arc::clone(root),
            None => {
                eprintln!(
                    "Roc returned a file response for undeclared root {:?}",
                    plan.root_id
                );
                return (
                    simple_response(
                        StatusCode::INTERNAL_SERVER_ERROR,
                        &[],
                        Bytes::from_static(b"Internal Server Error"),
                    ),
                    Some(FileServeFailure::InvalidPlan),
                );
            }
        };
        let permit = match Arc::clone(&self.transfers).try_acquire_owned() {
            Ok(permit) => permit,
            Err(_) => {
                return (
                    simple_response(
                        StatusCode::SERVICE_UNAVAILABLE,
                        &[],
                        Bytes::from_static(b"Native file transfer capacity is exhausted"),
                    ),
                    Some(FileServeFailure::Overloaded),
                );
            }
        };
        let lease =
            TransferLease::new(permit, active_request, self.metrics.file_transfer_started());
        let chunk_bytes = self.chunk_bytes;
        let (prepared_sender, prepared_receiver) = oneshot::channel();
        let spawn_result = std::thread::Builder::new()
            .name("basic-webserver-file".to_owned())
            .spawn(move || {
                prepare_and_stream(
                    root,
                    plan,
                    method,
                    headers,
                    chunk_bytes,
                    lease,
                    prepared_sender,
                );
            });
        if let Err(error) = spawn_result {
            return (
                simple_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    &[],
                    Bytes::from(format!("Failed to start file transfer: {error}")),
                ),
                Some(FileServeFailure::StartFailed),
            );
        }

        match prepared_receiver.await {
            Ok(prepared) => (prepared.into_response(), None),
            Err(_) => (
                simple_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    &[],
                    Bytes::from_static(b"File transfer failed before producing a response"),
                ),
                Some(FileServeFailure::StartFailed),
            ),
        }
    }

    pub(crate) fn active_transfers(&self) -> usize {
        self.metrics.active_file_transfers()
    }

    pub(crate) fn high_water_transfers(&self) -> usize {
        self.metrics.high_water_file_transfers()
    }
}

impl NativeRoute {
    fn plan(&self, relative: String, encoded_uri_path: bool) -> FilePlan {
        debug_assert!(
            self.kind == NativeRouteKind::Prefix || !encoded_uri_path,
            "only prefix routes derive paths from request URIs"
        );
        FilePlan {
            root_id: self.root_id.clone(),
            relative,
            encoded_uri_path,
            disposition: Disposition::Inline,
            cache: self.cache,
        }
    }
}

struct TransferLease {
    _permit: OwnedSemaphorePermit,
    _active_request: Arc<ActiveRequest>,
    _metrics: ActiveGaugeGuard,
}

impl TransferLease {
    fn new(
        permit: OwnedSemaphorePermit,
        active_request: Arc<ActiveRequest>,
        metrics: ActiveGaugeGuard,
    ) -> Arc<Self> {
        Arc::new(Self {
            _permit: permit,
            _active_request: active_request,
            _metrics: metrics,
        })
    }
}

struct FileBody {
    receiver: mpsc::Receiver<io::Result<Bytes>>,
    lease: Option<Arc<TransferLease>>,
    remaining: Option<u64>,
}

impl Body for FileBody {
    type Data = Bytes;
    type Error = io::Error;

    fn poll_frame(
        mut self: Pin<&mut Self>,
        context: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        match self.receiver.poll_recv(context) {
            Poll::Ready(Some(Ok(bytes))) => {
                if let Some(remaining) = &mut self.remaining {
                    *remaining = remaining.saturating_sub(bytes.len() as u64);
                }
                Poll::Ready(Some(Ok(Frame::data(bytes))))
            }
            Poll::Ready(Some(Err(error))) => {
                self.lease.take();
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(None) => {
                self.lease.take();
                Poll::Ready(None)
            }
            Poll::Pending => Poll::Pending,
        }
    }

    fn is_end_stream(&self) -> bool {
        self.remaining == Some(0)
    }

    fn size_hint(&self) -> SizeHint {
        self.remaining
            .map_or_else(SizeHint::new, SizeHint::with_exact)
    }
}

struct Prepared {
    status: StatusCode,
    headers: HeaderMap,
    body: Option<FileBody>,
}

impl Prepared {
    fn into_response(self) -> ServerResponse {
        let body = self
            .body
            .map_or_else(empty_body, |body| body.boxed_unsync());
        let mut response = hyper::Response::new(body);
        *response.status_mut() = self.status;
        *response.headers_mut() = self.headers;
        response
    }

    fn without_body(status: StatusCode, headers: HeaderMap) -> Self {
        Self {
            status,
            headers,
            body: None,
        }
    }
}

fn prepare_and_stream(
    root: Arc<FileRoot>,
    plan: FilePlan,
    method: Method,
    request_headers: HeaderMap,
    chunk_bytes: usize,
    lease: Arc<TransferLease>,
    prepared_sender: oneshot::Sender<Prepared>,
) {
    let segments = if plan.encoded_uri_path {
        decode_uri_relative_path(&plan.relative)
    } else {
        validate_relative_path(&plan.relative)
    };
    let segments = match segments {
        Ok(segments) => segments,
        Err(_) => {
            let _ = prepared_sender.send(not_found());
            return;
        }
    };
    let mut file = match open_relative_file(&root.handle, &segments) {
        Ok(file) => file,
        Err(_) => {
            let _ = prepared_sender.send(not_found());
            return;
        }
    };
    let metadata = match file.metadata() {
        Ok(metadata) if metadata.is_file() => metadata,
        _ => {
            let _ = prepared_sender.send(not_found());
            return;
        }
    };
    let length = metadata.len();
    let modified = metadata.modified().ok();
    let mut etag = weak_etag(length, modified);
    let cache = plan.cache.unwrap_or(root.cache);
    let mut response_headers = representation_headers(
        segments
            .last()
            .expect("validated relative paths contain a final component"),
        length,
        modified,
        &etag,
        cache,
        &plan.disposition,
    );
    let mut eligibility_headers = response_headers.clone();
    eligibility_headers.remove(ETAG);
    let compression_eligible = !request_headers.contains_key(RANGE)
        && response_is_compressible(StatusCode::OK, &eligibility_headers, length);
    let content_coding = if compression_eligible {
        vary_on_accept_encoding(&mut response_headers);
        AcceptedEncodings::from_headers(&request_headers).preferred()
    } else {
        None
    };
    if let Some(coding) = content_coding {
        etag = encoded_etag(&etag, coding);
        response_headers.insert(
            ETAG,
            etag.parse()
                .expect("host-generated encoded ETag is a valid header value"),
        );
        response_headers.remove(ACCEPT_RANGES);
        apply_content_coding(&mut response_headers, coding, None);
    }

    if let Some(status) = precondition_status(&request_headers, &etag, modified, &method) {
        if status == StatusCode::NOT_MODIFIED {
            response_headers.remove(CONTENT_LENGTH);
            response_headers.remove(CONTENT_TYPE);
            response_headers.remove(CONTENT_DISPOSITION);
        } else {
            response_headers.remove(CONTENT_ENCODING);
            response_headers.insert(CONTENT_LENGTH, hyper::header::HeaderValue::from_static("0"));
        }
        let _ = prepared_sender.send(Prepared::without_body(status, response_headers));
        return;
    }

    let selected_range = if if_range_allows(&request_headers, &etag, modified) {
        parse_range(&request_headers, length)
    } else {
        RangeSelection::Ignore
    };
    let (status, start, response_length) = match selected_range {
        RangeSelection::Ignore => (StatusCode::OK, 0, length),
        RangeSelection::Unsatisfiable => {
            response_headers.insert(
                CONTENT_RANGE,
                format!("bytes */{length}")
                    .parse()
                    .expect("content range generated by host is valid"),
            );
            response_headers.insert(CONTENT_LENGTH, hyper::header::HeaderValue::from_static("0"));
            let _ = prepared_sender.send(Prepared::without_body(
                StatusCode::RANGE_NOT_SATISFIABLE,
                response_headers,
            ));
            return;
        }
        RangeSelection::Range { start, end } => {
            let response_length = end - start + 1;
            response_headers.insert(
                CONTENT_RANGE,
                format!("bytes {start}-{end}/{length}")
                    .parse()
                    .expect("content range generated by host is valid"),
            );
            (StatusCode::PARTIAL_CONTENT, start, response_length)
        }
    };
    if content_coding.is_none() {
        response_headers.insert(
            CONTENT_LENGTH,
            response_length
                .to_string()
                .parse()
                .expect("content length generated by host is valid"),
        );
    }

    if method == Method::HEAD || response_length == 0 {
        let _ = prepared_sender.send(Prepared::without_body(status, response_headers));
        return;
    }
    if file.seek(SeekFrom::Start(start)).is_err() {
        let _ = prepared_sender.send(not_found());
        return;
    }

    let (body_sender, body_receiver) = mpsc::channel(1);
    let body = FileBody {
        receiver: body_receiver,
        lease: Some(Arc::clone(&lease)),
        remaining: content_coding.is_none().then_some(response_length),
    };
    if prepared_sender
        .send(Prepared {
            status,
            headers: response_headers,
            body: Some(body),
        })
        .is_err()
    {
        return;
    }

    if let Err(error) = stream_file(
        &mut file,
        response_length,
        chunk_bytes,
        content_coding,
        body_sender.clone(),
    ) {
        let _ = body_sender.blocking_send(Err(error));
    }
}

fn stream_file(
    file: &mut File,
    length: u64,
    chunk_bytes: usize,
    content_coding: Option<ContentCoding>,
    sender: mpsc::Sender<io::Result<Bytes>>,
) -> io::Result<()> {
    match content_coding {
        Some(coding) => {
            let writer = ChunkWriter::new(sender, chunk_bytes);
            let mut encoder = ContentEncoder::new(coding, writer)?;
            copy_file(file, length, chunk_bytes, |bytes| encoder.write_all(bytes))?;
            encoder.finish()?.finish()
        }
        None => copy_file(file, length, chunk_bytes, |bytes| {
            sender
                .blocking_send(Ok(Bytes::copy_from_slice(bytes)))
                .map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "response body dropped"))
        }),
    }
}

fn copy_file(
    file: &mut File,
    length: u64,
    chunk_bytes: usize,
    mut consume: impl FnMut(&[u8]) -> io::Result<()>,
) -> io::Result<()> {
    let mut remaining = length;
    while remaining > 0 {
        let next = usize::try_from(remaining.min(chunk_bytes as u64))
            .expect("bounded file chunk fits usize");
        let mut buffer = vec![0; next];
        file.read_exact(&mut buffer)?;
        remaining -= next as u64;
        consume(&buffer)?;
    }
    Ok(())
}

struct ChunkWriter {
    sender: mpsc::Sender<io::Result<Bytes>>,
    buffer: Vec<u8>,
    chunk_bytes: usize,
}

impl ChunkWriter {
    fn new(sender: mpsc::Sender<io::Result<Bytes>>, chunk_bytes: usize) -> Self {
        Self {
            sender,
            buffer: Vec::with_capacity(chunk_bytes),
            chunk_bytes,
        }
    }

    fn send_buffer(&mut self) -> io::Result<()> {
        if self.buffer.is_empty() {
            return Ok(());
        }
        let bytes = Bytes::from(std::mem::replace(
            &mut self.buffer,
            Vec::with_capacity(self.chunk_bytes),
        ));
        self.sender
            .blocking_send(Ok(bytes))
            .map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "response body dropped"))
    }

    fn finish(mut self) -> io::Result<()> {
        self.send_buffer()
    }
}

impl Write for ChunkWriter {
    fn write(&mut self, mut bytes: &[u8]) -> io::Result<usize> {
        let written = bytes.len();
        while !bytes.is_empty() {
            let available = self.chunk_bytes - self.buffer.len();
            let take = available.min(bytes.len());
            self.buffer.extend_from_slice(&bytes[..take]);
            bytes = &bytes[take..];
            if self.buffer.len() == self.chunk_bytes {
                self.send_buffer()?;
            }
        }
        Ok(written)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.send_buffer()
    }
}

fn simple_response(
    status: StatusCode,
    headers: &[(hyper::header::HeaderName, &'static str)],
    body: Bytes,
) -> ServerResponse {
    let mut response = hyper::Response::new(full_body(body));
    *response.status_mut() = status;
    for (name, value) in headers {
        response
            .headers_mut()
            .insert(name, hyper::header::HeaderValue::from_static(value));
    }
    response
}

fn not_found() -> Prepared {
    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_LENGTH, hyper::header::HeaderValue::from_static("0"));
    Prepared::without_body(StatusCode::NOT_FOUND, headers)
}

fn validate_root_id(id: &str) -> Result<(), String> {
    if id.is_empty()
        || id.len() > 64
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        return Err(format!(
            "file root identifier {id:?} must contain 1-64 ASCII letters, digits, '-' or '_'"
        ));
    }
    Ok(())
}

pub(crate) fn validate_route_path(path: &str) -> Result<(), String> {
    if !path.starts_with('/')
        || path.len() > MAX_ROUTE_PATH_BYTES
        || (path.len() > 1 && path.ends_with('/'))
        || path.contains("//")
        || !path.is_ascii()
        || path
            .bytes()
            .any(|byte| byte == b'%' || byte == b'\\' || byte == 0 || byte == b'?')
    {
        return Err(format!("invalid native route path {path:?}"));
    }
    for segment in path.split('/').skip(1) {
        if segment == "." || segment == ".." || segment.starts_with('.') {
            return Err(format!("invalid native route path {path:?}"));
        }
    }
    Ok(())
}

pub(crate) fn validate_relative_path(relative: &str) -> Result<Vec<String>, String> {
    if relative.is_empty() || relative.len() > MAX_RELATIVE_PATH_BYTES {
        return Err("relative file path is empty or too long".to_owned());
    }
    relative.split('/').map(validate_decoded_segment).collect()
}

fn decode_uri_relative_path(relative: &str) -> Result<Vec<String>, String> {
    if relative.is_empty() || relative.len() > MAX_RELATIVE_PATH_BYTES {
        return Err("relative file path is empty or too long".to_owned());
    }
    relative
        .split('/')
        .map(|segment| {
            if segment.is_empty() || segment.as_bytes().contains(&b'\\') {
                return Err("invalid URI path component".to_owned());
            }
            let bytes = percent_decode(segment.as_bytes())?;
            let decoded =
                String::from_utf8(bytes).map_err(|_| "URI path is not valid UTF-8".to_owned())?;
            validate_decoded_segment(&decoded)
        })
        .collect()
}

fn percent_decode(input: &[u8]) -> Result<Vec<u8>, String> {
    let mut output = Vec::with_capacity(input.len());
    let mut index = 0;
    while index < input.len() {
        if input[index] != b'%' {
            output.push(input[index]);
            index += 1;
            continue;
        }
        if index + 2 >= input.len() {
            return Err("truncated percent escape".to_owned());
        }
        let high =
            hex_value(input[index + 1]).ok_or_else(|| "invalid percent escape".to_owned())?;
        let low = hex_value(input[index + 2]).ok_or_else(|| "invalid percent escape".to_owned())?;
        let byte = high * 16 + low;
        if byte == b'/' || byte == b'\\' {
            return Err("encoded path separator".to_owned());
        }
        output.push(byte);
        index += 3;
    }
    Ok(output)
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn validate_decoded_segment(segment: &str) -> Result<String, String> {
    if segment.is_empty()
        || segment == "."
        || segment == ".."
        || segment.starts_with('.')
        || segment
            .bytes()
            .any(|byte| byte == 0 || byte == b'\\' || byte == b':' || byte == b'/')
    {
        return Err("unsafe relative file component".to_owned());
    }
    Ok(segment.to_owned())
}

fn open_relative_file(root: &File, segments: &[String]) -> io::Result<File> {
    let (last, parents) = segments
        .split_last()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "empty relative path"))?;
    let mut current = root.try_clone()?;
    for parent in parents {
        current = open_dir_nofollow(&current, Path::new(parent))?;
    }
    let mut options = OpenOptions::new();
    options.read(true)._cap_fs_ext_follow(FollowSymlinks::No);
    open(&current, Path::new(last), &options)
}

fn representation_headers(
    relative: &str,
    length: u64,
    modified: Option<SystemTime>,
    etag: &str,
    cache: CachePolicy,
    disposition: &Disposition,
) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(
        ACCEPT_RANGES,
        hyper::header::HeaderValue::from_static("bytes"),
    );
    headers.insert(
        CACHE_CONTROL,
        cache
            .header_value()
            .parse()
            .expect("typed cache policy generates a valid header"),
    );
    headers.insert(
        CONTENT_LENGTH,
        length
            .to_string()
            .parse()
            .expect("file length generates a valid header"),
    );
    headers.insert(
        CONTENT_TYPE,
        content_type(relative)
            .parse()
            .expect("static content type is a valid header"),
    );
    headers.insert(
        ETAG,
        etag.parse()
            .expect("host-generated ETag is a valid header value"),
    );
    if let Some(modified) = modified {
        headers.insert(
            LAST_MODIFIED,
            httpdate::fmt_http_date(modified)
                .parse()
                .expect("HTTP date is a valid header"),
        );
    }
    let disposition = match disposition {
        Disposition::Inline => "inline".to_owned(),
        Disposition::Attachment(name) => attachment_header(name),
    };
    headers.insert(
        CONTENT_DISPOSITION,
        disposition
            .parse()
            .expect("encoded content disposition is a valid header"),
    );
    headers
}

fn content_type(relative: &str) -> &'static str {
    let extension = relative
        .rsplit('/')
        .next()
        .and_then(|name| name.rsplit_once('.').map(|(_, extension)| extension))
        .unwrap_or("")
        .to_ascii_lowercase();
    match extension.as_str() {
        "css" => "text/css; charset=utf-8",
        "csv" => "text/csv; charset=utf-8",
        "gif" => "image/gif",
        "htm" | "html" => "text/html; charset=utf-8",
        "ico" => "image/x-icon",
        "jpeg" | "jpg" => "image/jpeg",
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "json" => "application/json",
        "pdf" => "application/pdf",
        "png" => "image/png",
        "svg" => "image/svg+xml",
        "txt" => "text/plain; charset=utf-8",
        "wasm" => "application/wasm",
        "webp" => "image/webp",
        "xml" => "application/xml",
        _ => "application/octet-stream",
    }
}

fn attachment_header(name: &str) -> String {
    let bounded: String = name.chars().take(MAX_DOWNLOAD_NAME_CHARS).collect();
    let fallback: String = bounded
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, ' ' | '-' | '_' | '.') {
                character
            } else {
                '_'
            }
        })
        .collect();
    let fallback = if fallback.is_empty() {
        "download"
    } else {
        fallback.as_str()
    };
    let encoded = bounded
        .as_bytes()
        .iter()
        .map(|byte| {
            if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_') {
                (*byte as char).to_string()
            } else {
                format!("%{byte:02X}")
            }
        })
        .collect::<String>();
    format!("attachment; filename=\"{fallback}\"; filename*=UTF-8''{encoded}")
}

fn weak_etag(length: u64, modified: Option<SystemTime>) -> String {
    let nanos = modified
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |duration| duration.as_nanos());
    format!("W/\"{length:x}-{nanos:x}\"")
}

fn precondition_status(
    headers: &HeaderMap,
    etag: &str,
    modified: Option<SystemTime>,
    method: &Method,
) -> Option<StatusCode> {
    if headers.contains_key(IF_MATCH) {
        if !etag_condition_matches(headers, IF_MATCH, etag, false) {
            return Some(StatusCode::PRECONDITION_FAILED);
        }
    } else if let (Some(value), Some(modified)) = (headers.get(IF_UNMODIFIED_SINCE), modified) {
        if parse_http_date(value).is_some_and(|date| is_later(modified, date)) {
            return Some(StatusCode::PRECONDITION_FAILED);
        }
    }

    if headers.contains_key(IF_NONE_MATCH) {
        if etag_condition_matches(headers, IF_NONE_MATCH, etag, true) {
            return Some(if method == Method::GET || method == Method::HEAD {
                StatusCode::NOT_MODIFIED
            } else {
                StatusCode::PRECONDITION_FAILED
            });
        }
    } else if method == Method::GET || method == Method::HEAD {
        if let (Some(value), Some(modified)) = (headers.get(IF_MODIFIED_SINCE), modified) {
            if parse_http_date(value).is_some_and(|date| !is_later(modified, date)) {
                return Some(StatusCode::NOT_MODIFIED);
            }
        }
    }
    None
}

fn etag_condition_matches(
    headers: &HeaderMap,
    name: hyper::header::HeaderName,
    current: &str,
    weak: bool,
) -> bool {
    headers.get_all(name).iter().any(|value| {
        value.to_str().ok().is_some_and(|raw| {
            raw.split(',').any(|candidate| {
                let candidate = candidate.trim();
                candidate == "*"
                    || if weak {
                        strip_weak(candidate) == strip_weak(current)
                            && candidate.ends_with('"')
                            && candidate.contains('"')
                    } else {
                        !candidate.starts_with("W/") && candidate == current
                    }
            })
        })
    })
}

fn strip_weak(value: &str) -> &str {
    value.strip_prefix("W/").unwrap_or(value)
}

fn parse_http_date(value: &hyper::header::HeaderValue) -> Option<SystemTime> {
    value
        .to_str()
        .ok()
        .and_then(|raw| httpdate::parse_http_date(raw).ok())
}

fn unix_seconds(time: SystemTime) -> u64 {
    time.duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs())
}

fn is_later(left: SystemTime, right: SystemTime) -> bool {
    unix_seconds(left) > unix_seconds(right)
}

fn if_range_allows(headers: &HeaderMap, etag: &str, modified: Option<SystemTime>) -> bool {
    let Some(value) = headers.get(IF_RANGE) else {
        return true;
    };
    let Ok(raw) = value.to_str() else {
        return false;
    };
    if raw.starts_with('"') || raw.starts_with("W/") {
        return !raw.starts_with("W/") && !etag.starts_with("W/") && raw == etag;
    }
    match (httpdate::parse_http_date(raw).ok(), modified) {
        (Some(date), Some(modified)) => !is_later(modified, date),
        _ => false,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RangeSelection {
    Ignore,
    Unsatisfiable,
    Range { start: u64, end: u64 },
}

fn parse_range(headers: &HeaderMap, length: u64) -> RangeSelection {
    let mut values = headers.get_all(RANGE).iter();
    let Some(value) = values.next() else {
        return RangeSelection::Ignore;
    };
    if values.next().is_some() {
        return RangeSelection::Ignore;
    }
    let Some(raw) = value.to_str().ok() else {
        return RangeSelection::Ignore;
    };
    let Some(spec) = raw.strip_prefix("bytes=") else {
        return RangeSelection::Ignore;
    };
    if spec.contains(',') {
        return RangeSelection::Ignore;
    }
    let Some((first, last)) = spec.split_once('-') else {
        return RangeSelection::Ignore;
    };
    if first.is_empty() {
        let Ok(suffix) = last.parse::<u64>() else {
            return RangeSelection::Ignore;
        };
        if suffix == 0 || length == 0 {
            return RangeSelection::Unsatisfiable;
        }
        let start = length.saturating_sub(suffix);
        return RangeSelection::Range {
            start,
            end: length - 1,
        };
    }
    let Ok(start) = first.parse::<u64>() else {
        return RangeSelection::Ignore;
    };
    if start >= length {
        return RangeSelection::Unsatisfiable;
    }
    if last.is_empty() {
        return RangeSelection::Range {
            start,
            end: length - 1,
        };
    }
    let Ok(end) = last.parse::<u64>() else {
        return RangeSelection::Ignore;
    };
    if start > end {
        return RangeSelection::Ignore;
    }
    RangeSelection::Range {
        start,
        end: end.min(length - 1),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::telemetry::Metrics;
    use std::fs;
    use std::io::Read;

    #[test]
    fn route_matching_has_segment_boundaries_and_precedence() {
        let temp = tempfile_dir();
        let service = FileService::activate(
            vec![FileRootSpec {
                id: "root".to_owned(),
                path: temp.clone(),
                cache: CachePolicy::Revalidate,
            }],
            vec![
                NativeRouteSpec {
                    at: "/assets".to_owned(),
                    root_id: "root".to_owned(),
                    kind: NativeRouteKind::Prefix,
                    relative: String::new(),
                    cache: None,
                },
                NativeRouteSpec {
                    at: "/assets/special".to_owned(),
                    root_id: "root".to_owned(),
                    kind: NativeRouteKind::Exact,
                    relative: "special.txt".to_owned(),
                    cache: None,
                },
                NativeRouteSpec {
                    at: "/assets/deep".to_owned(),
                    root_id: "root".to_owned(),
                    kind: NativeRouteKind::Prefix,
                    relative: String::new(),
                    cache: None,
                },
            ],
            2,
            1024,
            Metrics::new(),
        )
        .unwrap();

        assert_eq!(
            service.route("/assets/special").unwrap().relative,
            "special.txt"
        );
        assert_eq!(
            service.route("/assets/deep/file.txt").unwrap().relative,
            "file.txt"
        );
        assert_eq!(
            service.route("/assets/file.txt").unwrap().relative,
            "file.txt"
        );
        assert!(service.route("/assets2/file.txt").is_none());
        fs::remove_dir(temp).unwrap();
    }

    #[test]
    fn route_activation_rejects_duplicates_and_missing_roots() {
        let temp = tempfile_dir();
        let duplicate_root = FileService::activate(
            vec![
                FileRootSpec {
                    id: "root".to_owned(),
                    path: temp.clone(),
                    cache: CachePolicy::Revalidate,
                },
                FileRootSpec {
                    id: "root".to_owned(),
                    path: temp.clone(),
                    cache: CachePolicy::NoStore,
                },
            ],
            Vec::new(),
            1,
            1,
            Metrics::new(),
        );
        assert!(duplicate_root
            .unwrap_err()
            .contains("duplicate file root identifier"));

        let absent = FileService::activate(
            vec![FileRootSpec {
                id: "absent".to_owned(),
                path: temp.join("does-not-exist"),
                cache: CachePolicy::Revalidate,
            }],
            Vec::new(),
            1,
            1,
            Metrics::new(),
        );
        assert!(absent.unwrap_err().contains("missing, inaccessible"));

        let duplicate = FileService::activate(
            vec![FileRootSpec {
                id: "root".to_owned(),
                path: temp.clone(),
                cache: CachePolicy::Revalidate,
            }],
            vec![
                NativeRouteSpec {
                    at: "/assets".to_owned(),
                    root_id: "root".to_owned(),
                    kind: NativeRouteKind::Prefix,
                    relative: String::new(),
                    cache: None,
                },
                NativeRouteSpec {
                    at: "/assets".to_owned(),
                    root_id: "root".to_owned(),
                    kind: NativeRouteKind::Prefix,
                    relative: String::new(),
                    cache: None,
                },
            ],
            1,
            1,
            Metrics::new(),
        );
        assert!(duplicate
            .unwrap_err()
            .contains("duplicate native route prefix"));

        let missing = FileService::activate(
            Vec::new(),
            vec![NativeRouteSpec {
                at: "/assets".to_owned(),
                root_id: "missing".to_owned(),
                kind: NativeRouteKind::Prefix,
                relative: String::new(),
                cache: None,
            }],
            1,
            1,
            Metrics::new(),
        );
        assert!(missing.unwrap_err().contains("undeclared file root"));
        fs::remove_dir(temp).unwrap();
    }

    #[test]
    fn uri_path_validation_rejects_traversal_and_encoded_separators() {
        for invalid in [
            "",
            ".",
            "..",
            "%2e%2e",
            ".hidden",
            "dir/.hidden",
            "dir//file",
            "dir/%2Ffile",
            "dir/%5cfile",
            "C:%5csecret",
            "dir/%00file",
            "dir/%ff",
            "dir/%",
        ] {
            assert!(
                decode_uri_relative_path(invalid).is_err(),
                "{invalid:?} should be rejected"
            );
        }
        assert_eq!(
            decode_uri_relative_path("dir/a%20file.txt").unwrap(),
            ["dir", "a file.txt"]
        );
        assert!(decode_uri_relative_path(&"x".repeat(MAX_RELATIVE_PATH_BYTES + 1)).is_err());
    }

    #[cfg(unix)]
    #[test]
    fn rooted_open_rejects_symlinks_in_every_component() {
        use std::os::unix::fs::symlink;

        let root = tempfile_dir();
        let outside = tempfile_dir();
        fs::write(outside.join("secret.txt"), b"secret").unwrap();
        fs::create_dir(root.join("inside")).unwrap();
        fs::write(root.join("inside/file.txt"), b"ok").unwrap();
        symlink(&outside, root.join("linked-dir")).unwrap();
        symlink(
            outside.join("secret.txt"),
            root.join("inside/linked-file.txt"),
        )
        .unwrap();
        let root_handle = open_ambient_dir(&root, cap_primitives::ambient_authority()).unwrap();

        assert!(
            open_relative_file(&root_handle, &["inside".to_owned(), "file.txt".to_owned()]).is_ok()
        );
        assert!(open_relative_file(
            &root_handle,
            &["linked-dir".to_owned(), "secret.txt".to_owned()]
        )
        .is_err());
        assert!(open_relative_file(
            &root_handle,
            &["inside".to_owned(), "linked-file.txt".to_owned()]
        )
        .is_err());

        fs::remove_dir_all(root).unwrap();
        fs::remove_dir_all(outside).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn component_swap_race_never_opens_an_outside_file() {
        use std::os::unix::fs::symlink;
        use std::sync::atomic::{AtomicBool, Ordering};

        let root = tempfile_dir();
        let outside = tempfile_dir();
        fs::create_dir(root.join("slot")).unwrap();
        fs::write(root.join("slot/file.txt"), b"public").unwrap();
        fs::write(outside.join("file.txt"), b"secret").unwrap();
        let root_handle = open_ambient_dir(&root, cap_primitives::ambient_authority()).unwrap();
        let stop = Arc::new(AtomicBool::new(false));
        let attacker_stop = Arc::clone(&stop);
        let attacker_root = root.clone();
        let attacker_outside = outside.clone();
        let attacker = std::thread::spawn(move || {
            while !attacker_stop.load(Ordering::Acquire) {
                if fs::rename(attacker_root.join("slot"), attacker_root.join("slot-real")).is_ok() {
                    let _ = symlink(&attacker_outside, attacker_root.join("slot"));
                    let _ = fs::remove_file(attacker_root.join("slot"));
                    let _ = fs::rename(attacker_root.join("slot-real"), attacker_root.join("slot"));
                }
            }
        });

        for _ in 0..2_000 {
            if let Ok(mut file) =
                open_relative_file(&root_handle, &["slot".to_owned(), "file.txt".to_owned()])
            {
                let mut bytes = Vec::new();
                file.read_to_end(&mut bytes).unwrap();
                assert_eq!(bytes, b"public");
            }
        }
        stop.store(true, Ordering::Release);
        attacker.join().unwrap();
        if root.join("slot-real").exists() {
            let _ = fs::remove_file(root.join("slot"));
            fs::rename(root.join("slot-real"), root.join("slot")).unwrap();
        }
        fs::remove_dir_all(root).unwrap();
        fs::remove_dir_all(outside).unwrap();
    }

    #[tokio::test]
    async fn dropped_body_releases_transfer_capacity_and_request_accounting() {
        use crate::shutdown::RequestTracker;

        let root = tempfile_dir();
        fs::write(root.join("large.bin"), vec![b'x'; 64 * 1024]).unwrap();
        let service = FileService::activate(
            vec![FileRootSpec {
                id: "root".to_owned(),
                path: root.clone(),
                cache: CachePolicy::Revalidate,
            }],
            Vec::new(),
            1,
            1024,
            Metrics::new(),
        )
        .unwrap();
        let tracker = RequestTracker::new();
        let plan = || {
            FilePlan::authorized(
                "root".to_owned(),
                "large.bin".to_owned(),
                Disposition::Inline,
                None,
            )
        };

        let (first, first_failure) = service
            .serve(
                plan(),
                Method::GET,
                HeaderMap::new(),
                Arc::new(tracker.begin().unwrap()),
            )
            .await;
        assert_eq!(first_failure, None);
        assert_eq!(first.status(), StatusCode::OK);
        assert_eq!(service.active_transfers(), 1);

        let (saturated, saturated_failure) = service
            .serve(
                plan(),
                Method::GET,
                HeaderMap::new(),
                Arc::new(tracker.begin().unwrap()),
            )
            .await;
        assert_eq!(saturated_failure, Some(FileServeFailure::Overloaded));
        assert_eq!(saturated.status(), StatusCode::SERVICE_UNAVAILABLE);
        drop(saturated);
        drop(first);

        tokio::time::timeout(std::time::Duration::from_secs(1), async {
            while service.active_transfers() != 0 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("dropped response did not cancel its file worker");
        assert_eq!(tracker.active(), 0);
        assert_eq!(service.high_water_transfers(), 1);
        fs::remove_dir_all(root).unwrap();
    }

    #[tokio::test]
    async fn native_files_stream_zstandard_but_preserve_identity_ranges() {
        use crate::shutdown::RequestTracker;

        let root = tempfile_dir();
        let original = b"compressible native file ".repeat(512);
        fs::write(root.join("large.txt"), &original).unwrap();
        let service = FileService::activate(
            vec![FileRootSpec {
                id: "root".to_owned(),
                path: root.clone(),
                cache: CachePolicy::Revalidate,
            }],
            Vec::new(),
            1,
            1024,
            Metrics::new(),
        )
        .unwrap();
        let tracker = RequestTracker::new();
        let plan = || {
            FilePlan::authorized(
                "root".to_owned(),
                "large.txt".to_owned(),
                Disposition::Inline,
                None,
            )
        };
        let mut compressed_headers = HeaderMap::new();
        compressed_headers.insert(
            hyper::header::ACCEPT_ENCODING,
            "gzip, br, zstd".parse().unwrap(),
        );
        let (compressed, compressed_failure) = service
            .serve(
                plan(),
                Method::GET,
                compressed_headers,
                Arc::new(tracker.begin().unwrap()),
            )
            .await;
        assert_eq!(compressed_failure, None);
        assert_eq!(compressed.status(), StatusCode::OK);
        assert_eq!(compressed.headers()[CONTENT_ENCODING], "zstd");
        assert_eq!(compressed.headers()[hyper::header::VARY], "Accept-Encoding");
        assert!(!compressed.headers().contains_key(CONTENT_LENGTH));
        assert!(!compressed.headers().contains_key(ACCEPT_RANGES));
        let compressed_etag = compressed.headers()[ETAG].clone();
        let encoded = compressed.into_body().collect().await.unwrap().to_bytes();
        let mut decoded = Vec::new();
        zstd::stream::read::Decoder::new(encoded.as_ref())
            .unwrap()
            .read_to_end(&mut decoded)
            .unwrap();
        assert_eq!(decoded, original);

        let mut conditional_headers = HeaderMap::new();
        conditional_headers.insert(hyper::header::ACCEPT_ENCODING, "zstd".parse().unwrap());
        conditional_headers.insert(IF_NONE_MATCH, compressed_etag);
        let (not_modified, not_modified_failure) = service
            .serve(
                plan(),
                Method::GET,
                conditional_headers,
                Arc::new(tracker.begin().unwrap()),
            )
            .await;
        assert_eq!(not_modified_failure, None);
        assert_eq!(not_modified.status(), StatusCode::NOT_MODIFIED);
        assert_eq!(not_modified.headers()[CONTENT_ENCODING], "zstd");
        assert_eq!(
            not_modified.headers()[hyper::header::VARY],
            "Accept-Encoding"
        );
        assert!(not_modified
            .into_body()
            .collect()
            .await
            .unwrap()
            .to_bytes()
            .is_empty());

        let mut range_headers = HeaderMap::new();
        range_headers.insert(
            hyper::header::ACCEPT_ENCODING,
            "gzip, br, zstd".parse().unwrap(),
        );
        range_headers.insert(RANGE, "bytes=0-10".parse().unwrap());
        let (ranged, ranged_failure) = service
            .serve(
                plan(),
                Method::GET,
                range_headers,
                Arc::new(tracker.begin().unwrap()),
            )
            .await;
        assert_eq!(ranged_failure, None);
        assert_eq!(ranged.status(), StatusCode::PARTIAL_CONTENT);
        assert!(!ranged.headers().contains_key(CONTENT_ENCODING));
        assert_eq!(ranged.headers()[CONTENT_LENGTH], "11");
        let bytes = ranged.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(bytes.as_ref(), &original[..11]);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn single_range_parser_is_bounded_and_deterministic() {
        fn headers(value: &'static str) -> HeaderMap {
            let mut headers = HeaderMap::new();
            headers.insert(RANGE, hyper::header::HeaderValue::from_static(value));
            headers
        }

        assert_eq!(
            parse_range(&headers("bytes=2-4"), 10),
            RangeSelection::Range { start: 2, end: 4 }
        );
        assert_eq!(
            parse_range(&headers("bytes=7-"), 10),
            RangeSelection::Range { start: 7, end: 9 }
        );
        assert_eq!(
            parse_range(&headers("bytes=-3"), 10),
            RangeSelection::Range { start: 7, end: 9 }
        );
        assert_eq!(
            parse_range(&headers("bytes=99-"), 10),
            RangeSelection::Unsatisfiable
        );
        assert_eq!(
            parse_range(&headers("bytes=0-1,4-5"), 10),
            RangeSelection::Ignore
        );
        assert_eq!(
            parse_range(&headers("items=0-1"), 10),
            RangeSelection::Ignore
        );

        let mut repeated = headers("bytes=0-1");
        repeated.append(RANGE, hyper::header::HeaderValue::from_static("bytes=4-5"));
        assert_eq!(parse_range(&repeated, 10), RangeSelection::Ignore);
    }

    #[test]
    fn attachment_filenames_cannot_inject_headers() {
        let header = attachment_header("report\"\r\nX-Evil: yes.pdf");
        assert!(!header.contains('\r'));
        assert!(!header.contains('\n'));
        assert!(hyper::header::HeaderValue::from_str(&header).is_ok());
        assert!(header.starts_with("attachment;"));
    }

    #[test]
    fn preconditions_follow_if_match_and_if_none_match_precedence() {
        let modified = UNIX_EPOCH + std::time::Duration::from_secs(1_700_000_000);
        let etag = weak_etag(10, Some(modified));
        let mut headers = HeaderMap::new();
        headers.insert(
            IF_MATCH,
            hyper::header::HeaderValue::from_static("\"strong\""),
        );
        headers.insert(IF_NONE_MATCH, etag.parse().unwrap());
        assert_eq!(
            precondition_status(&headers, &etag, Some(modified), &Method::GET),
            Some(StatusCode::PRECONDITION_FAILED)
        );

        headers.remove(IF_MATCH);
        assert_eq!(
            precondition_status(&headers, &etag, Some(modified), &Method::GET),
            Some(StatusCode::NOT_MODIFIED)
        );
    }

    fn tempfile_dir() -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "basic-webserver-file-test-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&path).unwrap();
        path
    }
}
