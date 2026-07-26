use core::cell::UnsafeCell;
use core::ffi::c_void;
use core::mem::{offset_of, MaybeUninit};
use core::sync::atomic::{AtomicIsize, Ordering};
use std::sync::Mutex;

const TOKEN_INDEX_BITS: u32 = 16;
const TOKEN_INDEX_MASK: u64 = (1_u64 << TOKEN_INDEX_BITS) - 1;
const MAX_GENERATION: u64 = u64::MAX >> TOKEN_INDEX_BITS;
const DEBUG_FREED_REFCOUNT: isize = 0xDEADBEEFDEADBEEFu64 as isize;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ReserveError {
    Capacity,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum LookupError {
    Invalid,
    Stale,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum DeallocRoute {
    NotOwned,
    Deallocated,
    Corrupt,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SlotState {
    Free,
    Reserved,
    Live,
    Closing,
    Retired,
}

#[repr(C)]
struct ResourceSlot<T> {
    // Roc's Box(U64) representation is exactly one atomic refcount word
    // followed by the U64 payload pointer returned to Roc.
    refcount: AtomicIsize,
    token: UnsafeCell<u64>,
    resource: UnsafeCell<MaybeUninit<T>>,
}

struct HeapState {
    free: Vec<usize>,
    generations: Vec<u64>,
    slots: Vec<SlotState>,
    active: usize,
    high_water: usize,
}

/// A finite host-owned heap whose allocation prefix is ABI-compatible with
/// Roc's `Box(U64)`.
///
/// Roc owns and copies only the opaque box pointer. The native value remains in
/// a stable host slot and is dropped when Roc's final ARC release routes the
/// box allocation through [`route_dealloc`].
pub(crate) struct HostResourceHeap<T> {
    slots: Box<[ResourceSlot<T>]>,
    state: Mutex<HeapState>,
}

// Access to slot state and initialization is serialized by `state`. A live
// resource may be accessed without holding that lock only while the caller owns
// a live Roc reference; resource-specific synchronization remains inside `T`.
unsafe impl<T: Send> Send for HostResourceHeap<T> {}
unsafe impl<T: Send + Sync> Sync for HostResourceHeap<T> {}

impl<T> HostResourceHeap<T> {
    pub(crate) fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "host resource heap capacity must be non-zero");
        assert!(
            capacity <= TOKEN_INDEX_MASK as usize,
            "host resource heap capacity exceeds token index space"
        );
        assert_eq!(
            offset_of!(ResourceSlot<T>, token),
            core::mem::size_of::<isize>(),
            "resource handle payload must immediately follow Roc's refcount"
        );

        let slots = (0..capacity)
            .map(|_| ResourceSlot {
                refcount: AtomicIsize::new(0),
                token: UnsafeCell::new(0),
                resource: UnsafeCell::new(MaybeUninit::uninit()),
            })
            .collect::<Vec<_>>()
            .into_boxed_slice();
        let free = (0..capacity).rev().collect();
        Self {
            slots,
            state: Mutex::new(HeapState {
                free,
                generations: vec![0; capacity],
                slots: vec![SlotState::Free; capacity],
                active: 0,
                high_water: 0,
            }),
        }
    }

    pub(crate) fn reserve(&self) -> Result<ResourceReservation<'_, T>, ReserveError> {
        let mut state = self.lock_state();
        while let Some(index) = state.free.pop() {
            let generation = state.generations[index].saturating_add(1);
            if generation == 0 || generation > MAX_GENERATION {
                state.slots[index] = SlotState::Retired;
                continue;
            }
            state.generations[index] = generation;
            state.slots[index] = SlotState::Reserved;
            state.active += 1;
            state.high_water = state.high_water.max(state.active);
            return Ok(ResourceReservation {
                heap: self,
                index,
                generation,
                committed: false,
            });
        }
        Err(ReserveError::Capacity)
    }

    /// Resolve a live Roc handle to its host-owned resource.
    ///
    /// # Safety
    /// The caller must own a live Roc reference to `handle` for the full
    /// lifetime of the returned reference. That prevents final ARC deallocation
    /// and slot reuse while the resource is borrowed.
    pub(crate) unsafe fn get(&self, handle: *mut u64) -> Result<&T, LookupError> {
        let index = self.payload_index(handle).ok_or(LookupError::Invalid)?;
        let slot = &self.slots[index];
        if slot.refcount.load(Ordering::Acquire) <= 0 {
            return Err(LookupError::Stale);
        }
        let token = unsafe { *slot.token.get() };
        let (token_index, generation) = decode_token(token).ok_or(LookupError::Stale)?;
        let state = self.lock_state();
        if token_index != index
            || state.slots[index] != SlotState::Live
            || state.generations[index] != generation
        {
            return Err(LookupError::Stale);
        }
        drop(state);
        Ok(unsafe { (&*slot.resource.get()).assume_init_ref() })
    }

    /// Route a Roc allocation-base pointer to this heap.
    pub(crate) fn route_dealloc(&self, ptr: *mut c_void) -> DeallocRoute {
        let Some(index) = self.base_index(ptr) else {
            return if self.contains_address(ptr) {
                DeallocRoute::Corrupt
            } else {
                DeallocRoute::NotOwned
            };
        };
        let slot = &self.slots[index];
        let mut state = self.lock_state();
        let refcount = slot.refcount.load(Ordering::Acquire);
        // Roc's debug runtime poisons the final refcount immediately before it
        // invokes the host deallocator. Optimized runtimes leave it at zero.
        // Slot state still makes a second deallocation unambiguously corrupt.
        if state.slots[index] != SlotState::Live
            || (refcount != 0 && refcount != DEBUG_FREED_REFCOUNT)
        {
            eprintln!(
                "host resource deallocation invariant failed: index={index}, state={:?}, refcount={}",
                state.slots[index], refcount
            );
            return DeallocRoute::Corrupt;
        }
        let token = unsafe { *slot.token.get() };
        let Some((token_index, generation)) = decode_token(token) else {
            return DeallocRoute::Corrupt;
        };
        if token_index != index || state.generations[index] != generation {
            return DeallocRoute::Corrupt;
        }

        let resource = unsafe { (&*slot.resource.get()).assume_init_read() };
        state.slots[index] = SlotState::Closing;
        drop(state);

        // Native teardown may block. Keep this slot active and unavailable for
        // reuse until teardown is complete, but do not serialize unrelated
        // heap operations behind it.
        drop(resource);

        let mut state = self.lock_state();
        assert_eq!(state.slots[index], SlotState::Closing);
        assert_eq!(state.generations[index], generation);
        state.slots[index] = SlotState::Free;
        state.active -= 1;
        state.free.push(index);
        DeallocRoute::Deallocated
    }

    pub(crate) fn contains_address(&self, ptr: *const c_void) -> bool {
        let address = ptr as usize;
        let start = self.slots.as_ptr() as usize;
        let end = start + core::mem::size_of_val(&*self.slots);
        start <= address && address < end
    }

    pub(crate) fn active(&self) -> usize {
        self.lock_state().active
    }

    pub(crate) fn high_water(&self) -> usize {
        self.lock_state().high_water
    }

    fn commit(&self, index: usize, generation: u64, resource: T) -> *mut u64 {
        let slot = &self.slots[index];
        let token = encode_token(index, generation);
        let mut state = self.lock_state();
        assert_eq!(state.slots[index], SlotState::Reserved);
        assert_eq!(state.generations[index], generation);
        unsafe {
            (*slot.resource.get()).write(resource);
            *slot.token.get() = token;
        }
        state.slots[index] = SlotState::Live;
        slot.refcount.store(1, Ordering::Release);
        slot.token.get()
    }

    fn cancel_reservation(&self, index: usize, generation: u64) {
        let mut state = self.lock_state();
        if state.slots[index] == SlotState::Reserved && state.generations[index] == generation {
            state.slots[index] = SlotState::Free;
            state.active -= 1;
            state.free.push(index);
        }
    }

    fn payload_index(&self, handle: *mut u64) -> Option<usize> {
        if handle.is_null() {
            return None;
        }
        let token_offset = offset_of!(ResourceSlot<T>, token);
        let base = (handle as usize).checked_sub(token_offset)?;
        self.index_for_base(base)
            .filter(|&index| self.slots[index].token.get() == handle)
    }

    fn base_index(&self, ptr: *mut c_void) -> Option<usize> {
        self.index_for_base(ptr as usize)
    }

    fn index_for_base(&self, address: usize) -> Option<usize> {
        let start = self.slots.as_ptr() as usize;
        let offset = address.checked_sub(start)?;
        let stride = core::mem::size_of::<ResourceSlot<T>>();
        if offset % stride != 0 {
            return None;
        }
        let index = offset / stride;
        (index < self.slots.len()).then_some(index)
    }

    fn lock_state(&self) -> std::sync::MutexGuard<'_, HeapState> {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

impl<T> Drop for HostResourceHeap<T> {
    fn drop(&mut self) {
        let state = self
            .state
            .get_mut()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        for (index, slot_state) in state.slots.iter_mut().enumerate() {
            if *slot_state == SlotState::Live {
                unsafe {
                    (&mut *self.slots[index].resource.get()).assume_init_drop();
                }
                *slot_state = SlotState::Free;
            }
        }
    }
}

pub(crate) struct ResourceReservation<'a, T> {
    heap: &'a HostResourceHeap<T>,
    index: usize,
    generation: u64,
    committed: bool,
}

