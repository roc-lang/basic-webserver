# Design

- Read `design.md` before making code changes. It is the authoritative,
  forward-looking reference for the platform's desired architecture, scope,
  ownership boundaries, and invariants.
- The current implementation may differ from `design.md`. Move the
  implementation toward the design; do not treat existing code as evidence
  that a conflicting architecture is intended.
- Evaluate changes against the goals and non-goals in `design.md`. If requested
  work conflicts with them, identify the conflict explicitly rather than
  silently adding a workaround or expanding the platform's scope.
- Do not update `design.md` merely to justify an implementation decision. It
  should change only when new information invalidates an assumption, exposes a
  conflict between its goals, or the desired architecture or scope is
  deliberately changed.
- Keep implementation plans, migration status, and temporary constraints out
  of `design.md`. It records enduring WHAT and WHY; implementation-specific HOW
  belongs in code, focused documentation, issues, or pull requests.

# General Info

basic-webserver is a Roc platform:

Every Roc application has exactly one platform. That platform provides all the I/O primitives that the application can use; Roc's standard library provides no I/O operations, and the only way for a Roc application to execute functions in other languages is if the platform offers a way to do that.

Applications only interact with the Roc API portion of a platform, but there is also a host portion (written in a different language) that works behind the scenes. The host determines how the program starts, how memory is allocated and deallocated, and how I/O primitives are implemented.

basic-webserver is implemented in Rust and Roc.

# Compiler

This platform targets the new Zig-based Roc compiler. Use a `roc` from your PATH
(build it from a roc source checkout with `zig build roc`). The old Rust-based
compiler is no longer supported.

# Useful Commands

Build the host static library for the native target (writes `libhost.a` or
`host.lib` under `platform/targets/<target>/`):
```
python scripts/build.py                  # native target
python scripts/build.py --target TARGET  # one specific target
python scripts/build.py --all            # targets buildable from this host OS
```

Format, check, test, build, and run every active example through the
cross-platform HTTP specification suite:
```
python scripts/test.py
```

Release validation bundles the platform once. Five compiler-host jobs consume
that bundle and each cross-build every target; five native runner jobs then
execute every independently built artifact set for their target:
```
python scripts/test.py --operation validate
python scripts/test_bundle.py --operation build-all --bundle-path BUNDLE --build-id linux-x64 --artifact-dir dist/example-binaries
python scripts/test.py --operation run --target x64musl --artifact-dir dist/example-binaries
```

Pin a different Roc nightly in `.roc-version` and every example manifest
(`--check` fails when they disagree, and runs as part of `test.py --operation
validate`):
```
python scripts/update_roc_version.py nightly-2026-08-13-2fdd90e
python scripts/update_roc_version.py --check
```

Regenerate the committed Rust glue after changing `platform/main.roc`'s
`hosted`/`provides` blocks (needs a roc source checkout for `RustGlue.roc`):
```
ROC_SRC=/path/to/roc python scripts/regenerate_glue.py          # write
ROC_SRC=/path/to/roc python scripts/regenerate_glue.py --check  # fail if stale
```

# Tests

Runtime coverage lives in `scripts/test_spec.json`. Every active
`examples/*.roc` application must have exactly one spec entry, and normal
server cases must exercise the real HTTP listener. Keep examples realistic:
add cases to an existing example or add a useful example rather than creating
test-only Roc applications.

Platform-specific skips are exceptional. Every skip must include both a
concrete reason and a GitHub tracking issue URL; the spec validator rejects
incomplete skips and platform-specific expected results.

Build an individual example (the server binary lands in the repo root):
```
roc build examples/hello-web.roc
```

Files with a `.todoroc` extension are intentionally skipped migration backlog.
Active `.roc` examples should pass `python scripts/test.py` on every supported OS.

# Style

- Prefer simple solutions.
- Try to achieve a single source of truth when sensible.
- Keep repository automation in `scripts/` and write it in portable Python.
  Extend an existing entrypoint when the responsibility fits; add a script only
  when it owns a distinct reusable workflow.
