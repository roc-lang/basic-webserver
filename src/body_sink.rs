//! Bounded, authorized request-body transfers into startup-declared writable
//! roots.
//!
//! Each transfer creates an unpredictable, exclusive staging file in the
//! destination directory, writes through the request body's existing bounded
//! channel, and publishes with an atomic create-new hard link. Directory
//! traversal uses held no-follow handles, so a concurrent rename cannot turn a
//! validated component into an escape from the declared root.

use crate::file_server::{validate_relative_path, validate_root_id};
use crate::request_body::BodyError;
use bytes::Bytes;
#[cfg(unix)]
use cap_primitives::fs::OpenOptionsExt;
use cap_primitives::fs::{
    hard_link, open, open_ambient_dir, open_dir_nofollow, remove_file, FollowSymlinks, OpenOptions,
};
use ring::digest::{Context as DigestContext, SHA256};
use ring::rand::{SecureRandom, SystemRandom};
use std::collections::BTreeMap;
use std::fmt;
use std::fs::File;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};

const MAX_WRITABLE_ROOTS: usize = 64;
const MAX_SINK_TIMEOUT: Duration = Duration::from_secs(24 * 60 * 60);
const STAGING_CREATE_ATTEMPTS: usize = 16;
const STAGING_PREFIX: &str = ".basic-webserver-upload-";

#[derive(Debug)]
pub(crate) struct WritableRootSpec {
    pub(crate) id: String,
    pub(crate) path: PathBuf,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DigestKind {
    None,
    Sha256,
}

impl DigestKind {
    pub(crate) fn from_abi(tag: u8) -> Result<Self, SinkError> {
        match tag {
            0 => Ok(Self::None),
            1 => Ok(Self::Sha256),
            _ => Err(SinkError::Filesystem(
                "invalid request-body sink digest kind".to_owned(),
            )),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SinkSuccess {
    pub(crate) bytes_written: u64,
    pub(crate) sha256: Option<[u8; 32]>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum SinkError {
    Body(BodyError),
    Saturated,
    Stopping,
    DestinationExists,
    InvalidRoot,
    InvalidRelativeFile,
    PermissionDenied,
    StorageFull,
    Filesystem(String),
    PublishFailed(String),
    CleanupFailed(String),
}

impl fmt::Display for SinkError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Body(error) => write!(formatter, "request body failed: {error:?}"),
            Self::Saturated => formatter.write_str("request-body sink capacity is exhausted"),
            Self::Stopping => formatter.write_str("server is stopping"),
            Self::DestinationExists => formatter.write_str("destination already exists"),
            Self::InvalidRoot => formatter.write_str("invalid or undeclared writable root"),
            Self::InvalidRelativeFile => formatter.write_str("invalid relative file path"),
            Self::PermissionDenied => formatter.write_str("filesystem permission denied"),
            Self::StorageFull => formatter.write_str("filesystem storage is full"),
            Self::Filesystem(detail) => write!(formatter, "filesystem failure: {detail}"),
            Self::PublishFailed(detail) => write!(formatter, "publication failure: {detail}"),
            Self::CleanupFailed(detail) => write!(formatter, "staging cleanup failure: {detail}"),
        }
    }
}

#[derive(Debug)]
struct WritableRoot {
    handle: File,
}

#[derive(Debug, Default)]
struct SinkDiagnostics {
    active: AtomicUsize,
    high_water: AtomicUsize,
}

#[derive(Clone, Debug)]
pub(crate) struct BodySinkService {
    roots: Arc<BTreeMap<String, Arc<WritableRoot>>>,
    permits: Arc<Semaphore>,
    timeout: Duration,
    diagnostics: Arc<SinkDiagnostics>,
}

impl BodySinkService {
    pub(crate) fn activate(
        specs: Vec<WritableRootSpec>,
        max_concurrent: usize,
        timeout: Duration,
    ) -> Result<Self, String> {
        if specs.len() > MAX_WRITABLE_ROOTS {
            return Err(format!(
                "at most {MAX_WRITABLE_ROOTS} writable roots may be declared"
            ));
        }
        if max_concurrent == 0 {
            return Err("maximum concurrent request-body sinks must be non-zero".to_owned());
        }
        if timeout.is_zero() {
            return Err("request-body sink timeout must be non-zero".to_owned());
        }
        if timeout > MAX_SINK_TIMEOUT {
            return Err("request-body sink timeout cannot exceed 24 hours".to_owned());
        }

        let mut roots = BTreeMap::new();
        for spec in specs {
            validate_root_id(&spec.id)?;
            if roots.contains_key(&spec.id) {
                return Err(format!("duplicate writable root identifier {:?}", spec.id));
            }
            let handle = open_ambient_dir(&spec.path, cap_primitives::ambient_authority())
                .map_err(|error| {
                    format!(
                        "writable root {:?} is missing, inaccessible, or not a directory: {error}",
                        spec.id
                    )
                })?;
            let metadata = handle.metadata().map_err(|error| {
                format!("failed to inspect writable root {:?}: {error}", spec.id)
            })?;
            if !metadata.is_dir() {
                return Err(format!("writable root {:?} is not a directory", spec.id));
            }
            roots.insert(spec.id, Arc::new(WritableRoot { handle }));
        }

        Ok(Self {
            roots: Arc::new(roots),
            permits: Arc::new(Semaphore::new(max_concurrent)),
            timeout,
            diagnostics: Arc::new(SinkDiagnostics::default()),
        })
    }

