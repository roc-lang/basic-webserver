//! One immutable, startup-validated route table for every host-native route.

use crate::file_server::{CachePolicy, FilePlan, FileService};
use crate::readiness::ReadinessLease;
use crate::response::{empty_body, full_body, ServerResponse};
use bytes::Bytes;
use hyper::header::{ALLOW, CACHE_CONTROL, CONTENT_LENGTH, CONTENT_TYPE};
use hyper::{Method, StatusCode};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

const MAX_NATIVE_ROUTES: usize = 128;
const MAX_ROUTE_PATH_BYTES: usize = 4 * 1024;
const PROBE_ALLOW: &str = "GET, HEAD";
const PROBE_CONTENT_TYPE: &str = "text/plain; charset=utf-8";
const PROBE_CACHE_CONTROL: &str = "no-store";
const LIVE_BODY: &[u8] = b"OK\n";
const READY_BODY: &[u8] = b"OK\n";
const NOT_READY_BODY: &[u8] = b"NOT READY\n";
const METHOD_NOT_ALLOWED_BODY: &[u8] = b"Method Not Allowed\n";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum FileRouteKind {
    Prefix,
    Exact,
}

#[derive(Debug)]
pub(crate) struct FileRouteSpec {
    pub(crate) at: String,
    pub(crate) root_id: String,
    pub(crate) kind: FileRouteKind,
    pub(crate) relative: String,
    pub(crate) cache: Option<CachePolicy>,
}

pub(crate) struct ReadinessRouteSpec {
    pub(crate) at: String,
    pub(crate) readiness: ReadinessLease,
}

enum ExactRoute {
    File {
        root_id: String,
        relative: String,
        cache: Option<CachePolicy>,
    },
    Liveness,
    Readiness(ReadinessLease),
}

struct PrefixRoute {
    at: String,
    root_id: String,
    cache: Option<CachePolicy>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ProbeKind {
    Liveness,
    Readiness,
}

impl ProbeKind {
    fn telemetry_label(self) -> &'static str {
        match self {
            Self::Liveness => "liveness",
            Self::Readiness => "readiness",
        }
    }

    fn suppress_success_log(self) -> bool {
        true
    }
}

#[derive(Default)]
struct ProbeCounters {
    liveness_requests: AtomicU64,
    readiness_requests: AtomicU64,
    ready_responses: AtomicU64,
    not_ready_responses: AtomicU64,
    method_not_allowed_responses: AtomicU64,
}

impl ProbeCounters {
    fn record_request(&self, kind: ProbeKind) {
        let counter = match kind {
            ProbeKind::Liveness => &self.liveness_requests,
            ProbeKind::Readiness => &self.readiness_requests,
        };
        saturating_increment(counter);
    }

    fn record_status(&self, status: StatusCode) {
        let counter = match status {
            StatusCode::OK => &self.ready_responses,
            StatusCode::SERVICE_UNAVAILABLE => &self.not_ready_responses,
            StatusCode::METHOD_NOT_ALLOWED => &self.method_not_allowed_responses,
            _ => return,
        };
        saturating_increment(counter);
    }
}

fn saturating_increment(counter: &AtomicU64) {
    let _ = counter.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
        value.checked_add(1)
    });
}

struct NativeRouterInner {
    exact: BTreeMap<String, ExactRoute>,
    prefixes: Vec<PrefixRoute>,
    probes: ProbeCounters,
}

#[derive(Clone)]
pub(crate) struct NativeRouter {
    inner: Arc<NativeRouterInner>,
}

pub(crate) enum NativeMatch {
    File(FilePlan),
    Probe(ServerResponse),
}

