# Datastar browser and real-listener transport spike

This disposable harness closes the smallest end-to-end part of Spike 0, Spike
2, and Spike 5 from `docs/datastar-experiment.md`. It serves the exact pinned
Datastar v1.0.2 browser bundle from a real Hyper listener and proves whether
one identity or Brotli event is applied before the server is allowed to create
event two.

It is research code, not a production SSE implementation. The listener reuses
the bounded body and explicit Brotli FLUSH/FINISH/abort adapter in
`research/datastar-transport`; it does not add SSE to `basic-webserver`.

## What the runner proves

For every progressive case, event two is guarded by `/release`. The runner:

1. waits until pinned Datastar has patched the real Firefox DOM with event one;
2. reads `/status` and requires `second_generated_us` to still be null;
3. releases event two and waits for its DOM patch;
4. requires one request only after clean EOF; and
5. for Brotli, requires a non-empty FINISH tail.

Firefox navigation supplies the cancellation case. The server requires body
drop to reach producer cleanup without generating event two or FINISHing the
Brotli stream. Direct HTTP/2 uses curl's real prior-knowledge H2 transport,
because browsers do not negotiate h2c. The NGINX case provides a real TLS H2
browser frontend with buffering configured on; the upstream response's
`X-Accel-Buffering: no` must still make event one visible. Firefox performance
entries are asserted as `h2` for that path.

Both the earlier semantic-comparison profile (quality 4, LGWin 18) and the
transport sweep's provisional low-memory candidate (quality 1, LGWin 11) run
through real Firefox over direct HTTP/1.1 and the NGINX HTTP/2 frontend. The
candidate profile is therefore browser-observed, not inferred from a
command-line decoder.

## Reproduce

Requirements: Rust, Python 3, Firefox, geckodriver, curl with HTTP/2 and Brotli,
and OpenSSL. NGINX is optional but required for the proxy/browser-H2 cases.

```sh
cargo build \
  --manifest-path research/datastar-transport/Cargo.toml \
  --release \
  --bin browser_transport_server

python3 research/datastar-browser-transport/run_browser_transport.py
```

On Ubuntu 24.04 x86-64, obtain the exact rootless reference proxy without
installing a system package:

```sh
python3 research/datastar-browser-transport/prepare_nginx.py /tmp/datastar-nginx-root

python3 research/datastar-browser-transport/run_browser_transport.py \
  --nginx /tmp/datastar-nginx-root/usr/sbin/nginx \
  --output research/datastar-browser-transport/results/observations.jsonl
```

`assets.lock.json` pins the Datastar asset and both NGINX package checksums.
The runner verifies the Datastar bundle before launching. The NGINX preparation
script verifies package bytes before extraction.

## Evidence boundary

The committed observations are one indicative run, not a latency benchmark.
They establish ordering, protocol, headers, clean close, and cleanup behavior.
They do not establish portable timing, slow-reader bounds, HTTP/2 fairness,
production listener integration, or cross-browser/cross-target behavior.
