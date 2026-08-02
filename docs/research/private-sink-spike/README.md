# Private retained-source result cell spike

Status: source topology type-checks, builds, and generates its supported ABI on
clean `debug-e1d283cb`; runtime ownership/performance remains unmeasured.

This minimal negative fixture moves the one-shot result deposit to an exposed
platform `Sse` module. The application callback receives only its typed state
and wake; it returns an item, next state, and wait. It never receives the hidden
`Host.StepSink` capability. The platform wrapper deposits once and directly
returns the next retained `Sse.Stream`, so it does not recreate a composite
result containing the next callable.

On Roc branch `datastar-erased-repack-arc` at
`e1d283cbff4230e8354f72959a0367a8200771ad`, this passes:

```sh
/path/to/roc check docs/research/private-sink-spike/app.roc
```

An archive build also passes:

```sh
/path/to/roc build --no-cache --opt=speed --target=x64musl \
  --output=build/private-sink-spike \
  docs/research/private-sink-spike/app.roc
```

The supported glue-generation step succeeds and emits the fixed make, advance,
drop, and hosted-deposit declarations:

```sh
/path/to/roc glue --no-cache \
  /path/to/roc/src/glue/src/CGlue.roc \
  build/private-sink-glue \
  docs/research/private-sink-spike/platform/main.roc
```

This fixture is not a platform implementation. It establishes that the desired
application abstraction and generated ABI are expressible. It does not yet
measure whether the generic platform-owned wrapper preserves direct callable
reuse, whether its captured transition/state introduce other ARC traffic, or
the cell's cancellation/join lifecycle. Those are the first tasks when server
research resumes after the composite-result compiler work.

The design boundary and competing composite result are recorded in
[`../datastar-retained-source-contract.md`](../datastar-retained-source-contract.md),
with measurements and compiler diagnosis in
[`../abi-spike/results/2026-08-02-composite-source.md`](../abi-spike/results/2026-08-02-composite-source.md).
