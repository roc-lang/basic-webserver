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

- [ ] Run a docs pass before tagging.
  - Update README release URLs, package extension wording (`tar.zst`, not `tar.br`), and version links.
  - Remove or update the Linux `--linker=legacy` warning now that [roc#3609](https://github.com/roc-lang/roc/issues/3609) is closed.
  - Update `AGENTS.md`; it still says Sqlite, Tcp, Url, MultipartFormData, and outbound HTTP are skipped `.todoroc` work.
  - Add or update CI coverage for the README example: [#43](https://github.com/roc-lang/basic-webserver/issues/43).

- [ ] Decide what to do with public JSON decode stubs.
  - `Http.get!` and `Http.body_json` currently return `JsonDecodeNotMigrated`.
  - Implement these using the built-in `Json` support.

- [ ] Decide what to do with remaining `.todoroc` files.
  - Candidates to port, delete as obsolete, or explicitly document as deferred:
    - `examples/sleep.todoroc`, `platform/Sleep.todoroc`
    - `examples/file-read-buffered.todoroc`
    - `examples/form-file-upload.todoroc`
    - `examples/todos.todoroc`
    - `tests/cmd-test.todoroc`, `tests/dir-test.todoroc`
    - `tests/sqlite-test.todoroc`, `tests/utc.todoroc`
    - `tests/issue_104.todoroc`, `tests/issue_154.todoroc`
    - `platform/EnvDecoding.todoroc`, `platform/InternalDateTime.todoroc`, `platform/Tcp.todoroc`
  - Add a CI check so skipped examples/tests are intentional and visible: [#109](https://github.com/roc-lang/basic-webserver/issues/109).

- [ ] Triage the GitHub Dependabot alert before tagging.
  - GitHub reports one moderate vulnerability on the default branch: <https://github.com/roc-lang/basic-webserver/security/dependabot/4>

- [ ] Return `Path.Path` from `Env.cwd!`, `Env.exe_path!`, and `Env.temp_dir!`.
  - Currently blocked by upstream Roc issue [roc#9963](https://github.com/roc-lang/roc/issues/9963).
  - Re-test after the latest API refactors and implement if the current compiler/runtime supports it.

- [ ] Revisit the `Tcp.read_line!` implementation once [roc#9826](https://github.com/roc-lang/roc/issues/9826) is fixed.
  - The current implementation avoids `?` for a single-variant error union because that path currently crashes.

- [ ] Review Sqlite safety and API details.
  - Investigate SQL injection protection: [#119](https://github.com/roc-lang/basic-webserver/issues/119)
  - Compare against the more mature sibling implementation in `../basic-cli`.
  - Consider transaction wrappers and query/decoder ergonomics from the TODOs in `examples/todos.todoroc`.

## Out of Scope for This Upgrade PR

- Performance work such as request/response allocation reductions: [#23](https://github.com/roc-lang/basic-webserver/issues/23)
- Future platform features such as WebSockets [#129](https://github.com/roc-lang/basic-webserver/issues/129), Server-Sent Events [#97](https://github.com/roc-lang/basic-webserver/issues/97), background queues [#108](https://github.com/roc-lang/basic-webserver/issues/108), dotenv [#73](https://github.com/roc-lang/basic-webserver/issues/73), and state-change examples [#142](https://github.com/roc-lang/basic-webserver/issues/142)
- Old issues that should be re-triaged separately after the migration lands, such as [#9](https://github.com/roc-lang/basic-webserver/issues/9), [#74](https://github.com/roc-lang/basic-webserver/issues/74), [#81](https://github.com/roc-lang/basic-webserver/issues/81), and [#85](https://github.com/roc-lang/basic-webserver/issues/85)
