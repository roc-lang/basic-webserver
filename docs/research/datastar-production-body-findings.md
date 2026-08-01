# Production SSE body transaction findings

Status: production-internal body and transport feasibility passed; Roc source
adapter, admission, shutdown integration, and public API remain open.

Date: 2026-08-02

This work does not change `design.md`.

## Conclusion

The selected bounded transaction works in the production host without
steady-state body, frame, or compressor allocations for identity, recycled
q1/LGWin11, and standard q3/LGWin12.

The internal `SseBody` owns a pull source of already validated, canonically
framed items. It reserves one fixed pool frame before polling the source and
before every Brotli PROCESS, FLUSH, or FINISH call. Encoder input position and
operation phase survive `Pending`; a returned `ServerData::Pooled` keeps the
slot transport-owned until Hyper or h2 drops it. There is no intermediate body
queue.

Normal source EOF drives FINISH to completion. Body error, idle timeout,
disconnect, or drop cancels the source and destroys the encoder without
emitting a tail. The close state is idempotent and separately reports pending
item bytes, active encoder, source EOF, finished, failed, and cancelled.

This is strong evidence for the host body architecture. It is not yet the
public SSE implementation: the source used by the live tests is scripted, not
a retained Roc machine, and the body is not yet admitted or constructed by the
application response path.

## Allocation result

One persistent production `SseBody` reused one 4,096-byte Datastar-shaped item
and one 4,096-byte frame slot. After 2,048 warmup events, allocator counters
covered 10,000 events. Corpus creation, stream construction, and normal FINISH
were outside the counted window.

| Mode | Output frames | Allocations | Requested bytes | Final free/in use | High-water slots |
| --- | ---: | ---: | ---: | ---: | ---: |
| identity | 10,000 | 0 | 0 | 1 / 0 | 1 |
| q1/LGWin11, standard scratch | 20,000 | 40,000 | 140,960,000 | 1 / 0 | 1 |
| q1/LGWin11, 256 KiB recycler | 20,000 | 0 | 0 | 1 / 0 | 1 |
| q3/LGWin12, standard scratch | 10,000 | 0 | 0 | 1 / 0 | 1 |

The standard q1 result identifies the remaining hot-path allocation exactly:
four Brotli scratch allocations and 14,096 requested bytes per event. Moving
the already selected fixed-slot scratch recycler into the production
compression authority removes all of them without changing output frames or
wire bytes. A focused test confirms that system allocations stop after warmup,
cache hits continue, and cached bytes remain within 256 KiB.

These counters include the production source poll, item `Bytes` clone, body
phase machine, frame reservation, encoder calls, `ServerData` wrapping, body
poll, and frame release. They do not include Hyper, h2, Tokio, or socket
allocation behavior; end-to-end allocator and latency measurements remain a
separate gate.

## Live transport and lifecycle result

Focused tests use the real response authority and transport implementations:

- HTTP/1.1 sends and independently decodes a normally FINISHed q3 stream;
- the manual HTTP/2 sender sends the same body through a seven-byte initial
  flow-control window and independently decodes it;
- every run uses one seven-byte pool slot and reaches high-water exactly one;
- a stalled HTTP/2 reader consumes the first grant and releases no further
  capacity; the response idle deadline resets the stream;
- that timeout cancels the source exactly once, aborts Brotli without FINISH,
  clears pending item and active encoder accounting, and returns all frame
  states to one free, zero reserved, zero transport-owned; and
- an oversized framed item fails before encoding and releases its reservation.

The pool reports free, reserved, and transport-owned slots separately. The body
reserves before polling the source, so application state cannot advance when no
output capacity exists. With a one-slot pool, the retained bound is one framed
item plus one output frame and the encoder state; the transport may additionally
retain only its independently configured bounded send buffer.

## Remaining gates

1. Implement the `SseItemSource` adapter for the selected retained Roc machine
   ABI and prove that cancellation drops the returned and pending Roc states
   exactly once.
2. Admit streams and compressed encoders through finite host resources before
   response commitment; connect request tracking, graceful drain, shutdown,
   heartbeat, and declarative wakes.
3. Run mixed H2 streams and ordinary request load under a stopped reader; gate
   queue/byte high-water, unrelated-stream latency, and ordinary p99.
4. Count full Hyper/h2/Tokio/socket-path allocations and measure event latency
   with changing corpora. Separate one-time connection/stream allocations from
   per-event steady state.
5. Add the recycled allocator's retained bytes to global compressed-stream
   admission and observability; exercise its ceiling across selected targets.
6. Only then select the public Roc SSE/Datastar API and add representative
   applications to the cross-platform runtime specification.

Raw results are in
[`2026-08-02-production-body-allocations.jsonl`](../../research/datastar-transport/results/2026-08-02-production-body-allocations.jsonl)
with the reproducible
[`environment and commands`](../../research/datastar-transport/results/2026-08-02-production-body-allocations-environment.txt).

## Validation

The final tree passes with Zig compiler `debug-e1d283cb`:

- all 179 production host library tests;
- all 32 research-crate tests;
- all 215 Roc platform tests; and
- all 52 live x64musl runtime specification cases.
