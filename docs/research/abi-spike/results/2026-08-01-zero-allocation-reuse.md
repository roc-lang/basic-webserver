# Zero-allocation retained-callable reuse

This follow-up records compiler feasibility commits `2c54467b8d` and
`f450d1ae25`, based on Roc main
`232552d8bb192c088b759db0b8bc7a4368a5dd61`. Validation also includes
`939c44a07d` (procedure-scoped ARC uniqueness certification) and `4885527bc3`
(restrict hosted `Try` adapters to closed error rows). They close the specific
allocation question identified in
[`2026-08-01-allocation-provenance.md`](2026-08-01-allocation-provenance.md);
this is not yet an upstream Roc change or a production `basic-webserver`
implementation.

## Result

The optimized, uniquely owned, layout-compatible retained-callable transition
now requests **zero calls to the instrumented Roc allocator or deallocator per
step**. After rebasing onto the newer compiler main, one CPU-pinned
five-million-step run at final compiler commit `4885527bc3` produced seven
samples from 1.446–1.461 ns/step, with a 1.460 ns median. The simple
explicit-state control measured 1.453–1.464 ns/step in the same process.

The complete lifecycle still passed:

```text
CORRECTNESS ok observed_calls=55 resource_allocations=8 resource_deallocations=8 max_independent=2
ACCOUNTING allocations=108 deallocations=108 reallocations=0 live=0
```

Those totals include construction, teardown, and the adversarial lifecycle
cases. The measured hot loop itself requested no allocation or deallocation.

## What allocated

Three separate gaps formed the original one-allocation transition:

1. ARC discarded an already-recognized `assign_packed_erased_fn.reuse` operand.
2. An erased callback received only its capture pointer, not ownership of the
   enclosing callable allocation, so a returned continuation could not reuse
   it.
3. The callback tail-called a finite recursive constructor. Even after adding
   a reuse destination to the erased call, that destination stopped at the
   direct-call boundary and the constructor allocated.

The third gap is why merely preserving the existing local repack marker did not
change the benchmark.

## Prototype mechanism

The prototype treats continuation replacement as an owned update:

- An erased callable invocation has a hidden optional `reuse` destination in
  addition to its ordinary capture pointer.
- `assign_call_erased` records both the callable used for dispatch and the
  outer local whose ownership is consumed. This distinction matters when a
  callable is wrapped in transparent nominal or single-tag values.
- Whole-procedure alias resolution traces the dispatch pointer back to that
  owned outer source. ARC transfers its ownership unit into the call, retaining
  it first only when the source remains live afterward.
- Private finite-procedure variants carry the destination through return-
  position direct calls. Variants are keyed by the old capture type, so
  recursive and mutually recursive specialization is finite and
  size/alignment compatibility is checked before repacking.
- Return-flow analysis crosses aliases, transparent tags, and the joins emitted
  by `if` and `match`. Hosted functions are never given this private ABI.
- A compatible terminal erased pack consumes the destination. An incompatible
  or ordinary return path leaves ARC responsible for releasing it exactly
  once.

The development, interpreter, LLVM, and Wasm call paths all implement the
extended convention. C, Rust, and Zig glue expose the corresponding fifth
argument. This is an intentional source/ABI break for hosts that invoke erased
callables directly: generated glue and the host must be rebuilt together, and
ordinary host calls pass null. A non-null destination is a consumed callable
ownership unit whether it is reused in place or released on the shared/fallback
path.

## LLVM hot-path follow-up

Passing ownership removed allocation but initially measured about 5.06 ns per
step because LLVM always called the external
`erased_callable_repack` runtime helper. ARC could prove consumption, but not
that a host-provided allocation had no aliases, so the helper still performed a
runtime refcount test.

The final prototype emits that fast path inline:

1. materialize the new capture before mutating the old allocation;
2. use an ARC-proven unique destination directly, or test its target-width
   refcount;
3. on the runtime-unique path, invoke the old dynamic `on_drop` callback if
   present, then rewrite the header and capture;
4. on the shared path, call the existing immutable repack helper, which
   allocates a replacement and consumes one reference to the old value.

The optimized `U64` continuation now contains no hot call to the repack helper
and no `memcpy`; the cold shared edge retains the existing helper. This reduced
the representative median from about 5.06 ns to about 1.46 ns. Code inspection
preserves the copy-on-share path and dynamic drop callback, but dedicated
shared host-authored and mixed-layout runtime regressions remain before that
claim is production evidence.

