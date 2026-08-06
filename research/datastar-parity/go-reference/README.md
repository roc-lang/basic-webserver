# Official Go SDK reference harness

This module exercises `datastar-go v1.2.2` through its public API. It provides:

- executable observations for stable wire and compression behavior;
- a progressive-delivery test for identity and one persistent Brotli stream;
- finite and persistent event microbenchmarks at representative payload sizes;
- an ergonomic reference server with finite, progressive, and persistent routes.

Two Brotli baselines are intentionally separate:

- `brotli-idiomatic` calls the SDK's documented `WithCompression()` default;
- `brotli-equivalent-q4-w18` forces Brotli quality 4 and window 18 so another
  implementation can use identical codec parameters.

Run with Go 1.24 or newer:

```sh
go test ./...
go test -run '^$' -bench 'BenchmarkOfficialSDK' -benchmem -count 5 ./...
go run ./cmd/reference-server -coding idiomatic
```

The microbenchmarks measure SDK framing and compression, not socket, HTTP/2,
proxy, scheduler, or browser performance. The experiment's full comparison
matrix must use a shared external load generator against this server and the
Roc server. Do not claim end-to-end parity from these numbers.