    pub(crate) fn timeout(&self) -> Duration {
        self.timeout
    }

    pub(crate) fn write_file<Next, Stopping>(
        &self,
        root_id: &str,
        relative: &str,
        digest: DigestKind,
        mut next_chunk: Next,
        mut stopping: Stopping,
    ) -> Result<SinkSuccess, SinkError>
    where
        Next: FnMut() -> Result<Option<Bytes>, BodyError>,
        Stopping: FnMut() -> bool,
    {
        if stopping() {
            return Err(SinkError::Stopping);
        }
        let root = self
            .roots
            .get(root_id)
            .cloned()
            .ok_or(SinkError::InvalidRoot)?;
        let segments =
            validate_relative_path(relative).map_err(|_| SinkError::InvalidRelativeFile)?;
        let permit = Arc::clone(&self.permits)
            .try_acquire_owned()
            .map_err(|_| SinkError::Saturated)?;
        let _lease = SinkLease::new(permit, Arc::clone(&self.diagnostics));

        let (destination, parents) = segments
            .split_last()
            .expect("validated relative paths contain a final component");
        let parent = open_parent(&root.handle, parents).map_err(map_io_error)?;
        let mut staging = StagingFile::create(parent).map_err(map_io_error)?;
        let mut bytes_written = 0u64;
        let mut hasher = (digest == DigestKind::Sha256).then(|| DigestContext::new(&SHA256));

        loop {
            if stopping() {
                return Err(fail_with_cleanup(staging, SinkError::Stopping));
            }
            let chunk = match next_chunk() {
                Ok(Some(chunk)) => chunk,
                Ok(None) => break,
                Err(error) => {
                    return Err(fail_with_cleanup(staging, SinkError::Body(error)));
                }
            };
            bytes_written = match bytes_written.checked_add(chunk.len() as u64) {
                Some(total) => total,
                None => {
                    return Err(fail_with_cleanup(
                        staging,
                        SinkError::Filesystem("written-byte count overflow".to_owned()),
                    ));
                }
            };
            if let Err(error) = staging.file_mut().write_all(&chunk) {
                let error = map_io_error(error);
                return Err(fail_with_cleanup(staging, error));
            }
            if let Some(hasher) = &mut hasher {
                hasher.update(&chunk);
            }
        }

        if stopping() {
            return Err(fail_with_cleanup(staging, SinkError::Stopping));
        }
        if let Err(error) = staging.publish(destination) {
            let mapped = if error.kind() == io::ErrorKind::AlreadyExists {
                SinkError::DestinationExists
            } else {
                SinkError::PublishFailed(error.to_string())
            };
            return Err(fail_with_cleanup(staging, mapped));
        }
        staging
            .cleanup()
            .map_err(|error| SinkError::CleanupFailed(error.to_string()))?;

        Ok(SinkSuccess {
            bytes_written,
            sha256: hasher.map(|hasher| {
                hasher
                    .finish()
                    .as_ref()
                    .try_into()
                    .expect("SHA-256 always produces 32 bytes")
            }),
        })
    }

