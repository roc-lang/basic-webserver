# TODO

Release-readiness backlog for the Zig compiler migration PR.

## Before Publishing

- [ ] Get GitHub CI green for [PR #163](https://github.com/roc-lang/basic-webserver/pull/163).
  - Rust is bumped to `1.85.0` so the resolved dependency graph can build Edition 2024 crates.
  - CI now has per-target coverage for Linux musl, macOS, and Windows host libraries.
  - Confirm the workflow is green after the next push.

- [x] Decide and validate release target support.
  - `platform/main.roc` currently advertises `x64mac`, `arm64mac`, `x64musl`, `arm64musl`, `x64win`, and `arm64win`.
  - Decision: keep all six targets for the release.
  - CI runs full Roc app tests for `x64musl`, `arm64musl`, `x64mac`, `arm64mac`, and `x64win`.
  - CI validates the `arm64win` Rust host library, but skips Roc app tests because `roc-lang/setup-roc` does not publish a Windows arm64 compiler binary yet.
  - Host libraries are intentionally ignored and must be rebuilt before packaging with `./build.sh --target <target>` or `./build.sh --all` on the appropriate host OS.

- [x] Run a docs pass before tagging.
  - README version links now point at `0.13.1`, `0.13.0`, and `main`.
  - Packaged-release wording now uses `.tar.zst`.
  - Removed stale Linux `--linker=legacy` guidance now that [roc#3609](https://github.com/roc-lang/roc/issues/3609) is closed.
  - Updated `AGENTS.md` so migrated modules are no longer described as skipped `.todoroc` work.
  - `./ci/all_tests.sh` now checks, tests, and builds the README example: [#43](https://github.com/roc-lang/basic-webserver/issues/43).

- [x] Decide what to do with public JSON decode stubs.
  - `Http.get!` and `Http.body_json` now decode through built-in `Json.parse`.
  - JSON parser failures are exposed as `JsonErr(_)`.

- [x] Decide what to do with remaining `.todoroc` files.
  - Ported `sleep`, buffered file reading, multipart upload, todos, Cmd, Dir, Sqlite, UTC, and issue 104 coverage to active `.roc` files.
  - Moved issue 154 into an active `MultipartFormData` expect.
  - Deleted obsolete `platform/EnvDecoding.todoroc`, `platform/InternalDateTime.todoroc`, and `platform/Tcp.todoroc`.
  - `./ci/all_tests.sh` now fails if any `.todoroc` files are present: [#109](https://github.com/roc-lang/basic-webserver/issues/109).

- [ ] Triage the GitHub Dependabot alert before tagging.
  - GitHub reports one moderate vulnerability on the default branch: <https://github.com/roc-lang/basic-webserver/security/dependabot/4>

- [x] Return `Path.Path` from `Env.cwd!`, `Env.exe_path!`, and `Env.temp_dir!`.
  - `cwd!` and `exe_path!` now return byte-preserving `Path.Path` values from Unix bytes or Windows UTF-16 code units.
  - `temp_dir!` now returns `Path.Path` through the platform raw-path representation.
  - The public API keeps open error rows; hosted functions keep closed rows for the host boundary.

- [ ] Revisit the `Tcp.read_line!` implementation once [roc#9826](https://github.com/roc-lang/roc/issues/9826) is fixed.
  - The current implementation avoids `?` for a single-variant error union because that path currently crashes.

- [ ] Review Sqlite safety and API details.
  - Investigate SQL injection protection: [#119](https://github.com/roc-lang/basic-webserver/issues/119)
  - Compare against the more mature sibling implementation in `../basic-cli`.
  - Consider transaction wrappers and query/decoder ergonomics in the updated `examples/todos.roc`.

## Out of Scope for This Upgrade PR

- Performance work such as request/response allocation reductions: [#23](https://github.com/roc-lang/basic-webserver/issues/23)
- Future platform features such as WebSockets [#129](https://github.com/roc-lang/basic-webserver/issues/129), Server-Sent Events [#97](https://github.com/roc-lang/basic-webserver/issues/97), background queues [#108](https://github.com/roc-lang/basic-webserver/issues/108), dotenv [#73](https://github.com/roc-lang/basic-webserver/issues/73), and state-change examples [#142](https://github.com/roc-lang/basic-webserver/issues/142)
- Old issues that should be re-triaged separately after the migration lands, such as [#9](https://github.com/roc-lang/basic-webserver/issues/9), [#74](https://github.com/roc-lang/basic-webserver/issues/74), [#81](https://github.com/roc-lang/basic-webserver/issues/81), and [#85](https://github.com/roc-lang/basic-webserver/issues/85)
