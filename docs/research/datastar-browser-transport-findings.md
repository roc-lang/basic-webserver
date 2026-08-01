# Datastar browser and real-listener transport findings

Status: focused end-to-end evidence; production integration, remaining
browsers, slow readers, and cross-target gates remain open

Date: 2026-08-01

Research branch: `research/datastar-browser-transport`

Harness checkpoint: `b66c6fe`

Low-memory Brotli profile checkpoint: `d0f6b32`

## Scope

This second-wave spike tested whether the pinned Datastar v1.0.2 custom Fetch
client can actually consume progressively flushed identity and Brotli SSE from
a real listener. It also tested clean Brotli completion, browser cancellation,
direct HTTP/2 transport, and a real buffering reverse proxy.

It does not change the accepted platform contract in `design.md`. The listener
is a disposable Hyper harness using the bounded body and explicit Brotli
lifecycle adapter from the transport research. It is not the production
`basic-webserver` listener and does not exercise Roc stream-machine state.

Evidence labels use `docs/research/datastar-research-program.md`.

## Pins and environment

- **Specified:** Datastar client `v1.0.2`, commit
  `e24f04d43ca4445d662b4a035e5bfe9ed68de57c`.
- **Observed:** the served `datastar.js` has SHA-256
  `2837d87acf6ee0ba8e4e63765926c25a98d63883b02f88be194a86b81d3fd24a`.
- **Observed:** Firefox `153.0.1` and geckodriver `0.37.0` on Linux x86-64.
- **Observed:** curl `8.5.0` with nghttp2 `1.59.0` and Brotli `1.1.0`.
- **Observed:** rootlessly extracted Ubuntu NGINX `1.24.0-2ubuntu7.15`, built
  with OpenSSL and `http_v2_module`. Both package SHA-256 values are pinned in
  `research/datastar-browser-transport/assets.lock.json`.
- **Observed:** Rust `1.97.1`, Hyper `1.6.0`, and the pinned Rust Brotli crate
  `8.0.4`.

Exact commands and versions are committed in
`research/datastar-browser-transport/results/2026-08-01-environment.txt`.
The JSON-lines observations are beside it.

## Experiment construction

The real listener serves a page containing the pinned Datastar bundle and a
`data-init="@get(...)"` action. The stream emits one canonical
`datastar-patch-elements` event, then waits for a separate `/release` request.
The status endpoint records when each event is generated, the actual request
protocol and `Accept-Encoding`, selected coding/profile, encoded-frame sizes,
FINISH tail, request count, and cancellation cleanup.

The ordering assertion is deliberately stronger than a timer:

1. WebDriver waits for event one's element in the Firefox DOM.
2. The runner requires `second_generated_us` to still be null.
3. Only then does the runner call `/release`.
4. It waits for event two in the DOM and a normal server FINISH.

This proves the browser applied event one before event two existed. A private
buffer flush or a lucky short timer cannot satisfy the assertion.

The direct listener auto-detects HTTP/1.1 and cleartext prior-knowledge HTTP/2.
Firefox uses HTTP/1.1 for the cleartext origin; curl supplies the genuine h2c
client. For browser HTTP/2, NGINX terminates a loopback-only self-signed TLS
connection, forwards HTTP/1.1 upstream, and deliberately has
`proxy_buffering on`. The upstream response supplies `X-Accel-Buffering: no`.
Firefox `PerformanceResourceTiming.nextHopProtocol` must report `h2`.

## Hard findings

### Pinned Datastar progressively consumes identity and Brotli

- **Observed:** direct Firefox HTTP/1.1 applied event one for identity, Brotli
  q4/LGWin18, and Brotli q1/LGWin11 while the server still recorded no event
  two.
- **Observed:** after release, all three applied event two and ended normally.
- **Observed:** Firefox sent `Datastar-Request: true` and
  `Accept-Encoding: gzip, deflate, br, zstd`; Brotli selection was browser
  controlled rather than injected by action options.
- **Observed:** direct resource timing reported `http/1.1`.

The provisional low-memory q1/LGWin11 profile is therefore compatible with a
real pinned Datastar/Firefox progressive stream. This result is not inferred
from command-line decompression or q4/LGWin18 behavior.

### Direct HTTP/2 progressively decodes both codings

- **Observed:** curl over cleartext prior-knowledge HTTP/2 decoded the first
  identity and Brotli events before release while the listener recorded
  `HTTP/2.0` and no second event.
- **Observed:** the responses contained `Content-Type: text/event-stream`,
  `Cache-Control: no-cache`, `Vary: Accept-Encoding`, and
  `X-Accel-Buffering: no`, with `Content-Encoding: br` only for Brotli.
- **Observed:** after release, curl decoded event two and accepted normal EOF.

This closes the small progressive-frame question for a real H2 socket. It does
not close browser-on-direct-H2, H2 flow-control fairness, or one blocked stream
beside an unrelated stream.

### NGINX does not hide event one

- **Observed:** Firefox consumed identity, q4/LGWin18 Brotli, and q1/LGWin11
  Brotli progressively through a real NGINX TLS HTTP/2 frontend.
