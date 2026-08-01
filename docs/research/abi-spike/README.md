# Retained callable ABI spike

This disposable fixture attempts to exercise the precise lifecycle proposed
for a Roc SSE stream machine. It is research evidence, not platform
implementation.

Run both the development and optimized backends:

```sh
python scripts/spike_retained_callable.py --opt all --iterations 1000000
```

The generated glue, host archive, target links, and executables are written
under ignored `build/` or `platform/targets/` paths. The script uses the Roc
compiler from `PATH` and finds its matching source checkout for `CGlue.roc`.
Set `ROC_SRC` when auto-discovery is not appropriate.

The current checkpoint is an intentionally preserved negative reproducer. Both
the development and optimized binaries segfault when a machine returned from a
provided entrypoint is consumed by the generated drop wrapper. The same failure
has been reproduced with a pure recursive callable containing only a `U64`
capture and with the explicit `Box(State)` path. The first failing scenario is
same-thread parked drop, before the migration/concurrency scenarios run. That
does not yet distinguish a compiler defect from a fixture ABI defect.

Once the drop path is reduced, the remaining scenarios cover sequential thread
migration, concurrent independent machines, host-side same-machine overlap
rejection, discard of a returned next machine, cancellation during an in-flight
advance, nested capture teardown, and an opaque boxed resource. The diagnostic
benchmark compares recursive boxed-callable reconstruction with the explicit
`stream!`-style `Box(State)` fallback and records crossing time plus allocation
counts.

The benchmark is not an end-to-end SSE or Go comparison. Its allocation
counters use atomics in the allocator and therefore perturb allocation-heavy
timings. It exists to choose the next design spike and to detect large ABI or
allocation regressions.