## Go comparison

The Go 1.26.5 fixture reports two deliberately different contracts. A fresh
CPU-pinned run measured 9.558–12.228 ns for the functional fixture (9.563 ns
median) and 1.086–1.403 ns for the mutable fixture (1.090 ns median). The slow
early samples show that CPU affinity alone did not control warmup or frequency,
so these nanosecond timings choose cost classes, not acceptance margins.

| Machine | Median ns/step | Allocations/step | Meaning |
| --- | ---: | ---: | --- |
| Roc retained callable | 1.460 | 0 | Immutable callable API; unique compatible benchmark path |
| Go functional closure | 9.563 | 1 | Closest source shape: return a newly captured continuation |
| Go reused machine | 1.090 | 0 | Aggressive mutable-pointer reference with indirect dispatch |

The Roc prototype is in the same no-allocation cost class as the aggressive
mutable Go reference and is faster than the closest functional source-shape
fixture in these runs. The mutable reference is not a lower bound and is not
semantically equivalent: it assumes exclusive mutation and has no shared-value
copy fallback. We therefore consider the allocation feasibility hypothesis
supported. Controlled repeated-process measurements and end-to-end Datastar
latency and throughput—not this nanobenchmark—remain the performance gate.

## Correctness and regression coverage

The prototype adds or exercises:

- a source-driven same-layout, refcounted-capture transition on interpreter,
  development, Wasm, and LLVM;
- an allocation budget proving the returned callable reuses storage;
- runtime unique/shared repack and old-capture destruction;
- ARC transfer for a dead source and retain-before-transfer for a source used
  later;
- consistency certification for the reuse flag and ownership source;
- direct recursive propagation through generated return joins;
- exact C, Rust, and Zig callable signatures;
- Win64's stack-passed fifth argument;
- LLVM explicit-versus-hidden argument accounting; and
- the full generated-wrapper lifecycle fixture, including cancellation,
  thread migration, independent concurrency, nested ARC captures, and opaque
  resources.

Before the rebase, the callable commits passed focused postcheck, LIR, backend,
LLVM, glue ABI, fx-platform, and four-backend eval suites; Roc MiniCI ran all 74
phases successfully. After rebasing the clean commits onto `232552d8bb`, the
check-module unit suite passed, the optimized lifecycle reproduced zero hot
allocator/deallocator calls, and `python3 scripts/test.py` passed all 52
basic-webserver runtime cases. The full basic-webserver run also exposed two
pre-existing recent-main compiler regressions: procedure-global ARC uniqueness
certification and hosted `Try` adaptation of record errors. Commits `939c44a07d`
and `4885527bc3` isolate those fixes. This validation does not establish
cross-target runtime or sanitizer coverage.

Development mode still reports one allocation and free per step and is not the
optimized performance result. Its lifecycle accounting and behavior pass, but
the allocation claim here is only about the release-speed hot path;
development remains a semantic/debugging backend.

## SSE and Brotli consequence

The preferred application API no longer needs an explicit central
`StreamState` union merely to avoid allocator cost. A private retained Roc
machine can offer immutable continuation ergonomics while the compiler reuses
its uniquely held storage underneath.

Brotli remains host-owned transport state, not part of the Roc continuation.
The host parks one Roc machine and one admitted encoder per connection, invokes
one bounded Roc step at a time, frames the returned events, feeds them into the
retained Brotli encoder, and FLUSHes after every logical event or heartbeat.
Normal close FINISHes the encoder; cancellation abandons it. Removing the
measured Roc transition allocation makes it plausible to compose with Brotli's
independently measured zero-steady-system-allocation profiles. Framing, owned
body frames, queueing, and the repeated-FLUSH bound still need a composed
transport measurement.

## Remaining gates

Before treating this as supported compiler/platform behavior:

- turn the research branch into an upstream-quality Roc proposal and decide
  whether the five-argument host-visible callable ABI is the desired stable
  contract or should be hidden behind generated adapters;
- complete cross-target execution and sanitizer/native memory-instrumentation
  coverage;
- add shared host-authored callable and mixed compatible/incompatible capture
  regressions;
- integrate the machine with `basic-webserver`'s real bounded body,
  cancellation, deadlines, and HTTP/1.1/HTTP/2 accounting; and
- pass the end-to-end Datastar plus Brotli latency, throughput, memory, slow-
  reader, and browser matrix.
