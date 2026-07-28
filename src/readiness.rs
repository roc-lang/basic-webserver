//! Bounded, ARC-owned host readiness gates.

use core::ffi::c_void;
use core::mem::ManuallyDrop;
use core::sync::atomic::{AtomicU8, Ordering};
use std::sync::OnceLock;

use crate::abi::{
    roc_host, ReadinessCreateResult, ReadinessCreateResultPayload, ReadinessCreateResultTag,
    ReadinessSetError, ReadinessSetResult, ReadinessSetResultPayload, ReadinessSetResultTag,
};
use crate::host_resource::{DeallocRoute, HostResourceHeap, LookupError, ReserveError};
use crate::roc_platform_abi::{decref_box, incref_box, RocBox};

const MAX_READINESS_GATES: usize = 64;
const NOT_READY: u8 = 0;
const READY: u8 = 1;
const STOPPING: u8 = 2;

struct ReadinessGate {
    state: AtomicU8,
}

impl ReadinessGate {
    fn new(ready: bool) -> Self {
        Self {
            state: AtomicU8::new(if ready { READY } else { NOT_READY }),
        }
    }

    fn is_ready(&self) -> bool {
        self.state.load(Ordering::Acquire) == READY
    }

    fn set(&self, ready: bool) -> Result<(), ReadinessSetError> {
        let desired = if ready { READY } else { NOT_READY };
        self.state
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |current| {
                (current != STOPPING).then_some(desired)
            })
            .map(|_| ())
            .map_err(|_| ReadinessSetError::ServerStopping)
    }

    fn begin_stopping(&self) {
        self.state.store(STOPPING, Ordering::Release);
    }
}

static READINESS_GATES: OnceLock<HostResourceHeap<ReadinessGate>> = OnceLock::new();

fn readiness_gates() -> &'static HostResourceHeap<ReadinessGate> {
    READINESS_GATES.get_or_init(|| HostResourceHeap::new(MAX_READINESS_GATES))
}

unsafe fn gate_ref(handle: *mut u64) -> Result<&'static ReadinessGate, LookupError> {
    unsafe { readiness_gates().get(handle) }
}

fn set_handle(handle: *mut u64, ready: bool) -> Result<(), ReadinessSetError> {
    match unsafe { gate_ref(handle) } {
        Ok(gate) => gate.set(ready),
        Err(LookupError::Invalid) => Err(ReadinessSetError::InvalidReadiness),
        Err(LookupError::Stale) => Err(ReadinessSetError::StaleReadiness),
    }
}

/// An owned host reference retained by an activated readiness route.
///
/// The application's context normally owns another reference. Keeping this
/// route reference makes the native route independent of context record shape
/// and keeps the gate alive through the final shutdown hook.
pub(crate) struct ReadinessLease {
    handle: *mut u64,
}

impl ReadinessLease {
    pub(crate) fn retain(handle: *mut u64) -> Result<Self, String> {
        match unsafe { gate_ref(handle) } {
            Ok(_) => {
                unsafe { incref_box(handle as RocBox, 1) };
                Ok(Self { handle })
            }
            Err(LookupError::Invalid) => {
                Err("readiness route references an invalid capability".to_owned())
            }
            Err(LookupError::Stale) => {
                Err("readiness route references a stale capability".to_owned())
            }
        }
    }

    pub(crate) fn is_ready(&self) -> bool {
        unsafe { gate_ref(self.handle) }.is_ok_and(ReadinessGate::is_ready)
    }

    pub(crate) fn begin_stopping(&self) {
        if let Ok(gate) = unsafe { gate_ref(self.handle) } {
            gate.begin_stopping();
        }
    }
}

// SAFETY: the lease owns a stable host-resource slot, and all mutable gate
// state is atomic.
unsafe impl Send for ReadinessLease {}
unsafe impl Sync for ReadinessLease {}

impl Drop for ReadinessLease {
    fn drop(&mut self) {
        unsafe { decref_box(self.handle as RocBox, roc_host()) };
    }
}

fn create_ok(handle: *mut u64) -> ReadinessCreateResult {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut result: ReadinessCreateResult = core::mem::zeroed();
        core::ptr::write(result.payload.as_mut_ptr().cast::<*mut u64>(), handle);
        result.tag = ReadinessCreateResultTag::Ok;
        result
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        ReadinessCreateResult {
            payload: ReadinessCreateResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: ReadinessCreateResultTag::Ok,
        }
    }
}

fn create_err() -> ReadinessCreateResult {
    #[cfg(target_pointer_width = "32")]
    {
        ReadinessCreateResult {
            _payload_alignment: [],
            payload: [0; 4],
            tag: ReadinessCreateResultTag::Err,
        }
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        ReadinessCreateResult {
            payload: ReadinessCreateResultPayload { err: [] },
            tag: ReadinessCreateResultTag::Err,
        }
    }
}

