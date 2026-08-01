# Retained callable ABI spike

This disposable fixture attempts to exercise the precise lifecycle proposed
for a Roc SSE stream machine. It is research evidence, not platform
implementation.

Run the complete lifecycle through generated provided wrappers in both
backends:

```sh
python3 scripts/spike_retained_callable.py --opt all --iterations 1000 \
  --mode wrapper
```

Run the development-only direct erased-callable diagnostic:

```sh
python3 scripts/spike_retained_callable.py --opt dev --iterations 100000 \
  --mode diagnostic
```

The generated glue, host archive, target links, and executables are written
under ignored `build/` or `platform/targets/` paths. The script uses the Roc
compiler from `PATH` and finds its matching source checkout for `CGlue.roc`.
Set `ROC_SRC` when auto-discovery is not appropriate.

Roc main commit `1c1ceccf672248bcd367cf3b21f4daadc0afd318`, which contains
the merged callable-boundary fix in `206f4c30b68ee6d02e1972828ee7b481ac8f23be`,
passes the generated-wrapper lifecycle in development and optimized builds.
The former minimal failure, consuming a non-recursive captured
`Box(U64 -> U64)`, now returns and restores the live-allocation count to zero.
Generated recursive make, advance, and drop wrappers also pass parked and
returned drops, sequential worker-thread migration, independent concurrency,
same-machine overlap rejection, in-flight cancellation, nested capture
teardown, and opaque-resource balance.

The development-only direct erased-callable helper remains available as a
diagnostic comparison, but the supported result no longer depends on it.

This clears the local callable correctness blocker; it does not select the
callable representation as the final hot-step design. A seven-sample,
CPU-pinned million-step optimized run measured a median 109.968 ns/step and
allocated/freed once per immutable callable continuation step. Allocator-ledger
atomics perturb that allocation-heavy timing, so it diagnoses the cost class
rather than satisfying the controlled Go gate. The benchmark's simple pure
explicit-state comparison was optimized to zero allocations, while the
separate representative explicit-state fixture still measures one replacement
allocation per transition. Cross-target and native memory-instrumentation
coverage remain open. The exact validation record is in
[`results/2026-08-01-main.md`](results/2026-08-01-main.md).
The allocating procedures, compiler reuse boundary, adjacent ARC regression,
and two elimination hypotheses are recorded in
[`results/2026-08-01-allocation-provenance.md`](results/2026-08-01-allocation-provenance.md).

The benchmark is not an end-to-end SSE or Go comparison. Its allocation
counters use atomics in the allocator and therefore perturb allocation-heavy
timings. It exists to choose the next design spike and to detect large ABI or
allocation regressions.
