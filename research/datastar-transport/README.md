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

Performance and cross-implementation commands will be added only after the
bounded-body mechanics pass their focused tests.

