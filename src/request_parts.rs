//! Roc-compatible ARC ownership for immutable Hyper request metadata.
//!
//! A seamless Roc string may point at bytes anywhere, provided its encoded
//! allocation pointer identifies a live atomic Roc reference count. This lets
//! request strings borrow Hyper's existing URI and header storage without
//! copying their payload bytes. The final Roc reference release is routed back
//! here, where dropping the heap resource releases all of the Hyper storage.

use crate::host_resource::{DeallocRoute, HostResourceHeap};
use crate::roc_platform_abi::{incref_box, RocBox, RocStr};
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
}

static REQUEST_PARTS: OnceLock<HostResourceHeap<RequestPartsResource>> = OnceLock::new();

fn request_parts() -> &'static HostResourceHeap<RequestPartsResource> {
    REQUEST_PARTS.get_or_init(|| HostResourceHeap::new(MAX_LIVE_REQUEST_BACKINGS))
}

pub(crate) fn request_target(parts: &hyper::http::request::Parts) -> &str {
    if parts.method == hyper::Method::CONNECT {
        if let Some(authority) = parts.uri.authority() {
            return authority.as_str();
        }
    }
    parts
        .uri
        .path_and_query()
        .map(hyper::http::uri::PathAndQuery::as_str)
        .unwrap_or("/")
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
    ) -> Result<Self, Box<hyper::http::request::Parts>> {
        let parts = Box::new(parts);
        let reservation = match request_parts().reserve() {
            Ok(reservation) => reservation,
            Err(_) => return Err(parts),
        };
        let allocation_ptr = reservation.insert(RequestPartsResource { parts });
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

    pub(crate) fn target(&self) -> &str {
        request_target(&self.resource.parts)
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
        assert!(
            reference_count > 0,
            "request backing must own at least one seamless reference"
        );
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

pub(crate) fn active_backings() -> usize {
    REQUEST_PARTS.get().map_or(0, HostResourceHeap::active)
}

pub(crate) fn high_water() -> usize {
    REQUEST_PARTS.get().map_or(0, HostResourceHeap::high_water)
}
