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

Build and run the matched Go reference separately with an explicit Go 1.26.5
executable. The version check deliberately fails instead of silently using a
different `go` from `PATH`:

```sh
GO_BIN=/path/to/go1.26.5/bin/go
test "$("$GO_BIN" version)" = "go version go1.26.5 linux/amd64"
"$GO_BIN" build -o build/abi-spike/go-reference \
  docs/research/abi-spike/go-reference.go
taskset -c 2 env ABI_SPIKE_ITERS=5000000 \
  build/abi-spike/go-reference
```

The initial lifecycle result used Roc main commit
`1c1ceccf672248bcd367cf3b21f4daadc0afd318`. That compiler contains the merged
callable-boundary fix in `206f4c30b68ee6d02e1972828ee7b481ac8f23be`
and passes the generated-wrapper lifecycle in development and optimized builds.
The former minimal failure, consuming a non-recursive captured
`Box(U64 -> U64)`, now returns and restores the live-allocation count to zero.
Generated recursive make, advance, and drop wrappers also pass parked and
returned drops, sequential worker-thread migration, independent concurrency,
same-machine overlap rejection, in-flight cancellation, nested capture
teardown, and opaque-resource balance.

The development-only direct erased-callable helper remains available as a
diagnostic comparison, but the supported result no longer depends on it.

That compiler baseline clears the local callable correctness blocker. A
follow-up compiler prototype on Roc main `9b601b5dac` also transfers the old
callable allocation through the erased call and recursive constructor, then
inlines LLVM's runtime-unique repack path. A CPU-pinned five-million-step speed
run measures a representative 1.46 ns median with zero calls to the
instrumented Roc allocator or deallocator in the unique compatible path. The
closest functional Go source-shape fixture allocates once per step; an
aggressive mutable-pointer Go reference does not allocate and is slightly
faster in this nanobenchmark. Cross-target, controlled repeated-process timing,
and native memory-instrumentation coverage remain open. The baseline validation
record is in
[`results/2026-08-01-main.md`](results/2026-08-01-main.md).
The allocating procedures, compiler reuse boundary, adjacent ARC regression,
and two elimination hypotheses are recorded in
[`results/2026-08-01-allocation-provenance.md`](results/2026-08-01-allocation-provenance.md).
The ownership propagation, backend fixes, zero-allocation result, and matched
Go comparison are in
[`results/2026-08-01-zero-allocation-reuse.md`](results/2026-08-01-zero-allocation-reuse.md).

The benchmark is not an end-to-end SSE or Go comparison. Its allocation
counters use atomics in the allocator and therefore perturb allocation-heavy
timings. It exists to choose the next design spike and to detect large ABI or
allocation regressions.
