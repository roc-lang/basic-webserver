# Roc versus Go SSE operational comparison: 2026-08-03

This follow-up tests the bounded lifecycle around the event hot path rather
than another framing or transport optimization. Raw records are in
[`2026-08-03-operational.jsonl`](2026-08-03-operational.jsonl).

## Reproduction

The environment record pins:

- basic-webserver and harness `54d54708fba0658284a889bf10a868aaae1e17de`;
- Roc `debug-5a5f4c02` from the retained erased-callable compiler branch;
- Go 1.26.5;
- one server process on CPU 2 and the Python/curl clients on CPU 3; and
- three measured samples after one warmup for timing scenarios. Idle-memory
  samples intentionally use fresh processes without warmup so their fixed and
  marginal costs remain visible.

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
  --ready-streams 64 \
  --wake-streams 96 \
  --disconnects 50 \
  --output results/operational.jsonl
```

The Go reference has the same explicit 128-stream admission limit as the Roc
comparison app. That is comparison scaffolding around datastar-go, not a claim
that the SDK supplies server admission policy automatically.

## Result

The corrected evidence supports the accepted bounded design:

- Parked streams did not occupy execution capacity. With 16 concurrent
  ordinary clients, median p99 was 1.94 ms with no parked Roc streams and
  1.29 ms with 50; Go measured 1.35 ms and 2.12 ms. The change within each
  implementation is run noise, so this establishes absence of material parked
  interference rather than a throughput ranking.
- A contention scenario started 64 transition-heavy, 1,000-event SSE responses
  alongside 64 ordinary requests. Roc ordinary-request p99 was 13.50 ms while
  the SSE group completed in 531 ms; Go ordinary p99 was 221.18 ms while its
  SSE group completed in 221 ms. Roc's unified bounded pool preserved ordinary
  responsiveness by sharing execution, at the cost of lower aggregate event
  throughput in this single-core workload. This is the clearest remaining
  engineering tradeoff, not evidence for another framing ABI.
- For 96 concurrently opened two-event streams, the per-stream first-to-second
  event gap had median p99 102.33 ms in Roc and 110.84 ms in Go against a
  requested 100 ms. This deliberately reports each stream's gap; it does not
  claim that connection setup armed every timer at one common instant.
- At exactly 128 parked streams, the next stream received `503` in both
  implementations. Closing one restored admission. Identity and Brotli runs
  both sent their matching `Accept-Encoding`; successful Brotli recovery also
  required `Content-Encoding: br`.
- A concurrent burst of 50 open/first-event/disconnect operations returned
  parked stream slots and Brotli lanes. Median recovery was 0.18/0.30 ms for
  Roc identity/Brotli and 0.13/0.17 ms for Go. This covers parked cancellation,
  not cancellation of a synchronously running Roc transition.
- Progressive event gaps stayed close to the requested 100 ms: Roc measured
  101.29 and 101.21 ms; Go measured 100.24 and 100.56 ms. First response bytes
  arrived in 0.38 ms for Roc and 0.24 ms for Go.

The request counts are intentionally small and include raw TCP connection and
Python-driver cost. They are useful for bounded lifecycle comparisons, not
sub-millisecond product guarantees or headline requests-per-second claims.

## Parked memory

Cold-start delta divided by stream count was misleading because both servers
show substantial fixed lazy initialization. The table instead uses the median
RSS delta change from 50 to 100 streams:

| Coding | Roc marginal bytes/stream | Go marginal bytes/stream | Roc/Go |
| --- | ---: | ---: | ---: |
| identity | 45,629 | 40,796 | 1.12x |
| Brotli q1 | 49,316 | 75,530 | 0.65x |

These page-granular three-sample slopes do not establish a meaningful parked
memory gap. The active-only response-frame pool remains a possible future
optimization, as does structured host framing of the one remaining Roc event
allocation, but neither is justified as a consolidation gate by this evidence.

## Interpretation

The operational comparison now demonstrates:

- parked sources consume no Roc worker;
- ordinary handlers and ready SSE transitions genuinely contend through one
  bounded execution policy;
- timer-driven transitions remain close to Go at 96 concurrent streams;
- identity and Brotli stream capacity saturate deliberately and recover; and
- concurrent parked-stream cancellation returns stream and Brotli capacity.

The comparison does not claim that Roc wins every microbenchmark or that it
has covered preemption of running Roc code. The acceptance target is an
idiomatic typed API and a finite, observable lifecycle with Go-comparable
behavior. The evidence meets that target while identifying unified-pool
throughput/fairness as the next tuning surface if production workloads demand
it.