impl<T> ResourceReservation<'_, T> {
    pub(crate) fn insert(mut self, resource: T) -> *mut u64 {
        let handle = self.heap.commit(self.index, self.generation, resource);
        self.committed = true;
        handle
    }
}

impl<T> Drop for ResourceReservation<'_, T> {
    fn drop(&mut self) {
        if !self.committed {
            self.heap.cancel_reservation(self.index, self.generation);
        }
    }
}

fn encode_token(index: usize, generation: u64) -> u64 {
    (generation << TOKEN_INDEX_BITS) | (index as u64 + 1)
}

fn decode_token(token: u64) -> Option<(usize, u64)> {
    let encoded_index = token & TOKEN_INDEX_MASK;
    let generation = token >> TOKEN_INDEX_BITS;
    if encoded_index == 0 || generation == 0 {
        None
    } else {
        Some((encoded_index as usize - 1, generation))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::roc_platform_abi::{decref_box, incref_box, make_roc_host, RocBox, RocHost};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Condvar};

    struct CountDrop(Arc<AtomicUsize>, usize);

    impl Drop for CountDrop {
        fn drop(&mut self) {
            self.0.fetch_add(self.1, Ordering::AcqRel);
        }
    }

    struct BlockingDrop {
        control: Arc<(Mutex<(bool, bool)>, Condvar)>,
    }

    impl Drop for BlockingDrop {
        fn drop(&mut self) {
            let (lock, changed) = &*self.control;
            let mut state = lock.lock().unwrap();
            state.0 = true;
            changed.notify_all();
            while !state.1 {
                state = changed.wait(state).unwrap();
            }
        }
    }

    extern "C" fn route_usize_heap_dealloc(
        roc_host: *mut RocHost,
        ptr: *mut c_void,
        _alignment: usize,
    ) {
        let heap = unsafe { &*((*roc_host).env.cast::<HostResourceHeap<usize>>()) };
        if heap.route_dealloc(ptr) != DeallocRoute::Deallocated {
            std::process::abort();
        }
    }

    fn release<T>(heap: &HostResourceHeap<T>, handle: *mut u64) -> Option<DeallocRoute> {
        let base = unsafe { handle.cast::<u8>().sub(core::mem::size_of::<isize>()) };
        let previous = unsafe { (*(base.cast::<AtomicIsize>())).fetch_sub(1, Ordering::Release) };
        assert!(previous > 0, "test released an invalid Roc reference");
        if previous == 1 {
            core::sync::atomic::fence(Ordering::Acquire);
            Some(heap.route_dealloc(base.cast()))
        } else {
            None
        }
    }

    fn final_dealloc<T>(heap: &HostResourceHeap<T>, handle: *mut u64) -> DeallocRoute {
        release(heap, handle).expect("test expected the final Roc reference")
    }

    #[test]
    fn capacity_is_finite_and_final_dealloc_reuses_a_slot() {
        let drops = Arc::new(AtomicUsize::new(0));
        let heap = HostResourceHeap::new(2);
        let first = heap
            .reserve()
            .unwrap()
            .insert(CountDrop(Arc::clone(&drops), 1));
        let second = heap
            .reserve()
            .unwrap()
            .insert(CountDrop(Arc::clone(&drops), 10));
        assert_eq!(heap.reserve().err(), Some(ReserveError::Capacity));
        assert_eq!(heap.active(), 2);
        assert_eq!(heap.high_water(), 2);

        assert_eq!(final_dealloc(&heap, first), DeallocRoute::Deallocated);
        assert_eq!(drops.load(Ordering::Acquire), 1);
        let replacement = heap
            .reserve()
            .unwrap()
            .insert(CountDrop(Arc::clone(&drops), 100));
        assert_eq!(
            replacement, first,
            "the bounded heap should reuse free slots"
        );

        assert_eq!(final_dealloc(&heap, second), DeallocRoute::Deallocated);
        assert_eq!(final_dealloc(&heap, replacement), DeallocRoute::Deallocated);
        assert_eq!(drops.load(Ordering::Acquire), 111);
        assert_eq!(heap.active(), 0);
    }

    #[test]
    fn dropped_reservations_return_capacity() {
        let heap = HostResourceHeap::<usize>::new(1);
        drop(heap.reserve().unwrap());
        let handle = heap.reserve().unwrap().insert(42);
        assert_eq!(unsafe { *heap.get(handle).unwrap() }, 42);
        assert_eq!(final_dealloc(&heap, handle), DeallocRoute::Deallocated);
    }

    #[test]
    fn debug_runtime_refcount_poison_is_a_valid_final_deallocation() {
        let heap = HostResourceHeap::<usize>::new(1);
        let handle = heap.reserve().unwrap().insert(42);
        let base = unsafe { handle.cast::<u8>().sub(core::mem::size_of::<isize>()) };
        unsafe {
            (*(base.cast::<AtomicIsize>())).store(DEBUG_FREED_REFCOUNT, Ordering::Release);
        }

        assert_eq!(heap.route_dealloc(base.cast()), DeallocRoute::Deallocated);
        assert_eq!(
            heap.route_dealloc(base.cast()),
            DeallocRoute::Corrupt,
            "slot state must still reject a duplicate debug deallocation"
        );
    }

    #[test]
    fn an_arc_alias_pins_the_slot_until_final_release() {
        let heap = HostResourceHeap::<usize>::new(1);
        let handle = heap.reserve().unwrap().insert(42);
        let mut roc_host =
            make_roc_host((&heap as *const HostResourceHeap<usize>).cast_mut().cast());
        roc_host.roc_dealloc = route_usize_heap_dealloc;
        // SAFETY: `handle` owns one live Roc Box reference, and both references
        // are balanced by `decref_box` below.
        unsafe {
            incref_box(handle as RocBox, 1);
            decref_box(handle as RocBox, &roc_host);
        }

        assert_eq!(unsafe { *heap.get(handle).unwrap() }, 42);
        assert_eq!(heap.reserve().err(), Some(ReserveError::Capacity));
        // SAFETY: this consumes the remaining owned Roc Box reference.
        unsafe { decref_box(handle as RocBox, &roc_host) };

        let replacement = heap.reserve().unwrap().insert(7);
        assert_eq!(replacement, handle);
        assert_eq!(final_dealloc(&heap, replacement), DeallocRoute::Deallocated);
    }

    #[test]
    fn capacity_remains_occupied_until_native_drop_finishes() {
        let control = Arc::new((Mutex::new((false, false)), Condvar::new()));
        let heap = Arc::new(HostResourceHeap::new(1));
        let handle = heap.reserve().unwrap().insert(BlockingDrop {
            control: Arc::clone(&control),
        });
        let base = unsafe { handle.cast::<u8>().sub(core::mem::size_of::<isize>()) } as usize;
        unsafe {
            (*(base as *mut AtomicIsize)).store(0, Ordering::Release);
        }

        let dealloc_heap = Arc::clone(&heap);
        let dealloc = std::thread::spawn(move || dealloc_heap.route_dealloc(base as *mut c_void));

        let (lock, changed) = &*control;
        let mut state = lock.lock().unwrap();
        while !state.0 {
            state = changed.wait(state).unwrap();
        }
        assert_eq!(heap.active(), 1);
        assert_eq!(heap.reserve().err(), Some(ReserveError::Capacity));
        state.1 = true;
        changed.notify_all();
        drop(state);

        assert_eq!(dealloc.join().unwrap(), DeallocRoute::Deallocated);
        assert_eq!(heap.active(), 0);
        drop(heap.reserve().unwrap());
    }

    #[test]
    fn lookup_rejects_foreign_and_finally_released_handles() {
        let heap = HostResourceHeap::<usize>::new(1);
        let handle = heap.reserve().unwrap().insert(42);
        assert_eq!(unsafe { *heap.get(handle).unwrap() }, 42);
        let mut foreign = 0_u64;
        assert_eq!(
            unsafe { heap.get(&mut foreign) }.err(),
            Some(LookupError::Invalid)
        );

        assert_eq!(final_dealloc(&heap, handle), DeallocRoute::Deallocated);
        assert_eq!(unsafe { heap.get(handle) }.err(), Some(LookupError::Stale));
        assert_eq!(heap.route_dealloc(handle.cast()), DeallocRoute::Corrupt);
    }
}