- **Observed:** browser resource timing reported `h2` for every proxy stream.
- **Observed:** NGINX was configured with `proxy_buffering on`; event one still
  appeared before release because the upstream response supplied
  `X-Accel-Buffering: no`.
- **Observed:** the backend saw HTTP/1.1, which matches the explicit upstream
  proxy configuration. The result proves an H2 browser edge path, not H2 on
  both sides of NGINX.

This supports `X-Accel-Buffering: no` as the default candidate. It does not
prove behavior when an operator configures NGINX to ignore that header.

### Normal EOF FINISHes and does not retry

- **Observed:** every completed Brotli case emitted a one-byte FINISH tail.
- **Observed:** Firefox applied event two, the action ended, and request count
  remained exactly one after a post-close observation window.

This is end-to-end evidence for a valid normal close under pinned Datastar's
default `retry: auto`. It deliberately exceeds the official Go SDK v1.2.2,
which exposes no compressor close and leaves normal Brotli EOF unfinished.
The one-byte tail is trace-specific and must not become a size invariant.

### Browser cancellation reaches producer cleanup

- **Observed:** navigating Firefox away after event one caused the direct
  Brotli body to drop and producer cleanup to be observed in 9.9 ms in the
  committed run.
- **Observed:** the same operation through NGINX HTTP/2 reached backend cleanup
  in 8.7 ms.
- **Observed:** both cancellation cases generated no event two, emitted no
  FINISH tail, and retained request count one.

The producer polls the bounded body's cancellation bit every 5 ms, and these
are single observations on an idle machine. The values are useful cleanup
evidence, not a portable cancellation-latency guarantee.

## Profile observation, not a compression-value decision

For this tiny event pair, q4/LGWin18 emitted 109 bytes then 18 bytes directly,
whereas q1/LGWin11 emitted 133 bytes for each event. Both added a one-byte
FINISH tail. The low-memory profile's lack of cross-event savings in this trace
is important but not sufficient to reject it: the trace contains different
stream IDs and only two small events. The transport sweep's realistic corpus,
retained memory, CPU, and scale results remain the authority for choosing the
candidate default.

This browser spike establishes semantic compatibility only. Its first-visible
times are affected by browser startup, connection reuse, and case order and
must not be used as a performance comparison between profiles or codings.

## Go comparison boundary

The official Go reference already proved progressive prefix delivery but has
an unfinished normal Brotli stream. Repeating it in Firefox would compare a
known lifecycle bug to the desired contract and could trigger Datastar's
exception retry path. The useful comparison here is precise:

- Go and the Rust harness both FLUSH an incrementally decodable prefix.
- The Rust experiment additionally FINISHes on normal EOF and aborts without a
  tail on disconnect.
- No end-to-end throughput or allocation comparison is claimed by this run.

## Explicit gates still open

- Chromium and WebKit/Safari progressive identity/Brotli behavior.
- Direct browser HTTP/2 against the eventual trusted-proxy/basic-webserver
  deployment topology. Firefox cannot negotiate h2c from the current cleartext
  research listener.
- The production `basic-webserver` listener, `ServerBody`, response authority,
  request accounting, deadlines, and graceful-shutdown integration.
- Roc retained-machine production and cleanup.
- Automatic replacement, explicit AbortController, hidden-page cancellation,
  and every Datastar retry mode. This run uses navigation cancellation only.
- A slow or non-reading H1/H2 client, memory high-water marks, HTTP/2
  multiplexing fairness, and an unrelated stream beside a blocked stream.
- Proxy timeout/heartbeat behavior and a proxy configured to ignore
  `X-Accel-Buffering`.
- A proven persistent-FLUSH output bound and integrated failure injection.
- Cross-target and cross-browser release coverage.
- Public TLS policy; the self-signed loopback certificate only enables genuine
  browser H2 in the disposable test.

## Exact experiment recommendations

1. Keep the Spike 0 browser matrix open, but record Firefox as observed passing
   progressive identity and Brotli for direct H1 and NGINX-fronted H2.
2. Require the browser progressive test to expose a server-side generation
   gate. “Event one arrived before a fixed delay” is weaker and can hide
   generation or buffering races.
3. Split Spike 2 evidence: the synthetic real-listener H1/h2c ordering and body
   drop pass here; production `ServerBody`, slow-reader, H2 fairness, and
   accounting remain open.
4. Record `X-Accel-Buffering: no` as observed effective with NGINX 1.24 while
   `proxy_buffering on`, without yet making it an unconditional contract.
5. Add q1/LGWin11 to Spike 5's candidate matrix. It passes real Firefox H1 and
   NGINX H2 progressive/FINISH behavior, but value and scale decide whether it
   becomes the fixed default.
6. Preserve separate normal-close and disconnect assertions: normal close must
   produce a decoder-accepted tail; disconnect must release the encoder without
   one.
7. Treat cancellation timing as a distribution measured through the integrated
   host. The 5 ms research poll makes this run an upper-bound observation, not
   a scheduler design.
8. Do not call the browser/proxy gate complete until Chromium and WebKit run
   the same generation-gated cases and the production listener owns the body.
