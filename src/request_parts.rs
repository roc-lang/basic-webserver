//! Roc-compatible ARC ownership for immutable Hyper request metadata.
//!
//! A seamless Roc string may point at bytes anywhere, provided its encoded
//! allocation pointer identifies a live atomic Roc reference count. This lets
//! request strings borrow Hyper's existing URI and header storage without
//! copying their payload bytes. The final Roc reference release is routed back
//! here, where dropping the heap resource releases all of the Hyper storage.

use crate::host_resource::{DeallocRoute, HostResourceHeap};
use crate::request_target::{AuthorityView, RequestMetadata, TargetKind};
use crate::roc_platform_abi::{decref_box, incref_box, RocBox, RocStr};
use core::ffi::c_void;
use std::sync::OnceLock;

const SEAMLESS_SLICE_TAG: usize = 1;

// The resource-heap token format supports at most 65,535 stable slots. Keeping
// request metadata has a finite process-wide bound; exhaustion falls back to
// bounded copies rather than rejecting an otherwise admissible request.
const MAX_LIVE_REQUEST_BACKINGS: usize = 65_535;

struct RequestPartsResource {
    // Indirection keeps the fixed 65,535-slot ARC-token slab small; only live
    // requests allocate their comparatively large Hyper Parts value.
    parts: Box<hyper::http::request::Parts>,
    metadata: RequestMetadata,
}

static REQUEST_PARTS: OnceLock<HostResourceHeap<RequestPartsResource>> = OnceLock::new();

fn request_parts() -> &'static HostResourceHeap<RequestPartsResource> {
    REQUEST_PARTS.get_or_init(|| HostResourceHeap::new(MAX_LIVE_REQUEST_BACKINGS))
}

/// One initial Roc ARC reference to a stable request-parts heap slot.
///
/// Construction and conversion happen synchronously without fallible work
/// between them. `install` expands the initial reference to cover every
/// seamless descriptor handed to Roc.
pub(crate) struct RequestPartsBacking {
    allocation_ptr: *mut u64,
    resource: &'static RequestPartsResource,
}

impl RequestPartsBacking {
    pub(crate) fn new(
        parts: hyper::http::request::Parts,
        metadata: RequestMetadata,
    ) -> Result<Self, Box<hyper::http::request::Parts>> {
        let parts = Box::new(parts);
        let reservation = match request_parts().reserve() {
            Ok(reservation) => reservation,
            Err(_) => return Err(parts),
        };
        let allocation_ptr = reservation.insert(RequestPartsResource { parts, metadata });
        // SAFETY: this wrapper owns the initial live Roc reference committed by
        // `insert` and retains it until `install` transfers all references.
        let resource = unsafe {
            request_parts()
                .get(allocation_ptr)
                .expect("new request backing must resolve")
        };
        Ok(Self {
            allocation_ptr,
            resource,
        })
    }

    pub(crate) fn method(&self) -> &hyper::Method {
        &self.resource.parts.method
    }

    pub(crate) fn headers(&self) -> &hyper::HeaderMap {
        &self.resource.parts.headers
    }

    pub(crate) fn target_kind(&self) -> TargetKind {
        self.resource.metadata.target_kind()
    }

    pub(crate) fn resource_path(&self) -> Option<&str> {
        self.resource
            .metadata
            .resource_path(&self.resource.parts.uri)
    }

    pub(crate) fn resource_path_is_backed(&self) -> bool {
        self.resource.parts.uri.path_and_query().is_some()
    }

    pub(crate) fn resource_query(&self) -> Option<&str> {
        self.resource
            .metadata
            .resource_query(&self.resource.parts.uri)
    }

