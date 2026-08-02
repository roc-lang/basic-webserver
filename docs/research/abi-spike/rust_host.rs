#![no_std]

#[path = "../../../build/abi-spike/glue-rust/roc_platform_abi.rs"]
mod abi;

use core::mem::MaybeUninit;
use core::panic::PanicInfo;
use core::sync::atomic::{AtomicIsize, Ordering};

unsafe extern "C" {
    fn abi_spike_allocation_calls() -> u64;
    fn abi_spike_allocation_bytes() -> u64;
    fn abi_spike_deallocation_calls() -> u64;
    fn abi_spike_expect_reuse() -> bool;
    fn abi_spike_live_allocations() -> i64;
    fn abort() -> !;
}

fn check(condition: bool) {
    if !condition {
        unsafe { abort() }
    }
}

fn some_or_abort<T>(value: Option<T>) -> T {
    match value {
        Some(value) => value,
        None => unsafe { abort() },
    }
}

fn some_ref_or_abort<T>(value: &Option<T>) -> &T {
    match value {
        Some(value) => value,
        None => unsafe { abort() },
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    unsafe { abort() }
}

struct OwnedSourceMachine(Option<abi::RocErasedCallable>);

impl OwnedSourceMachine {
    fn new(events: u64) -> Self {
        Self(Some(unsafe { abi::roc_abi_make_source_machine(events) }))
    }

    fn aliased(events: u64) -> Self {
        Self(Some(unsafe {
            abi::roc_abi_make_aliased_source_machine(events)
        }))
    }

    fn unique(events: u64) -> Self {
        Self(Some(unsafe {
            abi::roc_abi_make_unique_source_machine(events)
        }))
    }

    fn address(&self) -> usize {
        *some_ref_or_abort(&self.0) as usize
    }

    fn advance(mut self, wake: u64) -> OwnedSourceStep {
        let machine = some_or_abort(self.0.take());
        OwnedSourceStep::new(unsafe { abi::roc_abi_advance_source_machine(machine, wake) })
    }
}

impl Drop for OwnedSourceMachine {
    fn drop(&mut self) {
        if let Some(machine) = self.0.take() {
            unsafe { abi::roc_abi_drop_source_machine(machine) }
        }
    }
}

struct OwnedSourceItem(Option<abi::RocListWith<u8, false>>);

impl Drop for OwnedSourceItem {
    fn drop(&mut self) {
        if let Some(item) = self.0.take() {
            unsafe { abi::roc_abi_drop_source_item(item) }
        }
    }
}

fn item_refcount(item: &abi::RocListWith<u8, false>) -> isize {
    if item.elements.is_null() {
        return 0;
    }
    let allocation = if item.capacity_or_alloc_ptr & 1 == 1 {
        (item.capacity_or_alloc_ptr & !1) as *const u8
    } else {
        item.elements.cast_const()
    };
    let refcount = unsafe { allocation.cast::<AtomicIsize>().sub(1).as_ref() };
    some_ref_or_abort(&refcount).load(Ordering::Acquire)
}

struct OwnedEmit {
    item: OwnedSourceItem,
    machine: OwnedSourceMachine,
    wait_millis: u64,
}

struct OwnedSourceStep {
    raw: MaybeUninit<abi::AbiSourceStep>,
    live: bool,
}

#[cfg(prove_non_copy)]
fn affine_step_must_not_compile(step: OwnedSourceStep) {
    let moved = step;
    core::mem::forget(moved);
    core::mem::forget(step);
}

impl OwnedSourceStep {
    fn new(raw: abi::AbiSourceStep) -> Self {
        Self {
            raw: MaybeUninit::new(raw),
            live: true,
        }
    }

    fn tag(&self) -> abi::AbiSourceStepTag {
        unsafe { self.raw.assume_init_ref().tag }
    }

    fn try_take_emit(mut self) -> Result<OwnedEmit, Self> {
        if self.tag() != abi::AbiSourceStepTag::Emit {
            return Err(self);
        }

        let raw = unsafe { self.raw.assume_init_mut() };
        let payload = unsafe { raw.take_payload_emit_unchecked() };
        self.live = false;
        Ok(OwnedEmit {
            item: OwnedSourceItem(Some(payload.item)),
            machine: OwnedSourceMachine(Some(payload.machine)),
            wait_millis: payload.wait_millis,
        })
    }
}

impl Drop for OwnedSourceStep {
    fn drop(&mut self) {
        if self.live {
            let raw = unsafe { self.raw.assume_init_read() };
            self.live = false;
            unsafe { abi::roc_abi_drop_source_step(raw) }
        }
    }
}

fn project(machine: OwnedSourceMachine, wake: u64, expected_wait: u64) -> OwnedEmit {
    let input_address = machine.address();
    let step = machine.advance(wake);
    check(step.tag() == abi::AbiSourceStepTag::Emit);

    let borrowed = unsafe {
        step.raw
            .assume_init_ref()
            .borrow_payload_emit_unchecked()
    };
    let borrowed_item_address = borrowed.item.elements as usize;
    let borrowed_item_refcount = item_refcount(&borrowed.item);
    let borrowed_machine_address = borrowed.machine as usize;
    if unsafe { abi_spike_expect_reuse() } {
        check(input_address == borrowed_machine_address);
    }

    let allocations_before = unsafe { abi_spike_allocation_calls() };
    let bytes_before = unsafe { abi_spike_allocation_bytes() };
    let deallocations_before = unsafe { abi_spike_deallocation_calls() };
    let emit = match step.try_take_emit() {
        Ok(emit) => emit,
        Err(_) => unsafe { abort() },
    };
    check(some_ref_or_abort(&emit.item.0).elements as usize == borrowed_item_address);
    check(item_refcount(some_ref_or_abort(&emit.item.0)) == borrowed_item_refcount);
    check(emit.machine.address() == borrowed_machine_address);
    check(emit.wait_millis == expected_wait);
    check(unsafe { abi_spike_allocation_calls() } == allocations_before);
    check(unsafe { abi_spike_allocation_bytes() } == bytes_before);
    check(unsafe { abi_spike_deallocation_calls() } == deallocations_before);

    emit
}

fn projection_is_a_move() {
    let emit = project(OwnedSourceMachine::new(2), 3, 0);
    drop(emit.item);
    drop(emit.machine);
}

fn dynamic_item_drop_orders_balance() {
    let emit = project(OwnedSourceMachine::aliased(1), 7, 0);
    check(item_refcount(some_ref_or_abort(&emit.item.0)) > 0);
    drop(emit.item);
    drop(emit.machine);

    let emit = project(OwnedSourceMachine::aliased(1), 7, 0);
    drop(emit.machine);
    drop(emit.item);

    let emit = project(OwnedSourceMachine::unique(1), 7, 0);
    check(item_refcount(some_ref_or_abort(&emit.item.0)) > 0);
    drop(emit.item);
    drop(emit.machine);

    let emit = project(OwnedSourceMachine::unique(1), 7, 0);
    drop(emit.machine);
    drop(emit.item);
}

fn whole_step_and_wrong_tag_balance() {
    drop(OwnedSourceMachine::new(1).advance(0));

    let end = OwnedSourceMachine::new(0).advance(0);
    check(end.tag() == abi::AbiSourceStepTag::End);
    let end = match end.try_take_emit() {
        Ok(_) => unsafe { abort() },
        Err(still_owned) => still_owned,
    };
    drop(end);
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    projection_is_a_move();
    dynamic_item_drop_orders_balance();
    whole_step_and_wrong_tag_balance();
    check(unsafe { abi_spike_live_allocations() } == 0);
    0
}