fn set_ok() -> ReadinessSetResult {
    #[cfg(target_pointer_width = "32")]
    {
        ReadinessSetResult {
            _payload_alignment: [],
            payload: [0],
            tag: ReadinessSetResultTag::Ok,
        }
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        ReadinessSetResult {
            payload: ReadinessSetResultPayload { ok: [] },
            tag: ReadinessSetResultTag::Ok,
        }
    }
}

fn set_err(error: ReadinessSetError) -> ReadinessSetResult {
    #[cfg(target_pointer_width = "32")]
    unsafe {
        let mut result: ReadinessSetResult = core::mem::zeroed();
        core::ptr::write(
            result.payload.as_mut_ptr().cast::<ReadinessSetError>(),
            error,
        );
        result.tag = ReadinessSetResultTag::Err;
        result
    }
    #[cfg(not(target_pointer_width = "32"))]
    {
        ReadinessSetResult {
            payload: ReadinessSetResultPayload {
                err: ManuallyDrop::new(error),
            },
            tag: ReadinessSetResultTag::Err,
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_readiness_create(initially_ready: bool) -> ReadinessCreateResult {
    match readiness_gates().reserve() {
        Ok(reservation) => create_ok(reservation.insert(ReadinessGate::new(initially_ready))),
        Err(ReserveError::Capacity) => create_err(),
    }
}

#[no_mangle]
pub extern "C" fn hosted_readiness_set(handle: *mut u64, ready: bool) -> ReadinessSetResult {
    let result = set_handle(handle, ready);
    // SAFETY: hosted arguments transfer one owned Roc reference.
    unsafe { decref_box(handle as RocBox, roc_host()) };
    match result {
        Ok(()) => set_ok(),
        Err(error) => set_err(error),
    }
}

pub(crate) fn route_resource_dealloc(ptr: *mut c_void) -> DeallocRoute {
    READINESS_GATES
        .get()
        .map_or(DeallocRoute::NotOwned, |heap| heap.route_dealloc(ptr))
}

pub(crate) fn contains_resource_address(ptr: *const c_void) -> bool {
    READINESS_GATES
        .get()
        .is_some_and(|heap| heap.contains_address(ptr))
}

pub(crate) fn active_resources() -> usize {
    READINESS_GATES.get().map_or(0, HostResourceHeap::active)
}

pub(crate) fn resource_high_water() -> usize {
    READINESS_GATES
        .get()
        .map_or(0, HostResourceHeap::high_water)
}

#[cfg(test)]
pub(crate) fn test_lease(ready: bool) -> ReadinessLease {
    crate::abi::initialize_test_roc_host();
    let handle = readiness_gates()
        .reserve()
        .unwrap()
        .insert(ReadinessGate::new(ready));
    let lease = ReadinessLease::retain(handle).unwrap();
    unsafe { decref_box(handle as RocBox, roc_host()) };
    lease
}

#[cfg(test)]
mod tests {
    use super::*;

    fn release(handle: *mut u64) {
        unsafe { decref_box(handle as RocBox, roc_host()) };
    }

    #[test]
    fn concurrent_reads_and_writes_are_atomic() {
        crate::abi::initialize_test_roc_host();
        let handle = readiness_gates()
            .reserve()
            .unwrap()
            .insert(ReadinessGate::new(false));
        let lease = ReadinessLease::retain(handle).unwrap();
        let address = handle as usize;
        let workers = (0..8)
            .map(|worker| {
                std::thread::spawn(move || {
                    let handle = address as *mut u64;
                    for iteration in 0..10_000 {
                        set_handle(handle, (worker + iteration) % 2 == 0).unwrap();
                        let state = unsafe { gate_ref(handle) }
                            .unwrap()
                            .state
                            .load(Ordering::Acquire);
                        assert!(state == READY || state == NOT_READY);
                    }
                })
            })
            .collect::<Vec<_>>();
        for worker in workers {
            worker.join().unwrap();
        }
        drop(lease);
        release(handle);
    }

    #[test]
    fn drain_is_terminal_and_forces_not_ready() {
        crate::abi::initialize_test_roc_host();
        let handle = readiness_gates()
            .reserve()
            .unwrap()
            .insert(ReadinessGate::new(true));
        let lease = ReadinessLease::retain(handle).unwrap();
        assert!(lease.is_ready());
        lease.begin_stopping();
        assert!(!lease.is_ready());
        assert_eq!(
            set_handle(handle, true),
            Err(ReadinessSetError::ServerStopping)
        );
        drop(lease);
        release(handle);
    }

    #[test]
    fn invalid_and_stale_handles_are_distinct() {
        crate::abi::initialize_test_roc_host();
        assert_eq!(
            set_handle(core::ptr::null_mut(), true),
            Err(ReadinessSetError::InvalidReadiness)
        );
        let handle = readiness_gates()
            .reserve()
            .unwrap()
            .insert(ReadinessGate::new(false));
        release(handle);
        assert_eq!(
            set_handle(handle, true),
            Err(ReadinessSetError::StaleReadiness)
        );
    }
}
