# SSE owned-frame allocation findings

Status: focused feasibility evidence, not a production body implementation.
This work does not change `design.md`.

## Conclusion

The remaining steady-state frame allocation is caused by the current internal
body-data type, not by Brotli or an unavoidable Hyper requirement.

`ServerBody` is currently fixed to `Body<Data = Bytes>`. A pooled vector can be
adapted safely with `Bytes::from_owner`: dropping the last `Bytes` invokes the
frame's destructor, returns the vector, and wakes a blocked producer. However,
the pinned bytes 1.11.1 implementation boxes every owner. The measured adapter
therefore allocates and frees exactly one 56-byte owner for every output frame.

A candidate internal sum type removes that adapter:

```rust
enum ServerData {
    Bytes(Bytes),
    Pooled(PooledFrame),
}
```

Both variants implement `Buf`. Ordinary responses retain their existing
`Bytes`; an SSE frame owns a preallocated vector whose `Drop` returns the slot
and wakes a waiting producer. This is an internal host type change, not a Roc
application API or wire-protocol change.

After 2,048 warmup events, 10,000 measured events through the bounded queue,
resumable encoder, frame wrapper, `Frame`, and synchronous body poll made zero
global allocator/deallocator calls for identity, recycled q1/LGWin11, and
standard q3/LGWin12. Every run ended with the only slot free, no slot in use,
and high-water exactly one.

This selects the internal `ServerData` direction for the next production-body
spike. It does not yet justify changing production code: the real Hyper
listener, `TrackedResponseBody`, H2 flow control, deadlines, shutdown, and
ordinary response regression matrix must pass with the wider data type.

## Exact allocation result

The fixture uses one preallocated 4,096-byte frame, one persistent encoder, a
Datastar-shaped event targeting 4,096 bytes, and an immediate synchronous body
consumer. Allocation accounting covers only the 10,000-event measured window.

| Adapter | Mode | Output frames | Allocations | Bytes allocated | Final slots free/in use |
| --- | --- | ---: | ---: | ---: | ---: |
| `ServerData::Pooled` | identity | 10,000 | 0 | 0 | 1 / 0 |
| `ServerData::Pooled` | q1/LGWin11 | 20,000 | 0 | 0 | 1 / 0 |
| `ServerData::Pooled` | q3/LGWin12 | 10,000 | 0 | 0 | 1 / 0 |
| `Bytes::from_owner` | identity | 10,000 | 10,000 | 560,000 | 1 / 0 |
| `Bytes::from_owner` | q1/LGWin11 | 20,000 | 20,000 | 1,120,000 | 1 / 0 |
| `Bytes::from_owner` | q3/LGWin12 | 10,000 | 10,000 | 560,000 | 1 / 0 |

The q1 encoder emitted two frames per event for this corpus/configuration; this
is why its `Bytes` adapter has two allocations per event. It is not a general
frame-count guarantee. The meaningful invariant is one allocation per adapted
frame versus zero for the custom `Buf` data path.

The benchmark does not measure latency and repeats one event. Its purpose is
allocation provenance, not compression value or an end-to-end performance
comparison. The earlier multi-corpus and Go results remain authoritative for
compression ratio, encoder time, and retained state.

## Ownership and cancellation observations

Focused tests establish:

- one fixed slot bounds the queue and prevents a second reservation;
- dropping a transport-owned `PooledFrame` returns the vector and wakes the
  registered producer;
- abandoned reservations, queued cancellation, and in-flight cancellation all
  return the slot exactly once;
- body cancellation wakes a producer already waiting for a frame;
- the `Bytes::from_owner` compatibility path passes the real
  `response::finalize_response` authority as an unknown-length HTTP/2 body;
- PROCESS, FLUSH, and FINISH remain resumable across fixed frames; and
- recycled q1 and standard q3 both retain zero measured steady allocations
  when the custom `ServerData` wrapper is used.

The compatibility test matters because it proves the existing response rules
and unknown-length framing are already correct. The incompatibility is only
the `ServerBody::Data` type: the real authority accepts the pooled body after
conversion to `Bytes`, and that conversion is the measured allocation.

## Why the tempting `Bytes` alternatives do not close the gate

`Bytes::from_owner` has the required drop callback but allocates its owner box.
A retained `Bytes` clone over a preallocated slab can avoid the box and detect
uniqueness later, but dropping the transport's clone does not call platform
code. If the producer has already returned `Pending`, no supported public API
wakes it when the last external clone disappears. Polling or overprovisioning
would weaken prompt backpressure and shutdown behavior.

Unsafe access to bytes' private vtable, leaking slabs, or relying on Hyper to
drop a frame before its next poll are rejected. They would replace a measured
small allocation with an undocumented lifetime assumption.

## Next production-body spike

1. Prototype `ServerData` in the host and change `ServerBody`/tracked bodies to
   use it, mapping ordinary `Bytes` bodies without copying.
2. Keep the pool finite and separately account free, reserved, queued, and
   transport-owned slots. Saturation returns `Pending`; frame drop wakes the
   producer.
3. Run every existing ordinary response, HEAD, file, H1, and H2 case to prove
   that widening the internal data type has no semantic regression.
4. Put the resumable identity/q1/q3 body through a real listener. Stop a reader
   after the pool fills and prove the byte/frame high-water remains fixed.
5. Cancel before encoding, during PROCESS, during FLUSH, while queued, and while
   transport-owned. All frame, encoder, and request accounting must return to
   zero through the unified close path.
6. Measure full-path allocations and latency with realistic changing corpora
   and enough slots for real H2 behavior; then test an unrelated H2 stream and
   ordinary-request p99.

Raw output is in
[`2026-08-02-frame-ownership.jsonl`](../../research/datastar-transport/results/2026-08-02-frame-ownership.jsonl)
with its
[`environment`](../../research/datastar-transport/results/2026-08-02-frame-ownership-environment.txt).
