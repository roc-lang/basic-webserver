# Datastar transport feasibility spike

This disposable crate tests the bounded Hyper-body and streaming-Brotli
hypotheses in `docs/datastar-experiment.md`. It imports the repository's real
`src/compression.rs`, including the pinned Brotli crate and quality/window
configuration, but is not linked into the production host.

The research contract and evidence labels live in
`docs/research/datastar-research-program.md` on the coordinating experiment
branch. Results here must distinguish semantic-equivalence comparisons from
the official Go SDK's idiomatic defaults.

Run the correctness checks with:

```sh
cargo test --manifest-path research/datastar-transport/Cargo.toml --release
```

The performance comparison is intentionally compressor-focused; it does not
claim to close the real-listener, browser, proxy, or cross-target gates.

## Reproduce the recorded run

The committed measurements used Rust 1.97.1, checksum-verified Go 1.26.5,
Datastar Go v1.2.2, release builds, and logical CPU 2. The benchmark performs a
100-event warmup before seven recorded samples. Each sample processes about 64
MiB of preframed input through one persistent stream.

```sh
cargo build --manifest-path research/datastar-transport/Cargo.toml --release
taskset -c 2 research/datastar-transport/target/release/datastar-transport-spike benchmark 7
taskset -c 2 research/datastar-transport/target/release/datastar-transport-spike observe-bounds 100
taskset -c 2 research/datastar-transport/target/release/datastar-transport-spike memory 1000

cd research/datastar-transport/go
GOTOOLCHAIN=local /tmp/go1.26.5/bin/go test ./...
GOTOOLCHAIN=local /tmp/go1.26.5/bin/go build -trimpath -o /tmp/datastar-go-transport-reference .
taskset -c 2 /tmp/datastar-go-transport-reference benchmark 7
taskset -c 2 /tmp/datastar-go-transport-reference memory direct 1000
taskset -c 2 /tmp/datastar-go-transport-reference memory sdk-q4 1000
taskset -c 2 /tmp/datastar-go-transport-reference memory sdk-default 100
```

The Go toolchain archive was `go1.26.5.linux-amd64.tar.gz`, SHA-256
`5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053`.
The official SDK source was tag `v1.2.2`, commit
`60dc10ebdaad3207d71e4bd8c1f158e65bb4acb0`.

`datastar_event` deliberately reproduces the Go SDK v1.2.2 three-LF event
terminator for a byte-equivalent compressor comparison. It is not a canonical
Datastar fixture: the pinned client's golden fixture and WHATWG framing end an
event with two LFs. Production Roc framing should use the canonical form.

Raw results and the machine description are under [`results`](results). The
numbers are indicative single-host measurements, not a portable guarantee.
