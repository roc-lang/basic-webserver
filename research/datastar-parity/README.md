# Datastar client and Go parity research

Status: Spike 0 evidence for `docs/datastar-experiment.md`

Captured: 2026-08-01

This artifact pins the client contract that a first-party Roc `Datastar` module
must serve, records the official Go SDK's behavior and cost, and separates
compatibility requirements from behavior that `basic-webserver` should
deliberately improve. It does not change the accepted platform design.

Evidence labels have the meanings used by the experiment research program:

- **Specified**: required by a pinned source or standard.
- **Observed**: demonstrated by source inspection or a committed executable
  check.
- **Measured**: produced by the committed benchmark harness and raw results.
- **Inferred**: follows from evidence but still needs an end-to-end test.
- **Unknown**: must remain an open gate.

## Pins and authority order

The exact hashes, tag objects, and toolchain checksum are in
[`sources.lock.json`](sources.lock.json).

1. The compatibility target is the stable Datastar client `v1.0.2`, commit
   [`e24f04d`](https://github.com/starfederation/datastar/tree/e24f04d43ca4445d662b4a035e5bfe9ed68de57c).
2. The ergonomic and performance reference is `datastar-go v1.2.2`, commit
   [`60dc10e`](https://github.com/starfederation/datastar-go/tree/60dc10ebdaad3207d71e4bd8c1f158e65bb4acb0).
3. Generic event interpretation follows the pinned WHATWG HTML snapshot and
   HTTP content negotiation follows RFC 9110. The Datastar client has a custom
   Fetch implementation, so native `EventSource` reconnection behavior is not
   evidence for Datastar behavior.
4. The stable client's own SDK golden files are the canonical Datastar event
   bytes. The Go SDK is a reference implementation, but its divergences from
   those files are not requirements.

**Observed:** the Go SDK's `main` branch still equals `v1.2.2`. Datastar's
moving `main` was `ab49c217...` when inspected and differs materially from
`v1.0.2`: DELETE changed from query transport to a body, request cancellation
options changed, visibility reopen stopped rebuilding the payload, and retry
option names changed. The live documentation describes some moving-main
behavior. Therefore this experiment must not mix live prose with stable-client
source. Upgrading the pin requires rerunning every fixture and browser case.

Primary pinned sources:

- [client Fetch action](https://github.com/starfederation/datastar/blob/e24f04d43ca4445d662b4a035e5bfe9ed68de57c/library/src/plugins/actions/fetch.ts)
- [element watcher](https://github.com/starfederation/datastar/blob/e24f04d43ca4445d662b4a035e5bfe9ed68de57c/library/src/plugins/watchers/patchElements.ts)
- [signal watcher](https://github.com/starfederation/datastar/blob/e24f04d43ca4445d662b4a035e5bfe9ed68de57c/library/src/plugins/watchers/patchSignals.ts)
- [official SDK fixtures](https://github.com/starfederation/datastar/tree/e24f04d43ca4445d662b4a035e5bfe9ed68de57c/sdk/test/get-cases)
- [Go SSE implementation](https://github.com/starfederation/datastar-go/blob/60dc10ebdaad3207d71e4bd8c1f158e65bb4acb0/datastar/sse.go)
- [Go compression implementation](https://github.com/starfederation/datastar-go/blob/60dc10ebdaad3207d71e4bd8c1f158e65bb4acb0/datastar/sse-compression.go)
- [WHATWG SSE](https://html.spec.whatwg.org/multipage/server-sent-events.html)
- [WHATWG Fetch](https://fetch.spec.whatwg.org/)
- [RFC 9110 Accept-Encoding and Vary](https://www.rfc-editor.org/rfc/rfc9110.html)
- [NGINX proxy buffering](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffering)

## Stable client request contract

### Actions and signal placement

**Specified by `v1.0.2`:** all five backend actions use Fetch and can consume a
streaming SSE response. JSON is the default request content mode.

| Action | JSON transport | Form transport | `openWhenHidden` default |
| --- | --- | --- | --- |
| `@get` | `datastar=<JSON>` query parameter | form fields in query | `false` |
| `@post` | JSON request body | URL-encoded or multipart body | `true` |
| `@put` | JSON request body | URL-encoded or multipart body | `true` |
| `@patch` | JSON request body | URL-encoded or multipart body | `true` |
| `@delete` | `datastar=<JSON>` query parameter | form fields in query | `true` |

This DELETE behavior is easy to miss: it is present in the stable client and
the stable Go SDK's `ReadSignals`, but not in current documentation prose or
moving main.

The default request headers are:

```text
Accept: text/event-stream, text/html, application/json
Datastar-Request: true
```

Body-bearing JSON actions also set `Content-Type: application/json`. Form mode
sends no signals: it validates and serializes the selected or closest form.
For multipart forms the browser supplies the boundary; for other forms the
client uses `application/x-www-form-urlencoded`.

**Specified:** signal filtering defaults to all signals except a path segment
whose name begins with `_`. `payload` replaces the JSON signal payload.
Application-supplied headers overwrite defaults, including `Accept` and
`Datastar-Request`; neither is an authentication fact.

### Action options

The stable action options are:

- `contentType`: `json` (default) or `form`;
- `filterSignals`: include and exclude regular expressions;
- `selector`: form selector;
- `headers`: request header overrides;
- `openWhenHidden`;
- `payload`: replacement JSON payload;
- `requestCancellation`: `auto`, `cleanup`, `disabled`, or an
  `AbortController`;
- `retry`: `auto`, `error`, `always`, or `never`;
- `retryInterval` (1,000 ms), `retryScaler` (2), `retryMaxWait` (30,000 ms),
  and `retryMaxCount` (10);
- `responseOverrides`, which is declared in the type but is not passed into
  the Fetch machinery in `v1.0.2` and is therefore ineffective.

**Observed:** `auto` and `cleanup` cancellation both abort an older request
with the same method and URL anywhere in the document. `cleanup` additionally
aborts when the owning Datastar expression is cleaned up. `disabled` allows
overlap, and a supplied controller gives the application explicit control.

### Visibility, cancellation, and retries

**Specified/observed from pinned source:** when a default GET becomes hidden,
the client aborts the Fetch. When visible it rebuilds the URL/body from current
signals and opens a new Fetch. Other methods remain open by default. Explicit
abort resolves the action without retrying.

Retry behavior is Datastar-specific:

| Outcome | `auto` | `error` | `always` | `never` |
| --- | --- | --- | --- | --- |
| Clean EOF after status 200 | finish | finish | retry | finish |
| HTTP 4xx/5xx | finish | retry | retry | finish |
| HTTP 204 | finish | finish | finish | finish |
| Redirect response visible to code | finish | finish | finish | finish |
| Fetch/network/parser exception | retry | retry | retry | retry |
| Explicit or visibility abort | finish/reopen on visibility | same | same | same |

The last row exposes a stable-client quirk: `retry: never` does not suppress
exception retries. Retry delay starts at 1 second, grows exponentially to 30
seconds, and fails after 10 attempts unless configured otherwise. A valid SSE
`retry:` field changes the base delay used by subsequent retries.

**Hard design consequence:** a host-enforced maximum stream lifetime that ends
with clean EOF will not transparently reconnect under Datastar's default
`retry: auto`. The experiment must either avoid a default lifetime cutoff,
document `retry: always`, or establish a different explicit client contract.
It must not assume native `EventSource` reconnects on every EOF.

### Last event ID

The client implements event IDs itself. On an `id:` field it mutates the
headers used by that action's next retry or visibility reopen:

- non-empty `id` sets `last-event-id`;
- empty `id:` deletes the header;
- an event with no `id` leaves the previous header unchanged.

The cursor lasts only within one backend-action invocation. A later independent
`@get` starts with no retained ID. The server remains responsible for durable
cursor validation and replay.

**Specified by WHATWG, and stricter than the stable client parser:** an event
ID used in `Last-Event-ID` cannot contain NUL, LF, or CR. The Roc constructor
should reject all three even though the JavaScript parser only special-cases
the empty value.

## Stable client response contract

Only status 200 is body-dispatched. The client recognizes:

| Content type | Action |
| --- | --- |
| `text/event-stream` | incrementally parse Datastar SSE events |
| `text/html` | patch elements once |
| `application/json` | patch signals once |
| `text/javascript` | append and execute a script once |

HTML accepts `datastar-selector`, `datastar-mode`, `datastar-namespace`, and
`datastar-use-view-transition`. JSON accepts `datastar-only-if-missing`.
JavaScript accepts JSON-encoded `datastar-script-attributes`.

**Recommendation:** first-class support should expose ordinary finite HTML and
JSON response helpers as well as finite SSE. A one-patch response should not
pay for the stream subsystem. Raw JavaScript should be explicit and visibly
unsafe; `ExecuteScript` in the Go SDK is only a convenience that emits a
`datastar-patch-elements` event containing a script element.

### Datastar event vocabulary

The stable client has two wire event names:

- `datastar-patch-elements`;
- `datastar-patch-signals`.

Patch-elements data keys are:

- `selector`;
- `mode`: `outer` (default), `inner`, `remove`, `replace`, `prepend`, `append`,
  `before`, or `after`;
- `namespace`: `html` (default), `svg`, or `mathml`;
- `useViewTransition`: `false` by default;
- `viewTransitionSelector`, supported by client and Go SDK source but missing
  from the stable SDK config/golden suite;
- one or more `elements` lines, joined with LF.

Without a selector, `outer` and `replace` locate targets from top-level element
IDs (or html/head/body). Other modes require a selector. Remove needs no
elements payload.

Patch-signals data keys are `onlyIfMissing` (`false` by default) and one or
more `signals` lines. The joined signal string is parsed using Datastar's
JavaScript-like signal object parser; JSON emitted by typed server helpers is a
safe interoperable subset. JSON `null` removes signals.

The byte fixtures in [`fixtures`](fixtures/) cover default/all-option,
multiline, removal, script, multiple-event, comment, Unicode, and ID-clear
cases. The upstream canonical form uses LF and exactly one blank line between
events. Field order is semantically irrelevant to the client, but emitting one
canonical order makes fixtures and cross-SDK comparisons deterministic.

### Generic SSE parsing details

**Specified by WHATWG:** event streams are UTF-8; LF, CRLF, and CR are valid
line endings; comment lines begin with `:`; repeated data fields join with LF;
a blank line dispatches an event; an unterminated event at EOF is discarded;
`retry` is accepted only when it contains ASCII digits; and an empty `id:`
clears the retained ID.

**Observed stable-client differences:** its parser accepts any JavaScript
numeric conversion for `retry`, mutates ID state as soon as the ID line is
parsed, and invokes its message callback for blank records (which are ignored
because they have no `datastar` event name). Server output should use the
stricter standard form rather than depend on those quirks.

## Fetch versus EventSource

Datastar does not instantiate the browser `EventSource` API. Its bundled Fetch
parser is necessary because backend actions require methods other than GET,
request bodies, custom headers, explicit AbortControllers, non-SSE finite
responses, and custom retry policy.

Consequences for the server design:

- `Last-Event-ID` and reconnect are client code behavior, not automatic native
  EventSource behavior.
- `Accept-Encoding` is a browser-controlled forbidden request header. The
  application cannot force Brotli through Datastar action options.
- Fetch exposes a decoded `ReadableStream`; content coding is handled before
  bytes reach the SSE parser. The Fetch standard also permits the user agent to
  suspend network input when its decoded buffer reaches an implementation
  limit, which is compatible with transport backpressure.
- Same-origin credentials use Fetch defaults. Cross-origin Datastar requests
  with `Datastar-Request`, JSON content, or `Last-Event-ID` require the normal
  CORS preflight/response policy.
- A command-line Brotli decoder is not enough evidence. Browser integration
  must prove that each flushed encoded event reaches the Fetch reader before a
  later event exists.

## Official Go SDK experience

The idiomatic handler is short:

```go
func handler(w http.ResponseWriter, r *http.Request) {
    var signals Signals
    if err := datastar.ReadSignals(r, &signals); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    sse := datastar.NewSSE(w, r, datastar.WithCompression())
    if err := sse.PatchElements(render(signals)); err != nil {
        return
    }
}
```

Persistent handlers keep the Go handler goroutine and stack, wait on channels
or `r.Context().Done()`, and call the mutex-protected SSE writer. This is
excellent Go ergonomics, but it is not the architecture Roc should copy by
pinning one native execution thread per stream. The functional stream machine
must instead match the capability with similarly little route-level plumbing.

Go SDK conveniences worth matching in typed Roc form include element modes,
ID selectors, namespaces, view transitions, JSON signal encoding,
`onlyIfMissing`, event ID/retry options, templating adapters, and explicit
script/redirect helpers. Formatting helpers and Go-specific template
interfaces do not belong in the platform core.

`ReadSignals` is not a safety baseline: it reads the entire body without an
SDK limit. `MarshalAndPatchSignals` panics if JSON marshaling fails. The Roc
platform should retain its existing bounded-body and typed-error guarantees.

## Go wire and compression observations

Run the executable checks with:

```sh
cd research/datastar-parity/go-reference
go test -v ./...
```

The checks in [`reference_test.go`](go-reference/reference_test.go) establish:

1. **Observed:** `NewSSE` sets status 200 implicitly, `Content-Type:
   text/event-stream`, `Cache-Control: no-cache`, and `Connection: keep-alive`
   only for HTTP/1.x. It flushes headers immediately. It does not emit
   `X-Accel-Buffering`.
2. **Observed:** compression is opt-in through `WithCompression()`. Its default
   server order is Brotli, Zstandard, gzip, then deflate; Brotli defaults to
   quality 6 and automatic window selection.
3. **Observed:** encoding parsing strips parameters and compares bare tokens.
   Consequently `br;q=0` selects Brotli, wildcard `*` selects nothing, and
   server priority chooses Brotli even when gzip has a higher q-value. It does
   not model identity preference.
4. **Observed:** neither compressed nor identity responses emit `Vary:
   Accept-Encoding`.
5. **Observed:** `NewSSE` overwrites an existing `Cache-Control: private,
   no-transform` with `no-cache` and still compresses.
6. **Observed:** one Go `Send` appends LF to every field and then appends two
   more LF bytes. It therefore emits one extra LF beyond the stable client's
   official golden fixture. The extra blank record is harmless to this client,
   but is not canonical and must not be copied.
7. **Observed:** event type, ID, and caller-provided data lines are emitted
   without CR/LF/NUL validation, allowing field injection. The typed Roc API
   must reject this.
8. **Observed:** one compressor is retained and `Flush()` is called after every
   event, followed by `ResponseController.Flush()`. Both identity and Brotli
   deliver event one before the test server is allowed to produce event two.
9. **Observed:** the SDK stores the compressor as `io.Writer`, never calls its
   required `Close`, and exposes no finish method. A flushed prefix decodes,
   but normal handler return leaves the Brotli stream unfinished and prevents
   the dependency from returning the encoder to its pool.

Items 2–5 deliberately differ from the proposed automatic Brotli contract.
`basic-webserver` should reuse its RFC-aware negotiation, merge `Vary`, preserve
`no-transform`, finish on normal EOF, and drop without finishing on disconnect.
That is both safer and more standards-compliant than Go SDK parity.

## Preliminary measured Go baseline

The committed harness uses Go 1.26.5 on an AMD Ryzen 7 9700X, Linux x86-64,
with five 300 ms samples per case. Exact machine and tool data are in
[`environment.txt`](results/environment.txt), raw output in
[`go-microbench.txt`](results/go-microbench.txt), and medians/ranges in
[`go-microbench-summary.md`](results/go-microbench-summary.md).

These are in-process SDK framing/codec costs, not HTTP throughput:

| Case | Median time | Allocated | Allocs | Wire bytes |
| --- | ---: | ---: | ---: | ---: |
| finite identity, 256 B | 1.30 µs | 6.7 KiB | 26 | 305 |
| finite idiomatic Brotli q6/auto, 256 B | 774 µs | 8.29 MB | 182 | 95 unfinished |
| finite equivalent Brotli q4/w18, 256 B | 123 µs | 1.11 MB | 64 | 105 unfinished |
| persistent identity, 256 B | 151 ns/event | 544 B/event | 6 | 305/event |
| persistent idiomatic Brotli, 256 B | 2.86 µs/event | 631 B/event | 6 | 11/event after dictionary warmup |
| persistent equivalent Brotli q4/w18, 256 B | 2.81 µs/event | 558 B/event | 6 | 11/event after dictionary warmup |
| persistent identity, 4 KiB | 473 ns/event | 5.14 KiB/event | 6 | 4,145/event |
| persistent idiomatic Brotli, 4 KiB | 9.04 µs/event | 5.41 KiB/event | 6 | 13/event after dictionary warmup |
| persistent equivalent Brotli q4/w18, 4 KiB | 11.3 µs/event | 5.23 KiB/event | 6 | 13/event after dictionary warmup |

**Measured caveats:** payloads are intentionally highly repetitive to expose
cross-event dictionary value. Finite compressed output omits a required final
tail because that is the official SDK behavior. Persistent per-operation
figures exclude initial encoder construction and do not measure retained
encoder memory. No socket, HTTP/2, browser, proxy, slow reader, goroutine, RSS,
or tail-latency cost is included. These numbers are targets for a codec/framing
microbenchmark only, not evidence that the whole Roc server meets Go.

Notable target implications:

- Reusing one encoder is essential: constructing idiomatic q6 Brotli per event
  is roughly 774 µs and 8.3 MB of allocation for a 256-byte response, whereas a
  retained stream costs roughly 2.9 µs per repeated event after construction.
- Quality/window dominate startup memory and CPU. The q4/w18 comparison is
  roughly six times faster and allocates one seventh as much as the SDK default
  on a 256-byte finite response. The transport spike must measure retained
  state and choose parameters from scale evidence.
- The astonishing 11–13 byte repeated-event results are not representative of
  changing application data. The shared corpus needs realistic HTML/signal
  traces and incompressible cases before setting a compression-ratio gate.

## Match, improve, and deliberately differ

### Must match the pinned client

- All five action methods and stable JSON/form placement, especially DELETE.
- The four response content types and their response metadata.
- Both Datastar event types, every mode/namespace/option, multiline joining,
  removal behavior, signal null removal, and view-transition selector.
- Progressive dispatch after every logical event.
- Empty-ID clearing and durable-cursor access through `Last-Event-ID`.
- Visibility abort/reopen, explicit abort, retry modes, retry fields, clean EOF,
  and exception behavior in browser integration tests.
- Transparent browser decoding of negotiated Brotli.

### Should exceed the Go SDK

- RFC-correct q-values, wildcard, identity, `Vary`, and `no-transform` handling.
- Canonical two-LF framing rather than the extra blank record.
- Validated event names, IDs, retries, and data boundaries; no field injection.
- Bounded body parsing, event sizes, queues, encoder memory, and concurrency.
- Clean Brotli finish on normal EOF and prompt drop on disconnect.
- No per-stream worker thread, explicit backpressure, fair callback admission,
  typed saturation, and deterministic shutdown.
- Host heartbeats and proxy-safe defaults without waking Roc.

### Should deliberately differ

- Do not expose arbitrary concurrently callable writers. A stream has one
  serialized machine advance at a time.
- Do not copy Go's compressor strategy/options into route APIs. Use one measured
  server policy and the normal HTTP opt-out.
- Do not treat event IDs as host replay or exactly-once delivery.
- Do not implement Go template interfaces in `Datastar`; Roc packages render
  strings/elements before constructing typed events.
- Do not reproduce SDK panics or unchecked raw script helpers as defaults.

## Exact recommendations for `docs/datastar-experiment.md`

### Proposed application API

1. Expand `Datastar` finite helpers to cover plain `text/html` element patches
   and `application/json` signal patches. Keep multi-event finite SSE as a
   bounded ordinary response.
2. Pin all element modes, all namespaces, `viewTransitionSelector`, signal
   `onlyIfMissing`, null removal, event ID, and retry. Add an explicitly unsafe
   script helper only if realistic examples justify it.
3. Specify `read_signals!` against GET+DELETE query and POST+PUT+PATCH JSON body
   for `v1.0.2`. Form mode is normal form parsing and contains no Datastar
   signals.
4. Make `Datastar-Request` a typed convenience predicate only, never an auth or
   CSRF signal.
5. Preserve generic SSE `id` states `Absent`, `Set`, and `Clear`. Validate NUL,
   LF, and CR. Restrict retry to bounded non-negative integer milliseconds.

### HTTP, compression, and lifecycle

6. State that Datastar uses Fetch, and that the browser controls
   `Accept-Encoding` and incrementally decodes `Content-Encoding` before the
   event parser.
7. Keep automatic Brotli and identity, but explicitly call this a deliberate
   improvement over the Go SDK's opt-in, non-RFC negotiation. Merge
   `Cache-Control` rather than overwriting it; `no-transform` selects identity.
8. Require exactly one terminating blank line in canonical framing and a valid
   Brotli tail on normal close. Disconnect still drops the encoder without a
   tail.
9. Remove any assumption that a finite maximum stream lifetime transparently
   reconnects. Add a gate for clean EOF under each client retry mode before a
   default lifetime is chosen.
10. Keep `X-Accel-Buffering: no` as the candidate default. NGINX buffering is
    on by default and this response header disables it unless the proxy is
    configured to ignore it. Heartbeat interval must remain below the selected
    `proxy_read_timeout`, whose default is 60 seconds and is measured between
    upstream reads.

### Spike 0 and release matrix

11. Treat the fixtures and `go test -v ./...` as the initial Spike 0 evidence,
    but leave the browser gate open.
12. Add browser cases for every method/content mode, same-method+URL automatic
    cancellation, cleanup cancellation, explicit controller, hidden GET,
    open-when-hidden GET, all retry modes, clean EOF, abrupt reset, HTTP errors,
    204, ID set/retain/clear, and cross-origin preflight.
13. Run browser cases in at least Chromium, Firefox, and WebKit/Safari coverage
    available to CI. Brotli event one must be applied before event two exists.
14. Add a stable-tag upgrade procedure: update locks, regenerate/copy official
    fixtures, diff client Fetch/watcher source, and rerun the browser matrix.

### Performance gates

15. Compare both idiomatic Go q6/auto and semantic-equivalent q4/w18. Do not
    compare Roc q4/w18 only against the much heavier Go default and claim a
    runtime win.
16. Add retained encoder bytes per open stream and encoder construction cost to
    Spike 5/8. Per-event benchmarks hide startup and idle memory.
17. Use changing realistic patches, heartbeat-only streams, and incompressible
    maximum events in addition to repeated payloads.
18. Require end-to-end direct/proxy HTTP/1.1 and HTTP/2 load results before the
    meet-or-exceed-Go claim. The committed microbenchmark is only the lower
    codec/framing baseline.

## Remaining unknowns and next commands

The following gates remain open:

- real Chromium, Firefox, and WebKit progressive Brotli behavior;
- browser-to-host cancellation latency for visibility, explicit abort, and
  automatic replacement;
- HTTP/2 and proxy behavior of the reference server;
- Go goroutine/stack/RSS cost for 100, 1,000, and 10,000 idle streams;
- retained Brotli state for q6/auto versus q4/w18;
- realistic trace compression ratio and event-latency distribution;
- cross-origin CORS behavior with `Datastar-Request` and `Last-Event-ID`;
- whether the experiment should remain on stable `v1.0.2` or wait for the
  moving-main request-contract changes to ship.

Reproduction:

```sh
python3 research/datastar-parity/verify_fixtures.py
cd research/datastar-parity/go-reference
go test -v ./...
go test -run '^$' -bench 'BenchmarkOfficialSDK' -benchmem -benchtime=300ms -count=5 .
go run ./cmd/reference-server -coding idiomatic
go run ./cmd/reference-server -coding equivalent
```

The reference server provides `/finite`, `/progressive`, and `/persistent`.
The next end-to-end runner should drive the exact workload matrix from the
research program against those routes and the Rust/Roc prototype using the
same client process and payload corpus.