    pub(crate) fn active_sinks(&self) -> usize {
        self.diagnostics.active.load(Ordering::Acquire)
    }

    pub(crate) fn high_water_sinks(&self) -> usize {
        self.diagnostics.high_water.load(Ordering::Acquire)
    }
}

fn open_parent(root: &File, parents: &[String]) -> io::Result<File> {
    let mut current = root.try_clone()?;
    for parent in parents {
        current = open_dir_nofollow(&current, Path::new(parent))?;
    }
    Ok(current)
}

struct SinkLease {
    _permit: OwnedSemaphorePermit,
    diagnostics: Arc<SinkDiagnostics>,
}

impl SinkLease {
    fn new(permit: OwnedSemaphorePermit, diagnostics: Arc<SinkDiagnostics>) -> Self {
        let active = diagnostics.active.fetch_add(1, Ordering::AcqRel) + 1;
        diagnostics.high_water.fetch_max(active, Ordering::AcqRel);
        Self {
            _permit: permit,
            diagnostics,
        }
    }
}

impl Drop for SinkLease {
    fn drop(&mut self) {
        let previous = self.diagnostics.active.fetch_sub(1, Ordering::AcqRel);
        debug_assert!(previous > 0, "request-body sink accounting underflow");
    }
}

struct StagingFile {
    parent: File,
    name: String,
    file: Option<File>,
}

impl StagingFile {
    fn create(parent: File) -> io::Result<Self> {
        for _ in 0..STAGING_CREATE_ATTEMPTS {
            let name = random_staging_name()?;
            let mut options = OpenOptions::new();
            options
                .write(true)
                .create_new(true)
                ._cap_fs_ext_follow(FollowSymlinks::No);
            #[cfg(unix)]
            options.mode(0o600);
            match open(&parent, Path::new(&name), &options) {
                Ok(file) => {
                    return Ok(Self {
                        parent,
                        name,
                        file: Some(file),
                    });
                }
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "failed to allocate a unique staging filename",
        ))
    }

    fn file_mut(&mut self) -> &mut File {
        self.file
            .as_mut()
            .expect("staging file remains open until publication")
    }

    fn publish(&mut self, destination: &str) -> io::Result<()> {
        self.file.take();
        hard_link(
            &self.parent,
            Path::new(&self.name),
            &self.parent,
            Path::new(destination),
        )
    }

