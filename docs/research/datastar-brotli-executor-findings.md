# Bounded SSE Brotli executor findings

Status: production-path feasibility passed; final configuration, telemetry,
and whole-process allocation measurement remain open

Date: 2026-08-03

This is implementation-specific research and does not change
[`design.md`](../../design.md).

## Result

Negotiated Brotli for a retained Roc SSE response no longer executes encoder
PROCESS, FLUSH, or FINISH inside `Body::poll_frame`. The server starts a fixed
set of named `basic-webserver-brotli-N` threads and a fixed number of reusable
lane slots. A compressed stream must acquire one lane before its response is
constructed. Every finite encoder operation consumes the lane and the body's
already reserved output frame, wakes the body on completion, and returns the
same Roc-backed `Bytes` input, input offset, and frame reservation. The encoder
stays in its stable lane cell instead of copying its roughly 7 KiB inline state
through the queue on every operation.

This establishes isolation for the incremental encoder operations, not the
entire encoder lifecycle. Encoder construction currently occurs during
precommit lane admission, and normal encoder destruction occurs when the body
consumes the completed FINISH result. Moving create/destroy onto the executor
remains a possible follow-up if measurement shows meaningful transport-worker
cost.

The scale profile used by the live application path is q1/LGWin11 with the
existing 256 KiB capped scratch recycler. The q3/LGWin12 compression profile is
also implemented and tested but is not yet selected by public configuration.

Validation passes:

- incremental PROCESS/FLUSH/FINISH round-trips through seven-byte frames;
- operations report one of the fixed worker indices and never execute in the
  body poll;
- lane admission reaches its exact configured capacity and rejects the next
  stream;
- a real Hyper HTTP/1.1 response independently decodes after normal FINISH;
- bounded HTTP/2 normal flow control and stopped-reader cancellation both
  return their frame and lane capacity;
- deterministic queued and post-operation/pre-publication cancellation
  interleavings, plus prompt in-flight body cancellation, make the lane
  available only after worker cleanup;
- dropping a body with an in-flight operation cancels its source once and
  obeys the same delayed lane release;
- the retained Roc SSE example completes both identity and negotiated `br`
  requests through the real listener; and
- all 188 Rust host tests, 215 Roc platform tests, and 53 native runtime cases
  pass.

The native `br` case proves production negotiation and drains the compiled Roc
stream to EOF. A separate real-Hyper test independently decodes the bounded
executor output byte-for-byte. The portable Python listener harness does not
currently contain a Brotli decoder, so exact decoding of that same compiled-app
exchange remains a distinct integration gate rather than an implied claim.

## Fixed ownership and queue bounds

At startup the executor allocates:

- `K = min(available_parallelism, max_handlers)` named worker threads;
- `M = max_handlers` lane descriptors, stable inline encoder storage, and
  completion/waker cells; and
- one `sync_channel` with capacity `M` for inline operation messages.

These are research defaults. A final configuration should name compressed
stream lanes independently from Roc handler concurrency and include their
encoder/scratch/frame bytes in startup validation.

A stream owns one lane. A lane permits at most one message, and the number of
messages cannot exceed the number of admitted lanes, so the channel's `M`
capacity is a derived bound rather than a second unbounded queue. Active,
queued, running, and high-water counters are maintained independently.

Submission is affine:

```text
IdleLane { stable encoder, lane cell }
  + input owner + input offset + frame reservation
    -> InFlightJob
      -> Completion { IdleLane, same input, new offset, same reservation, step }
```

The body cannot touch an encoder or reservation while the worker owns it. A
normal source EOF alone drives FINISH. Error, disconnect, timeout, or body drop
sets cancellation and drops its job handle. Queued cancellation skips the
encoder call; running cancellation lets the one finite call return and then
destroys the encoder without FINISH. Neither case publishes output or releases
lane admission early.

Adversarial review found one race in the first implementation: cancellation
could occur after a worker's final atomic check but before it published the
completion, leaving that completion and lane without an owner. Publication now
checks cancellation while holding the same result-cell mutex that job drop uses
to remove a completed result. Deterministic barriers pin that precise
interleaving as well as cancellation while still queued.

The same review found that in-flight work originally retained the executor
object that owned worker join handles. The last reference could therefore be
dropped by a worker during shutdown, making it try to join itself. Worker-visible
state is now a separate reference-counted core; only an owner-side executor
handle owns and joins threads. A barrier test proves owner shutdown waits for
in-flight cleanup and completes on the owner thread.

## Allocation hypothesis

The operation hot path intentionally contains no per-operation `Box`, `String`,
new `Vec`, task spawn, or unbounded queue node:

- lane cells and the bounded channel are created at startup;
- the stream's frame `Vec` is created once and moved through each message;
- `Bytes` clones retain the same Roc list allocation;
- the lane's encoder remains in its stable slot while a worker advances it;
- waker registration replaces one cell value; and
- q1 scratch allocations are served by the already measured bounded recycler
  after warmup.

This removes the obvious executor-side allocation sources and is designed to
preserve the previous zero-steady-allocation body architecture. It is not yet a
new whole-process allocation proof: Hyper, Tokio, channel internals, wake
behavior, Roc event construction, and the first stream/encoder admission remain
outside the earlier counted window. The next performance gate should rerun the
global allocator counter around a warmed retained Roc source and this exact
executor, separating one-time stream setup from per-event steady state.

## Remaining product decisions

- independent configuration and metrics for workers, lanes, queue/running
  counts, scratch bytes, and saturation;
- whether a client that accepts both identity and Brotli falls back to identity
  when Brotli lanes are full or receives the current precommit 503;
- selecting scale versus compression profiles from explicit platform policy;
- executor shutdown and hard-deadline diagnostics for a pathological encoder
  operation;
- moving encoder construction and destruction off transport workers if their
  measured cost warrants it;
- the precommit first-transition gate and end-to-end allocation/resource ledger;
  and
- mixed HTTP/2 stopped-reader load proving ordinary request p99 and unrelated
  stream progress while all Brotli workers and lanes are occupied.
