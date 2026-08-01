# Retained callable ABI spike

This disposable fixture attempts to exercise the precise lifecycle proposed
for a Roc SSE stream machine. It is research evidence, not platform
implementation.

Reproduce the generated provided-wrapper failure in both backends:

```sh
python3 scripts/spike_retained_callable.py --opt all --iterations 1000 \
  --mode wrapper-negative
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

The negative reproducer is now reduced to `Box(function)`. A trivial generated
provided wrapper that consumes a non-recursive captured callable segfaults in
both development and optimized builds. A generic `Box(U64)` wrapper and an
explicit `Box(State)` with strings, a list, and an opaque resource drop
correctly. A `Box(State)` containing a nested boxed callable follows the failing
callable teardown path.

The development runtime exports a low-level erased-callable decrement helper.
Using that helper directly makes the effectful recursive-machine lifecycle pass
sequential thread migration, concurrent independent machines, overlap
rejection, cancellation, nested capture teardown, and opaque-resource balance.
This is diagnostic evidence only: the symbol is not exported by optimized
builds, and application host code must not depend on it.

The benchmark is not an end-to-end SSE or Go comparison. Its allocation
counters use atomics in the allocator and therefore perturb allocation-heavy
timings. It exists to choose the next design spike and to detect large ABI or
allocation regressions.