impl NativeRouter {
    pub(crate) fn activate(
        files: &FileService,
        file_specs: Vec<FileRouteSpec>,
        liveness_paths: Vec<String>,
        readiness_specs: Vec<ReadinessRouteSpec>,
    ) -> Result<Self, String> {
        let route_count = file_specs
            .len()
            .checked_add(liveness_paths.len())
            .and_then(|count| count.checked_add(readiness_specs.len()))
            .ok_or_else(|| "native route count overflowed".to_owned())?;
        if route_count > MAX_NATIVE_ROUTES {
            return Err(format!(
                "at most {MAX_NATIVE_ROUTES} native routes may be declared"
            ));
        }

        let mut exact = BTreeMap::new();
        let mut prefixes = Vec::new();
        let mut prefix_paths = BTreeSet::new();

        for spec in file_specs {
            validate_route_path(&spec.at)?;
            let relative = (spec.kind == FileRouteKind::Exact).then_some(spec.relative.as_str());
            if spec.kind == FileRouteKind::Prefix && !spec.relative.is_empty() {
                return Err(format!(
                    "static mount {:?} supplied an unexpected relative file",
                    spec.at
                ));
            }
            files
                .validate_native_route(&spec.root_id, relative)
                .map_err(|detail| format!("native route {:?} {detail}", spec.at))?;
            match spec.kind {
                FileRouteKind::Exact => insert_exact(
                    &mut exact,
                    spec.at,
                    ExactRoute::File {
                        root_id: spec.root_id,
                        relative: spec.relative,
                        cache: spec.cache,
                    },
                )?,
                FileRouteKind::Prefix => {
                    if !prefix_paths.insert(spec.at.clone()) {
                        return Err(format!("duplicate native route prefix {:?}", spec.at));
                    }
                    prefixes.push(PrefixRoute {
                        at: spec.at,
                        root_id: spec.root_id,
                        cache: spec.cache,
                    });
                }
            }
        }

        for at in liveness_paths {
            validate_route_path(&at)?;
            insert_exact(&mut exact, at, ExactRoute::Liveness)?;
        }
        for spec in readiness_specs {
            validate_route_path(&spec.at)?;
            insert_exact(&mut exact, spec.at, ExactRoute::Readiness(spec.readiness))?;
        }

        prefixes.sort_by(|left, right| {
            right
                .at
                .len()
                .cmp(&left.at.len())
                .then_with(|| left.at.cmp(&right.at))
        });
        Ok(Self {
            inner: Arc::new(NativeRouterInner {
                exact,
                prefixes,
                probes: ProbeCounters::default(),
            }),
        })
    }

