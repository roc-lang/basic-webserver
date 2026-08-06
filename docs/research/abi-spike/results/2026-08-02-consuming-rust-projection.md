# Consuming Rust projection result

Date: 2026-08-02

`basic-webserver` branch: `datastar-experiment`

Roc branch: `datastar-erased-repack-arc`

Roc candidate: `be78e95c42` on top of aggregate-reuse candidate `d4921d8658`

## Question

Can the Rust host consume an owning `Emit { item, machine, wait_millis } | End`
result without bit-copying its owning fields, allocating during projection, or
making it possible for ordinary safe wrapper code to destroy the result shell
and extracted owners twice?

## Candidate boundary

Generated Rust glue now exposes two deliberately raw operations per payload:

- `borrow_payload_*_unchecked(&self) -> &Payload` for non-owning inspection;
- `take_payload_*_unchecked(&mut self) -> Payload` for an ownership move.

The consuming operation is unsafe because the caller must first validate the
tag and must treat the union shell as logically uninitialized afterward. On
32-bit targets it uses `ptr::read` from the aligned byte payload. On native
union targets it uses `ManuallyDrop::take`. Generated recursive decref helpers
consume active payloads through the same primitive; incref helpers borrow and
explicitly read only for the controlled retain operation.

The spike keeps this raw API below four non-`Copy` Rust owners:

- `OwnedSourceStep` whole-drops a still-live result;
- successful `try_take_emit(self)` invalidates that shell and returns
  `OwnedEmit`;
- `OwnedSourceItem` owns exactly one Roc list descriptor;
- `OwnedSourceMachine` owns exactly one erased callable.

A wrong-tag projection returns the still-owned `OwnedSourceStep`. A separate
compile invocation deliberately tries to use an `OwnedSourceStep` after moving
it and must fail with Rust's moved-value diagnostic.

## Evidence

The generated-wrapper lifecycle passes with the matched Roc compiler in both
development and release-speed builds.

The fixture checks all of the following:

- the borrow and take observe the same item allocation and next-machine
  address;
- the dynamic item's Roc refcount is unchanged by projection;
- allocation-call, allocation-byte, and deallocation-call counters do not
  change across projection;
- the release-speed compatible transition returns the old callable allocation
  as the next machine;
- an aliased dynamic item retained by the next machine balances when the item
  is dropped first and when the machine is dropped first;
- a unique changing dynamic item balances in both destruction orders;
- whole-step drop balances an unprojected `Emit` result;
- `End` rejects `try_take_emit`, returns the still-owned shell, and balances on
  drop; and
- opaque captured resources and all Roc allocations return to zero.

The C support allocator now tracks allocation identity as well as counts. An
unknown or already-freed pointer fails before calling `free`, so a balanced
counter cannot conceal an ordinary duplicate free in these lifecycle paths.

Compiler-side validation at `be78e95c42`:

- `zig build run-check-glue-abi` passed;
- the complete CLI glue suite passed 48/48;
- generated C, Zig, and Rust hosts passed their native and Wasm runtime
  matrices; and
- the focused RustGlue source-shape regression requires the borrow/take
  primitives and forbids the former owning `payload_*(&self) -> Payload`
  accessor.

## Conclusion

The Rust consuming-projection feasibility gate passes. The selected semantic
composite result no longer requires a borrowed owning-field copy or a private
one-shot result cell. The generated operations remain unsafe primitives; the
framework must expose only an affine RAII owner around them.

This does not yet prove the production retained-source transaction. The exact
source step still needs `Wait` and `Error` paths, integration with callback,
waiter, byte, frame, encoder, request, and shutdown accounting, and generation-
checked timer wakes. The retained Roc capture also needs an enforceable heap
and opaque-resource budget; counting only host scheduler objects is not a
complete admission proof. C and Zig consuming APIs remain upstream glue
completeness work, but are not required by the Rust `basic-webserver` host
feasibility gate.
