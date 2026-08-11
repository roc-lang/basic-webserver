# Contributing

Thanks for helping improve `basic-webserver`. Questions and early design
discussions are welcome in the [Roc Zulip chat](https://roc.zulipchat.com).

## Before making a change

Read [`design.md`](design.md) first. It is the authoritative description of the
platform's intended architecture, ownership boundaries, supported scope, and
non-goals. The implementation is still moving toward that design, so existing
code is not evidence that a conflicting architecture is intentional.

Keep application policy in Roc, durable mutable state in SQLite or an external
service, and bounded transport or operating-system resources in typed host
subsystems. If a request conflicts with the design, call out the conflict
instead of adding a workaround or silently expanding the platform's scope.

`design.md` records enduring what and why. Put implementation plans, migration
status, and temporary constraints in code, focused documentation, issues, or
pull requests.

Prefer simple solutions and a single source of truth where practical. Keep
repository automation in `scripts/` and write it in portable Python; extend an
existing entry point when the responsibility fits, and add a new script only
for a distinct reusable workflow.

## Prerequisites

- A recent Zig-based `roc` compiler on `PATH`. Build it from a Roc source
  checkout with `zig build roc`. The old Rust-based compiler is unsupported.
- The Rust toolchain declared in [`rust-toolchain.toml`](rust-toolchain.toml).
  Rustup selects it automatically.
- Python 3. Repository automation uses only the Python standard library.
- Native build tools for your operating system. Windows host builds require
  MSVC and the Windows SDK.

The exact Roc nightly used for development, CI, and releases is recorded in
[`.roc-version`](.roc-version). The CI action in
[`.github/actions/setup-roc`](.github/actions/setup-roc/action.yml) installs
that version. A separate scheduled workflow checks compatibility with the
latest nightly without changing the release pin.

## Build and run locally

Build the native host library:

```sh
python scripts/build.py
```

Then run an example:

```sh
roc examples/hello-web.roc
```

The server listens on <http://127.0.0.1:8000> by default. Build one explicit
target with `python scripts/build.py --target TARGET`, or every target
buildable from the current host with `python scripts/build.py --all`. Linux
builds the two musl targets; macOS builds the macOS and musl targets. The
`x64win` host inputs must be built on Windows.

## Verify a change

The normal local checks are:

```sh
cargo fmt --all -- --check
cargo test --locked
python scripts/test.py
```

Run `python scripts/build.py` first whenever the Rust host has changed or the
native host library is absent.

`scripts/test.py` validates its own harness, formats and checks Roc sources,
runs Roc tests, builds every active `examples/*.roc` application, and executes
the cases in [`scripts/test_spec.json`](scripts/test_spec.json). Normal server
cases use the real HTTP listener, including HTTP/2 coverage. The runner uses
only Python's standard library and applies the same expectations on Linux,
macOS, and Windows.

Files ending in `.todoroc` are intentionally skipped migration backlog.
Active `.roc` examples must pass the suite on every supported operating system.

For a focused application build after building the host:

```sh
roc build examples/hello-web.roc
```

CI also checks every Linux example under Valgrind Memcheck. On x86-64 Linux
with Valgrind installed, run the same lane with:

```sh
python scripts/test.py --operation memcheck
```

## Add or change examples

Keep examples realistic. Prefer adding a case to an existing useful example,
or add a new example that demonstrates a real platform use case instead of a
test-only Roc application.

Every active `examples/*.roc` application must have exactly one entry in
`scripts/test_spec.json`. Platform-specific skips are exceptional: each skip
must include a concrete reason and a GitHub tracking issue URL. The validator
rejects platform-specific expected results.

## Generated Rust glue

Changes to the `hosted` or `provides` blocks in `platform/main.roc` require
regenerating `src/roc_platform_abi.rs`. The compiler and `RustGlue.roc` must
come from the matching revision recorded in `scripts/regenerate_glue.py`.

```sh
ROC_SRC=/path/to/roc python scripts/regenerate_glue.py
ROC_SRC=/path/to/roc python scripts/regenerate_glue.py --check
```

`ROC_GLUE_SPEC=/path/to/RustGlue.roc` can be used instead of `ROC_SRC`.

## Generate API documentation

Generate and serve the same platform API documentation published for `main`:

```sh
roc docs platform/main.roc --serve
```

Open the local URL printed by Roc. The default output directory without
`--serve` is `generated-docs/`.

Generated documentation is not committed. Each release attaches a `docs.tar.gz`
asset holding the documentation for that version, and the published site is
rebuilt from those assets plus freshly generated `main` documentation:

```sh
python scripts/restore_release_docs.py temp_docs
```

This needs an authenticated GitHub CLI (`gh auth login`).

The `www` directory holds documentation for releases up to 0.16.0, which
predate the release asset and cannot be changed retroactively. It is copied
into the published site alongside the restored archives, and is scheduled for
deletion once 0.20.0 is released.

## Benchmarking

Use the unified benchmark entrypoint for substituted-transport server invariants,
allocation reports, real HTTP/SSE/SQLite load, process measurements, and
before/after comparisons:

```sh
python scripts/benchmark.py check
python scripts/benchmark.py measure \
  --suite http \
  --label before \
  --output target/benchmarks/before.jsonl
```

See [docs/benchmarking.md](docs/benchmarking.md) for the real-versus-simulated
evidence boundary, thousand-stream SSE runs, scenario controls, recorded
metrics, and comparison workflow. Local timing and memory values are indicative
and are never CI thresholds.

## Release validation

Source validation without building runtime artifacts is available separately:

```sh
python scripts/test.py --operation validate
```

Release CI builds all target host inputs, creates one platform bundle, has each
compiler host cross-build every target from that bundle, and runs every
independently produced artifact set on its native target.

After all declared target inputs have been assembled under `platform/targets`,
create a release-format package with:

```sh
python scripts/bundle.py --output-dir dist
```

The bundler validates target completeness and Roc's transitive dependency size
limit, then includes the required notices and exact Rust dependency licenses.
The release workflow assembles Windows, macOS, and Linux inputs before invoking
it.