    pub(crate) fn route(&self, uri_path: &str, method: &Method) -> Option<NativeMatch> {
        if let Some(route) = self.inner.exact.get(uri_path) {
            return Some(match route {
                ExactRoute::File {
                    root_id,
                    relative,
                    cache,
                } => NativeMatch::File(FilePlan::native(
                    root_id.clone(),
                    relative.clone(),
                    false,
                    *cache,
                )),
                ExactRoute::Liveness => {
                    NativeMatch::Probe(self.probe_response(ProbeKind::Liveness, true, method))
                }
                ExactRoute::Readiness(readiness) => NativeMatch::Probe(self.probe_response(
                    ProbeKind::Readiness,
                    readiness.is_ready(),
                    method,
                )),
            });
        }
        for route in &self.inner.prefixes {
            let relative = if route.at == "/" {
                uri_path.strip_prefix('/')?
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
            return Some(NativeMatch::File(FilePlan::native(
                route.root_id.clone(),
                relative.to_owned(),
                true,
                route.cache,
            )));
        }
        None
    }

    pub(crate) fn begin_draining(&self) {
        for route in self.inner.exact.values() {
            if let ExactRoute::Readiness(readiness) = route {
                readiness.begin_stopping();
            }
        }
    }

    fn probe_response(&self, kind: ProbeKind, available: bool, method: &Method) -> ServerResponse {
        self.inner.probes.record_request(kind);
        debug_assert!(!kind.telemetry_label().is_empty());
        debug_assert!(kind.suppress_success_log());
        let (status, body) = if method != Method::GET && method != Method::HEAD {
            (StatusCode::METHOD_NOT_ALLOWED, METHOD_NOT_ALLOWED_BODY)
        } else if available {
            (
                StatusCode::OK,
                if kind == ProbeKind::Liveness {
                    LIVE_BODY
                } else {
                    READY_BODY
                },
            )
        } else {
            (StatusCode::SERVICE_UNAVAILABLE, NOT_READY_BODY)
        };
        self.inner.probes.record_status(status);

        let mut response = hyper::Response::new(if method == Method::HEAD {
            empty_body()
        } else {
            full_body(Bytes::from_static(body))
        });
        *response.status_mut() = status;
        let headers = response.headers_mut();
        headers.insert(
            CACHE_CONTROL,
            hyper::header::HeaderValue::from_static(PROBE_CACHE_CONTROL),
        );
        headers.insert(
            CONTENT_TYPE,
            hyper::header::HeaderValue::from_static(PROBE_CONTENT_TYPE),
        );
        headers.insert(
            CONTENT_LENGTH,
            hyper::header::HeaderValue::from_str(&body.len().to_string())
                .expect("fixed probe body length is a valid header"),
        );
        if status == StatusCode::METHOD_NOT_ALLOWED {
            headers.insert(ALLOW, hyper::header::HeaderValue::from_static(PROBE_ALLOW));
        }
        response
    }

    #[cfg(test)]
    fn probe_metrics(&self) -> ProbeMetrics {
        ProbeMetrics {
            liveness_requests: self.inner.probes.liveness_requests.load(Ordering::Relaxed),
            readiness_requests: self.inner.probes.readiness_requests.load(Ordering::Relaxed),
            ready_responses: self.inner.probes.ready_responses.load(Ordering::Relaxed),
            not_ready_responses: self
                .inner
                .probes
                .not_ready_responses
                .load(Ordering::Relaxed),
            method_not_allowed_responses: self
                .inner
                .probes
                .method_not_allowed_responses
                .load(Ordering::Relaxed),
        }
    }
}

fn insert_exact(
    routes: &mut BTreeMap<String, ExactRoute>,
    at: String,
    route: ExactRoute,
) -> Result<(), String> {
    if routes.insert(at.clone(), route).is_some() {
        Err(format!("duplicate exact native route {at:?}"))
    } else {
        Ok(())
    }
}

fn validate_route_path(path: &str) -> Result<(), String> {
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

#[cfg(test)]
#[derive(Debug, Eq, PartialEq)]
struct ProbeMetrics {
    liveness_requests: u64,
    readiness_requests: u64,
    ready_responses: u64,
    not_ready_responses: u64,
    method_not_allowed_responses: u64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use http_body_util::BodyExt;

    fn empty_files() -> FileService {
        FileService::activate(Vec::new(), 1, 1024).unwrap()
    }

    #[test]
    fn route_paths_and_cross_type_duplicates_are_validated_together() {
        let files = empty_files();
        let duplicate = NativeRouter::activate(
            &files,
            Vec::new(),
            vec!["/health".to_owned()],
            vec![ReadinessRouteSpec {
                at: "/health".to_owned(),
                readiness: crate::readiness::test_lease(false),
            }],
        )
        .err()
        .unwrap();
        assert!(duplicate.contains("duplicate exact native route"));

        for invalid in [
            "health",
            "/health/",
            "/health?detail=1",
            "/.health",
            "/h%65alth",
        ] {
            assert!(NativeRouter::activate(
                &files,
                Vec::new(),
                vec![invalid.to_owned()],
                Vec::new(),
            )
            .is_err());
        }
    }

    #[tokio::test]
    async fn probes_have_fixed_responses_methods_and_metrics() {
        let files = empty_files();
        let router = NativeRouter::activate(
            &files,
            Vec::new(),
            vec!["/live".to_owned()],
            vec![ReadinessRouteSpec {
                at: "/ready".to_owned(),
                readiness: crate::readiness::test_lease(false),
            }],
        )
        .unwrap();

        let NativeMatch::Probe(live) = router.route("/live", &Method::HEAD).unwrap() else {
            panic!("liveness route was not a probe");
        };
        assert_eq!(live.status(), StatusCode::OK);
        assert_eq!(live.headers()[CACHE_CONTROL], PROBE_CACHE_CONTROL);
        assert_eq!(live.headers()[CONTENT_LENGTH], LIVE_BODY.len().to_string());
        assert!(live
            .into_body()
            .collect()
            .await
            .unwrap()
            .to_bytes()
            .is_empty());

        let NativeMatch::Probe(not_ready) = router.route("/ready", &Method::GET).unwrap() else {
            panic!("readiness route was not a probe");
        };
        assert_eq!(not_ready.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(
            not_ready.into_body().collect().await.unwrap().to_bytes(),
            NOT_READY_BODY
        );

        let NativeMatch::Probe(disallowed) = router.route("/ready", &Method::POST).unwrap() else {
            panic!("readiness route was not a probe");
        };
        assert_eq!(disallowed.status(), StatusCode::METHOD_NOT_ALLOWED);
        assert_eq!(disallowed.headers()[ALLOW], PROBE_ALLOW);
        assert_eq!(
            router.probe_metrics(),
            ProbeMetrics {
                liveness_requests: 1,
                readiness_requests: 2,
                ready_responses: 1,
                not_ready_responses: 1,
                method_not_allowed_responses: 1,
            }
        );
        assert_eq!(ProbeKind::Liveness.telemetry_label(), "liveness");
        assert_eq!(ProbeKind::Readiness.telemetry_label(), "readiness");
        assert!(ProbeKind::Liveness.suppress_success_log());
        assert!(ProbeKind::Readiness.suppress_success_log());
    }

    #[test]
    fn draining_forces_every_readiness_route_not_ready() {
        let files = empty_files();
        let lease = crate::readiness::test_lease(true);
        let router = NativeRouter::activate(
            &files,
            Vec::new(),
            Vec::new(),
            vec![ReadinessRouteSpec {
                at: "/ready".to_owned(),
                readiness: lease,
            }],
        )
        .unwrap();
        let NativeMatch::Probe(before) = router.route("/ready", &Method::GET).unwrap() else {
            panic!("readiness route was not a probe");
        };
        assert_eq!(before.status(), StatusCode::OK);
        router.begin_draining();
        let NativeMatch::Probe(after) = router.route("/ready", &Method::GET).unwrap() else {
            panic!("readiness route was not a probe");
        };
        assert_eq!(after.status(), StatusCode::SERVICE_UNAVAILABLE);
    }
}
