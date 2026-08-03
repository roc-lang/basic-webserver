# Roc versus Go Datastar SSE comparison

This directory contains the socket-level comparison promised by the Datastar
research program. `app.roc` and the pinned official Go SDK reference server
serve the same fixed workloads; `scripts/datastar_benchmark.py` builds both,
verifies their decoded event streams, and records repeated measurements.

The comparison has two distinct compression baselines:

- `identity` sends uncompressed SSE from both servers;
- `scale` selects Brotli q1/LGWin11 in Go, matching the current bounded Roc SSE
  executor. Roc cleanly finishes the stream; datastar-go v1.2.2 has no close
  operation for its retained encoder, so this unavoidable semantic difference
  is reported rather than hidden.

The hot routes are `/hot-100`, `/hot-1000`, `/hot-10000`, `/hot-4096`, and
`/hot-65536`.
The corresponding `/transport-256`, `/transport-4096`, and
`/transport-65536` routes retain one pre-rendered HTML value so they isolate
SDK framing and transport from per-event application rendering.
`/progressive` emits three events 100 ms apart, `/finite` emits one event, and
`/idle` emits immediately and then parks for 60 seconds.

This is research evidence, not an accepted change to `design.md`.

The measured result and prioritized follow-up hypotheses are in
[`results/2026-08-03-analysis.md`](results/2026-08-03-analysis.md). The complete
machine-readable observations are retained beside it in
[`results/2026-08-03-raw.jsonl`](results/2026-08-03-raw.jsonl).
The follow-up `Str.repeat` isolation and fix are captured in the paired
[`results/2026-08-03-repeat-before.jsonl`](results/2026-08-03-repeat-before.jsonl)
and
[`results/2026-08-03-repeat-after.jsonl`](results/2026-08-03-repeat-after.jsonl)
files.
The unified Roc executor is measured with the same compiler on both sides in
[`results/2026-08-03-executor-before.jsonl`](results/2026-08-03-executor-before.jsonl)
and
[`results/2026-08-03-executor-after.jsonl`](results/2026-08-03-executor-after.jsonl).
An intermediate run before replacing the final `Bytes` owner box is retained
in
[`results/2026-08-03-executor-before-inline.jsonl`](results/2026-08-03-executor-before-inline.jsonl).

Run the controlled Linux comparison with:

```sh
python3 scripts/datastar_benchmark.py \
  --output research/datastar-e2e/results/YYYY-MM-DD-raw.jsonl
```

The server is pinned to logical CPU 2 and curl to logical CPU 3. The script
uses HTTP/1.1 because Go's idiomatic `net/http.ListenAndServe` reference does
not offer cleartext HTTP/2; HTTP/2 remains a Roc transport validation rather
than part of this direct semantic comparison.