    pub(crate) fn target_authority(&self) -> Option<AuthorityView<'_>> {
        self.resource
            .metadata
            .target_authority(&self.resource.parts.uri, &self.resource.parts.headers)
    }

    pub(crate) fn effective_authority(&self) -> Option<AuthorityView<'_>> {
        self.resource
            .metadata
            .effective_authority(&self.resource.parts.uri, &self.resource.parts.headers)
    }

    /// Construct one owned seamless Roc string descriptor into this backing.
    pub(crate) fn roc_str(&self, value: &str) -> RocStr {
        let allocation_ptr = self.allocation_ptr as usize;
        debug_assert_eq!(
            allocation_ptr & SEAMLESS_SLICE_TAG,
            0,
            "request backing token must be pointer aligned"
        );
        RocStr {
            bytes: value.as_ptr().cast_mut(),
            capacity_or_alloc_ptr: allocation_ptr | SEAMLESS_SLICE_TAG,
            length: value.len(),
        }
    }

    /// Transfer this wrapper's initial reference to `reference_count`
    /// independently owned seamless descriptors.
    pub(crate) fn install(self, reference_count: usize) {
        if reference_count == 0 {
            // SAFETY: this wrapper owns the heap allocation's only reference.
            // The host allocator recognizes its base and routes final release
            // back through this module.
            unsafe { decref_box(self.allocation_ptr as RocBox, crate::abi::roc_host()) };
            return;
        }
        let additional = isize::try_from(reference_count - 1)
            .expect("request metadata reference count must fit Roc's refcount");
        if additional != 0 {
            // SAFETY: `self` owns the initial live heap reference. These
            // additional references correspond exactly to descriptors about
            // to be transferred together in one ServerRequest.
            unsafe { incref_box(self.allocation_ptr as RocBox, additional) };
        }
    }
}

/// Route a final Roc seamless-reference release back to its Hyper owner.
///
/// `HostResourceHeap::route_dealloc` rejects non-owned pointers with only
/// stable-range arithmetic. Its mutex is acquired only for an address in this
/// request heap, so ordinary Roc string/list frees do not globally serialize.
pub(crate) fn route_dealloc(ptr: *mut c_void) -> DeallocRoute {
    match REQUEST_PARTS.get() {
        Some(heap) => heap.route_dealloc(ptr),
        None => DeallocRoute::NotOwned,
    }
}

pub(crate) fn contains_address(ptr: *const c_void) -> bool {
    REQUEST_PARTS
        .get()
        .is_some_and(|heap| heap.contains_address(ptr))
}

pub(crate) fn validate_seamless_range(
    allocation_ptr: *mut u8,
    range_ptr: *const u8,
    range_length: usize,
) {
    let resource = unsafe {
        request_parts()
            .get(allocation_ptr.cast::<u64>())
            .unwrap_or_else(|_| {
                eprintln!("fatal: stale request metadata seamless allocation");
                std::process::abort();
            })
    };
    let range_start = range_ptr as usize;
    let range_end = range_start.checked_add(range_length).unwrap_or_else(|| {
        eprintln!("fatal: request metadata seamless range overflow");
        std::process::abort();
    });
    let contains = |bytes: &[u8]| {
        let start = bytes.as_ptr() as usize;
        let Some(end) = start.checked_add(bytes.len()) else {
            return false;
        };
        start <= range_start && range_end <= end
    };
    let parts = &resource.parts;
    let valid = contains(parts.method.as_str().as_bytes())
        || parts
            .uri
            .path_and_query()
            .is_some_and(|value| contains(value.as_str().as_bytes()))
        || parts
            .uri
            .authority()
            .is_some_and(|value| contains(value.as_str().as_bytes()))
        || parts
            .headers
            .iter()
            .any(|(name, value)| contains(name.as_str().as_bytes()) || contains(value.as_bytes()));
    if !valid {
        eprintln!("fatal: seamless response slice escapes its request metadata backing");
        std::process::abort();
    }
}

pub(crate) fn active_backings() -> usize {
    REQUEST_PARTS.get().map_or(0, HostResourceHeap::active)
}

pub(crate) fn high_water() -> usize {
    REQUEST_PARTS.get().map_or(0, HostResourceHeap::high_water)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host_resource::LookupError;

    #[test]
    fn installing_zero_seamless_references_releases_the_backing() {
        let request = hyper::Request::builder()
            .method(hyper::Method::OPTIONS)
            .uri("*")
            .version(hyper::Version::HTTP_10)
            .body(())
            .unwrap();
        let metadata = RequestMetadata::validate(&request).unwrap();
        let (parts, _) = request.into_parts();
        let backing = RequestPartsBacking::new(parts, metadata).unwrap();
        let allocation_ptr = backing.allocation_ptr;

        backing.install(0);

        assert!(matches!(
            unsafe { request_parts().get(allocation_ptr) },
            Err(LookupError::Stale)
        ));
    }
}