    fn cleanup(mut self) -> io::Result<()> {
        self.file.take();
        let result = remove_file(&self.parent, Path::new(&self.name));
        if result.is_ok() {
            self.name.clear();
        }
        result
    }
}

impl Drop for StagingFile {
    fn drop(&mut self) {
        self.file.take();
        if !self.name.is_empty() {
            let _ = remove_file(&self.parent, Path::new(&self.name));
        }
    }
}

fn random_staging_name() -> io::Result<String> {
    let mut random = [0u8; 24];
    SystemRandom::new()
        .fill(&mut random)
        .map_err(|_| io::Error::other("operating-system randomness failed"))?;
    let mut name = String::with_capacity(STAGING_PREFIX.len() + random.len() * 2);
    name.push_str(STAGING_PREFIX);
    for byte in random {
        use fmt::Write as _;
        write!(name, "{byte:02x}").expect("writing to a String cannot fail");
    }
    Ok(name)
}

fn fail_with_cleanup(mut staging: StagingFile, original: SinkError) -> SinkError {
    staging.file.take();
    match staging.cleanup() {
        Ok(()) => original,
        Err(error) => SinkError::CleanupFailed(format!(
            "{original}; additionally failed to remove staging file: {error}"
        )),
    }
}

fn map_io_error(error: io::Error) -> SinkError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => SinkError::PermissionDenied,
        io::ErrorKind::StorageFull | io::ErrorKind::QuotaExceeded => SinkError::StorageFull,
        _ => SinkError::Filesystem(error.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::{Arc, Barrier};
    use std::thread;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_dir() -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "basic-webserver-body-sink-{}-{unique}",
            std::process::id()
        ));
        fs::create_dir(&path).unwrap();
        path
    }

    fn service(path: &Path, max_concurrent: usize) -> BodySinkService {
        BodySinkService::activate(
            vec![WritableRootSpec {
                id: "uploads".to_owned(),
                path: path.to_owned(),
            }],
            max_concurrent,
            Duration::from_secs(1),
        )
        .unwrap()
    }

    fn chunks(values: &[&'static [u8]]) -> impl FnMut() -> Result<Option<Bytes>, BodyError> {
        let mut values = values
            .iter()
            .map(|value| Bytes::from_static(value))
            .collect::<Vec<_>>()
            .into_iter();
        move || Ok(values.next())
    }

    fn staging_entries(path: &Path) -> Vec<String> {
        fs::read_dir(path)
            .unwrap()
            .filter_map(|entry| {
                let name = entry.unwrap().file_name().to_string_lossy().into_owned();
                name.starts_with(STAGING_PREFIX).then_some(name)
            })
            .collect()
    }

    #[test]
    fn writes_multiple_chunks_with_authoritative_bytes_and_digest() {
        let root = temp_dir();
        fs::create_dir(root.join("nested")).unwrap();
        let result = service(&root, 1)
            .write_file(
                "uploads",
                "nested/file.bin",
                DigestKind::Sha256,
                chunks(&[b"abc", b"def"]),
                || false,
            )
            .unwrap();
        assert_eq!(result.bytes_written, 6);
        assert_eq!(
            result.sha256.unwrap(),
            [
                190, 245, 126, 199, 245, 58, 109, 64, 190, 182, 64, 167, 128, 166, 57, 200, 59,
                194, 154, 200, 169, 129, 111, 31, 198, 197, 198, 220, 217, 60, 71, 33,
            ]
        );
        assert_eq!(fs::read(root.join("nested/file.bin")).unwrap(), b"abcdef");
        assert!(staging_entries(&root.join("nested")).is_empty());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn never_overwrites_and_concurrent_publication_has_one_winner() {
        let root = temp_dir();
        fs::write(root.join("existing"), b"original").unwrap();
        let service = service(&root, 2);
        assert_eq!(
            service.write_file(
                "uploads",
                "existing",
                DigestKind::None,
                chunks(&[b"replacement"]),
                || false,
            ),
            Err(SinkError::DestinationExists)
        );
        assert_eq!(fs::read(root.join("existing")).unwrap(), b"original");

        let barrier = Arc::new(Barrier::new(2));
        let handles = [b"first".as_slice(), b"second".as_slice()].map(|body| {
            let service = service.clone();
            let barrier = Arc::clone(&barrier);
            thread::spawn(move || {
                let mut chunk = Some(Bytes::copy_from_slice(body));
                service.write_file(
                    "uploads",
                    "raced",
                    DigestKind::None,
                    move || {
                        barrier.wait();
                        Ok(chunk.take())
                    },
                    || false,
                )
            })
        });
        let results = handles.map(|handle| handle.join().unwrap());
        assert_eq!(results.iter().filter(|result| result.is_ok()).count(), 1);
        assert_eq!(
            results
                .iter()
                .filter(|result| **result == Err(SinkError::DestinationExists))
                .count(),
            1
        );
        assert!(staging_entries(&root).is_empty());
        drop(service);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn source_failure_and_stopping_remove_staging_state() {
        let root = temp_dir();
        let service = service(&root, 1);
        let mut sent = false;
        let result = service.write_file(
            "uploads",
            "partial",
            DigestKind::None,
            || {
                if sent {
                    Err(BodyError::ClientDisconnected)
                } else {
                    sent = true;
                    Ok(Some(Bytes::from_static(b"partial")))
                }
            },
            || false,
        );
        assert_eq!(result, Err(SinkError::Body(BodyError::ClientDisconnected)));
        assert!(!root.join("partial").exists());
        assert!(staging_entries(&root).is_empty());

        assert_eq!(
            service.write_file(
                "uploads",
                "stopping",
                DigestKind::None,
                chunks(&[b"data"]),
                || true,
            ),
            Err(SinkError::Stopping)
        );
        assert!(staging_entries(&root).is_empty());
        drop(service);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn invalid_authority_paths_and_symlink_parents_are_rejected() {
        let root = temp_dir();
        let outside = temp_dir();
        let service = service(&root, 1);
        assert_eq!(
            service.write_file("missing", "file", DigestKind::None, chunks(&[]), || false,),
            Err(SinkError::InvalidRoot)
        );
        assert_eq!(
            service.write_file("uploads", "../file", DigestKind::None, chunks(&[]), || {
                false
            },),
            Err(SinkError::InvalidRelativeFile)
        );

        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(&outside, root.join("escape")).unwrap();
            assert!(matches!(
                service.write_file(
                    "uploads",
                    "escape/file",
                    DigestKind::None,
                    chunks(&[b"outside"]),
                    || false,
                ),
                Err(SinkError::Filesystem(_))
            ));
            assert!(!outside.join("file").exists());
        }

        drop(service);
        fs::remove_dir_all(root).unwrap();
        fs::remove_dir_all(outside).unwrap();
    }

    #[test]
    fn saturation_is_immediate_and_capacity_recovers() {
        let root = temp_dir();
        let service = service(&root, 1);
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let first = {
            let service = service.clone();
            let entered = Arc::clone(&entered);
            let release = Arc::clone(&release);
            thread::spawn(move || {
                let mut sent = false;
                service.write_file(
                    "uploads",
                    "first",
                    DigestKind::None,
                    move || {
                        if sent {
                            Ok(None)
                        } else {
                            sent = true;
                            entered.wait();
                            release.wait();
                            Ok(Some(Bytes::from_static(b"first")))
                        }
                    },
                    || false,
                )
            })
        };
        entered.wait();
        assert_eq!(
            service.write_file(
                "uploads",
                "second",
                DigestKind::None,
                chunks(&[b"second"]),
                || false,
            ),
            Err(SinkError::Saturated)
        );
        release.wait();
        assert!(first.join().unwrap().is_ok());
        assert_eq!(service.active_sinks(), 0);
        assert_eq!(service.high_water_sinks(), 1);
        assert!(service
            .write_file(
                "uploads",
                "second",
                DigestKind::None,
                chunks(&[b"second"]),
                || false,
            )
            .is_ok());
        assert!(staging_entries(&root).is_empty());
        drop(service);
        fs::remove_dir_all(root).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn held_parent_handle_defeats_a_component_swap() {
        let root = temp_dir();
        let outside = temp_dir();
        fs::create_dir(root.join("slot")).unwrap();
        let root_handle = open_ambient_dir(&root, cap_primitives::ambient_authority()).unwrap();
        let parent = open_parent(&root_handle, &["slot".to_owned()]).unwrap();

        fs::rename(root.join("slot"), root.join("slot-original")).unwrap();
        std::os::unix::fs::symlink(&outside, root.join("slot")).unwrap();

        let mut staging = StagingFile::create(parent).unwrap();
        staging.file_mut().write_all(b"inside").unwrap();
        staging.publish("file").unwrap();
        staging.cleanup().unwrap();
        assert_eq!(
            fs::read(root.join("slot-original/file")).unwrap(),
            b"inside"
        );
        assert!(!outside.join("file").exists());

        drop(root_handle);
        fs::remove_dir_all(root).unwrap();
        fs::remove_dir_all(outside).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn staging_files_are_owner_only() {
        use std::os::unix::fs::MetadataExt;

        let root = temp_dir();
        let root_handle = open_ambient_dir(&root, cap_primitives::ambient_authority()).unwrap();
        let staging = StagingFile::create(root_handle).unwrap();
        let metadata = fs::metadata(root.join(&staging.name)).unwrap();
        assert_eq!(metadata.mode() & 0o777, 0o600);
        staging.cleanup().unwrap();
        fs::remove_dir_all(root).unwrap();
    }
}
