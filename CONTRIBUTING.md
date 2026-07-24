# Contributing

## Code of Conduct

We are committed to providing a friendly, safe and welcoming environment for all. Make sure to take a look at the Code of Conduct!

## Tips

AGENTS.md is the place to find common commands and useful info. Handy for humans and AI agents.

## Verification

Use a recent Zig-based `roc` compiler on `PATH`, then run:

```sh
python scripts/build.py
python scripts/test.py
```

The test driver checks, tests, builds, and exercises every active `.roc`
example and test, including a web-server smoke test. Files ending in
`.todoroc` are migration backlog and cause the release check to fail.

Build a specific host target with `python scripts/build.py --target TARGET`. The five
release targets are `x64mac`, `arm64mac`, `x64musl`, `arm64musl`, and
`x64win`. Windows inputs must be built on Windows. Release CI assembles all
five targets and verifies the resulting bundle on macOS, Linux, and Windows.

## Release packages

After all target inputs exist under `platform/targets`, create the same package
used by release CI with:

```sh
python scripts/bundle.py --output-dir dist
```

The bundler fails if any declared target input is missing or the unpacked
platform exceeds Roc's 100 MiB transitive dependency limit. Linux host
archives are stripped by the build script to stay below that limit. It also
includes the committed musl/libunwind notices and generates complete Rust
dependency license texts from the exact packages in `Cargo.lock`.

Release follow-up pull requests commit versioned documentation under `www/`.
The shared `roc-lang/release-package` actions snapshot, index, validate, and
preserve those versions; Pages deployments add a freshly generated `/main`.

## How to generate docs?

You can generate the documentation locally and then start a web server to host your files.

```bash
roc docs examples/hello-web.roc --serve
```

Open the printed local URL in your browser.
