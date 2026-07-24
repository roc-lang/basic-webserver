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
./build.sh                  # native target
./build.sh --target TARGET  # one specific target
./build.sh --all            # targets buildable from this host OS
```

Check + build every active example and test, plus a server smoke test:
```
./ci/all_tests.sh
```

Regenerate the committed Rust glue after changing `platform/main.roc`'s
`hosted`/`provides` blocks (needs a roc source checkout for `RustGlue.roc`):
```
ROC_SRC=/path/to/roc ./ci/regenerate_glue.sh          # write
ROC_SRC=/path/to/roc ./ci/regenerate_glue.sh --check  # fail if stale
```

# Tests

Note that if something is tested in ./examples, it may not have another test in ./tests.

Build an individual example or test (the server binary lands in the repo root):
```
roc build examples/hello-web.roc
```

Files with a `.todoroc` extension are intentionally skipped migration backlog.
Active `.roc` examples and tests should pass `./ci/all_tests.sh`.

# Style

- Prefer simple solutions.
- Try to achieve a single source of truth when sensible.
