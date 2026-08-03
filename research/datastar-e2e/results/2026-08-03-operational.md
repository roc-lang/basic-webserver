# Roc versus Go SSE operational comparison: 2026-08-03

This follow-up tests the bounded lifecycle around the event hot path rather
than another framing or transport optimization. Raw records are in
[`2026-08-03-operational.jsonl`](2026-08-03-operational.jsonl).

## Reproduction

The environment record pins:

- basic-webserver `8d3483d93da109b884a7d2666722295f0026a4b3`;
- Roc `debug-5a5f4c02` from the compiler branch used for the retained-callable
  and `Str.repeat` work;
- Go 1.26.5; and
- 3 measured samples after one warmup, with Roc and Go pinned to the same
  server CPU and clients pinned to another CPU.

Run the operational subset with:

```sh
python3 scripts/datastar_benchmark.py \
  --roc /path/to/roc \
  --go /path/to/go \
  --samples 3 \
  --warmup 1 \
  --skip-hot \
  --skip-allocations \
  --idle-streams 10,50,100 \
  --load-requests 64 \
  --load-concurrency 16 \
  --wake-streams 32 \
  --disconnects 50 \
  --output results/operational.jsonl
```

The Go reference now has the same explicit 128-stream admission limit as the
Roc comparison app. That is comparison scaffolding around datastar-go, not a
claim that the SDK supplies server admission policy automatically.

## Result

The current implementation is operationally comparable to the bounded Go
reference in this controlled local test:

- With no parked streams, 16 concurrent ordinary requests reached median
  18,421 requests/s in Roc and 18,132 requests/s in Go. With 50 parked SSE
  responses, Roc measured 17,238 requests/s and Go 19,318 requests/s. Median
  p99 was 1.05 ms for Roc and 0.93 ms for Go with the parked streams. These raw
  TCP requests deliberately include connection setup and Python driver cost;
  the result supports isolation from parked SSE, not a sub-millisecond product
  guarantee.
- Thirty-two streams waking after the same 100 ms delay completed their second
  event at p99 103.74 ms in Roc and 103.06 ms in Go. Completion spread was
  2.21 ms in Roc and 2.60 ms in Go. The unified Roc pool handled the wake wave
  without serializing one worker per parked stream.
- At exactly 128 parked streams, the next identity and Brotli stream received
  `503` in both implementations. Closing one stream restored admission; all
  median saturation responses and recovery requests completed in under
  0.1 ms.
- After 50 rapid open/first-event/disconnect cycles, both identity and Brotli
  servers immediately served a finite stream. Median recovery was 0.068-0.079
  ms for Roc and 0.044-0.080 ms for Go.
- Progressive event gaps remained close to the requested 100 ms: Roc measured
  101.19 and 101.17 ms; Go measured 100.19 and 100.17 ms. First response bytes
  arrived in 0.20 ms for Roc and 0.16 ms for Go.

## Parked memory

RSS deltas are page-granular and noisy at small counts, so the 100-stream
sample is the useful comparison:

| Coding | Roc bytes/stream | Go bytes/stream | Roc/Go |
| --- | ---: | ---: | ---: |
| identity | 99,410 | 43,704 | 2.27x |
| Brotli q1 | 104,284 | 76,308 | 1.37x |

This characterizes the accepted implementation rather than reopening the hot
path. Each parked Roc body currently owns its response frame capacity. Sharing
frames only among active streams remains a possible future optimization, as
does structured host framing of the one remaining Roc event allocation. Both
are explicitly outside this consolidation work.

## Interpretation

The evidence now covers the comparison questions that matter for this design:

- parked sources consume no Roc worker;
- ordinary work remains responsive with many active SSE requests;
- a simultaneous ready wave has Go-comparable timing;
- stream capacity saturates deliberately and recovers immediately;
- cancellation storms return stream and Brotli capacity; and
- the remaining measurable gap is parked memory and small-event fixed cost,
  not an unbounded lifecycle or transport failure.

This does not claim that Roc wins every microbenchmark. The acceptance target
is a predictable bounded server with an idiomatic typed application API and
operational behavior comparable to a deliberately bounded Go implementation.
