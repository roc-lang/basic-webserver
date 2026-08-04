from __future__ import annotations

import contextlib
import io
import json
import socket
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

from scripts import test, update_app_platform_urls


class RawExchangeTests(unittest.TestCase):
    def test_raw_exchange_timeout_is_total_for_an_infinite_stream(self) -> None:
        listener = socket.socket()
        self.addCleanup(listener.close)
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]

        def stream_forever() -> None:
            connection, _address = listener.accept()
            with connection:
                connection.recv(1024)
                while True:
                    try:
                        connection.sendall(b"event: tick\n\n")
                    except OSError:
                        return
                    time.sleep(0.005)

        server = threading.Thread(target=stream_forever, daemon=True)
        server.start()
        started = time.monotonic()

        test.run_raw_exchange(
            port,
            {
                "data": "GET /events HTTP/1.1\r\nHost: localhost\r\n\r\n",
                "half_close": False,
                "timeout": 0.05,
                "expect_response_before_ms": {
                    "timeout_ms": 100,
                    "contains": "event: tick",
                },
                "response_contains": ["event: tick"],
            },
            "infinite stream",
        )

        self.assertLess(time.monotonic() - started, 0.5)
        server.join(timeout=0.5)
        self.assertFalse(server.is_alive())


class SpecValidationTests(unittest.TestCase):
    def test_local_bundle_rewrite_uses_a_copy(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            root = Path(raw_directory)
            source = root / "examples" / "example.roc"
            source.parent.mkdir()
            original = 'app [main] { pf: platform "https://example.invalid/old" }\n'
            source.write_text(original, encoding="utf-8")
            support = source.parent / "Support.roc"
            support.write_text("Support :: [].{}\n", encoding="utf-8")
            sibling_app = source.parent / "sibling.roc"
            sibling_app.write_text("app [main] {}\n", encoding="utf-8")

            with (
                mock.patch.object(test, "ROOT", root),
                mock.patch.object(test, "VALIDATION_ROOT", root / "target" / "spec"),
            ):
                rewritten = test.rewritten_app_source(
                    "examples/example.roc",
                    "http://127.0.0.1:1234/platform.tar.zst",
                )

            self.assertNotEqual(rewritten, source)
            self.assertEqual(source.read_text(encoding="utf-8"), original)
            self.assertIn(
                'platform "http://127.0.0.1:1234/platform.tar.zst"',
                rewritten.read_text(encoding="utf-8"),
            )
            self.assertEqual(
                (rewritten.parent / "Support.roc").read_text(encoding="utf-8"),
                "Support :: [].{}\n",
            )
            self.assertFalse((rewritten.parent / "sibling.roc").exists())

    def test_active_sources_excludes_local_type_modules(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            root = Path(raw_directory)
            examples = root / "examples"
            examples.mkdir()
            (examples / "app.roc").write_text(
                "## executable\napp [main] {}\n", encoding="utf-8"
            )
            (examples / "Component.roc").write_text(
                "Component :: [].{}\n", encoding="utf-8"
            )

            with mock.patch.object(test, "ROOT", root):
                self.assertEqual(test.active_sources(), {"examples/app.roc"})

    def test_startup_failure_case_cannot_send_requests(self) -> None:
        case = {
            "name": "invalid-startup",
            "expect_startup_failure": True,
            "requests": [{"method": "GET", "target": "/"}],
        }

        with self.assertRaisesRegex(
            test.TestFailure,
            "expect_startup_failure cannot be combined with requests",
        ):
            test.validate_case("examples/health.roc", case, set())

    def test_http2_request_headers_use_prior_knowledge_hpack(self) -> None:
        block = test.hpack_request_headers(
            8000,
            {"method": "GET", "target": "/fast"},
            b"",
            [],
        )

        self.assertEqual(block[:3], b"\x82\x86\x04")
        self.assertIn(b"/fast", block)
        self.assertIn(b"127.0.0.1:8000", block)

    def test_http2_authority_can_be_overridden_or_omitted(self) -> None:
        overridden = test.hpack_request_headers(
            8000,
            {"target": "/", "authority": "example.test:8443"},
            b"",
            [],
        )
        omitted = test.hpack_request_headers(
            8000,
            {"target": "/", "authority": None},
            b"",
            [("host", "fallback.test")],
        )

        self.assertIn(b"example.test:8443", overridden)
        self.assertNotIn(b"127.0.0.1:8000", overridden)
        self.assertNotIn(b"127.0.0.1:8000", omitted)
        self.assertIn(b"fallback.test", omitted)

    def test_repeated_http2_headers_use_dynamic_table_references(self) -> None:
        block = test.hpack_request_headers(
            8000,
            {"method": "GET", "target": "/"},
            b"",
            [("x-test", "repeated"), ("x-test", "repeated")],
        )

        self.assertEqual(block.count(b"repeated"), 1)
        self.assertEqual(block[-1], 0x80 | 62)

    def test_generated_request_header_values_are_bounded(self) -> None:
        _, headers = test.request_body(
            {
                "headers": [
                    {
                        "name": "x-test",
                        "value_repeat": "abc",
                        "value_chars": 8,
                    }
                ]
            }
        )

        self.assertEqual(headers, [("x-test", "abcabcab")])

    def test_http2_frame_encodes_the_wire_header(self) -> None:
        frame = test.http2_frame(
            test.HTTP2_FRAME_HEADERS,
            test.HTTP2_FLAG_END_HEADERS | test.HTTP2_FLAG_END_STREAM,
            3,
            b"abc",
        )

        self.assertEqual(frame, b"\x00\x00\x03\x01\x05\x00\x00\x00\x03abc")

    def test_http2_completion_order_must_cover_every_named_request(self) -> None:
        case = {
            "name": "multiplexed",
            "http2_requests": [{"name": "slow"}, {"name": "fast"}],
            "http2_completion_order": ["fast"],
        }

        with self.assertRaisesRegex(
            test.TestFailure, "must name every HTTP/2 request"
        ):
            test.validate_case("examples/sleep.roc", case, set())

    def test_startup_failure_cases_cannot_send_requests(self) -> None:
        case = {
            "name": "invalid-startup",
            "expect_startup_failure": True,
            "requests": [{"target": "/"}],
        }

        with self.assertRaisesRegex(
            test.TestFailure,
            "expect_startup_failure cannot be combined with requests",
        ):
            test.validate_case("examples/request-limits.roc", case, set())

    def test_persistent_request_repetition_is_bounded(self) -> None:
        case = {
            "name": "persistent",
            "persistent_requests": [{"target": "/"}],
            "persistent_repeat": 100_001,
        }

        with self.assertRaisesRegex(test.TestFailure, "persistent_repeat"):
            test.validate_case("examples/datastar/showcase.roc", case, set())

    def test_memcheck_log_requires_observed_allocations_and_no_errors(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            log = Path(raw_directory) / "memcheck.log"
            log.write_text(
                "total heap usage: 1,234 allocs, 1,234 frees, 99 bytes allocated\n"
                "ERROR SUMMARY: 0 errors from 0 contexts\n",
                encoding="utf-8",
            )
            test.validate_memcheck_log(log, "case")

            log.write_text(
                "total heap usage: 0 allocs, 0 frees, 0 bytes allocated\n"
                "ERROR SUMMARY: 0 errors from 0 contexts\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(test.TestFailure, "zero allocations"):
                test.validate_memcheck_log(log, "case")

            log.write_text(
                "total heap usage: 10 allocs, 9 frees, 99 bytes allocated\n"
                "ERROR SUMMARY: 1 errors from 1 contexts\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(test.TestFailure, "reported an error"):
                test.validate_memcheck_log(log, "case")

    def test_memcheck_command_keeps_tool_output_separate(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            temp = Path(raw_directory)
            args, log = test.process_command(
                Path("/tmp/app"), temp, memcheck=True
            )
            self.assertEqual(args[0:2], ["valgrind", "--tool=memcheck"])
            self.assertEqual(args[-1], "/tmp/app")
            self.assertIn(f"--log-file={temp / 'memcheck.log'}", args)
            self.assertEqual(log, temp / "memcheck.log")

    def test_platform_validation_formats_and_tests_the_platform(self) -> None:
        with mock.patch.object(test, "command") as run:
            test.validate_platform_sources("custom-roc")

        self.assertEqual(
            run.call_args_list,
            [
                mock.call(
                    "custom-roc", "fmt", "--check", test.ROOT / "platform"
                ),
                mock.call(
                    "custom-roc", "test", test.ROOT / "platform" / "main.roc"
                ),
                mock.call(
                    sys.executable,
                    test.ROOT / "scripts" / "test_datastar_markup_types.py",
                    "--roc",
                    "custom-roc",
                ),
            ],
        )

    def test_platform_and_harness_targets_match(self) -> None:
        self.assertEqual(set(test.declared_targets()), set(test.TARGETS))

    def test_current_spec_covers_every_active_example(self) -> None:
        _, apps = test.load_spec()
        self.assertEqual({str(app["path"]) for app in apps}, test.active_sources())

    def test_build_optimization_defaults_to_speed(self) -> None:
        _, apps = test.load_spec()
        by_path = {str(app["path"]): app for app in apps}

        self.assertEqual(
            test.build_optimization(by_path["examples/form-url-encoded.roc"]),
            "dev",
        )
        self.assertEqual(
            test.build_optimization(by_path["examples/hello-web.roc"]),
            "speed",
        )

    def test_skip_requires_a_reason(self) -> None:
        with self.assertRaisesRegex(test.TestFailure, "non-empty reason"):
            test.validate_skip(
                "case",
                {
                    "platforms": ["windows"],
                    "reason": "",
                    "issue": "https://github.com/roc-lang/basic-webserver/issues/1",
                },
            )

    def test_skip_requires_a_tracking_issue(self) -> None:
        with self.assertRaisesRegex(test.TestFailure, "tracking issue"):
            test.validate_skip(
                "case",
                {
                    "platforms": ["windows"],
                    "reason": "Temporarily unavailable",
                    "issue": "TODO",
                },
            )

    def test_test_skip_requires_a_reason_and_tracking_issue(self) -> None:
        test.validate_test_skip(
            "example",
            {
                "reason": "compiler issue",
                "issue": "https://github.com/roc-lang/roc/issues/10422",
            },
        )

        with self.assertRaisesRegex(test.TestFailure, "non-empty reason"):
            test.validate_test_skip(
                "example",
                {
                    "reason": "",
                    "issue": "https://github.com/roc-lang/roc/issues/10422",
                },
            )

        with self.assertRaisesRegex(test.TestFailure, "tracking issue"):
            test.validate_test_skip(
                "example",
                {"reason": "compiler issue", "issue": "not-an-issue"},
            )

    def test_platform_names_are_validated(self) -> None:
        with self.assertRaisesRegex(test.TestFailure, "skip.platforms"):
            test.validate_skip(
                "case",
                {
                    "platforms": ["plan9"],
                    "reason": "Temporarily unavailable",
                    "issue": "https://github.com/roc-lang/basic-webserver/issues/1",
                },
            )

    def test_nested_platform_expectations_are_rejected(self) -> None:
        with self.assertRaisesRegex(test.TestFailure, "platform-specific"):
            test.reject_platform_variants(
                "case",
                {"requests": [{"windows": {"expect_body": "different"}}]},
            )

    def test_text_normalization_does_not_apply_to_raw_bytes(self) -> None:
        self.assertEqual(test.normalize_text("a\r\nb\r"), "a\nb\n")
        self.assertNotEqual(b"a\r\nb", b"a\nb")

    def test_portable_text_bytes_ignore_checkout_line_endings(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            source = directory / "source.roc"
            source.write_bytes(b"first\r\nsecond\r")
            self.assertEqual(
                test.portable_file_bytes(source), b"first\nsecond\n"
            )
            database = directory / "database.db"
            database.write_bytes(b"first\r\nsecond\r")
            self.assertEqual(
                test.portable_file_bytes(database), b"first\r\nsecond\r"
            )

    def test_generated_fixtures_are_bounded_and_reproducible(self) -> None:
        case = {
            "fixtures": [
                {
                    "dest": "{temp}/text.txt",
                    "text": "hello",
                    "mtime_unix": 1_700_000_000,
                },
                {"dest": "{temp}/bytes.bin", "hex": "00ff10"},
                {
                    "dest": "{temp}/large.bin",
                    "repeat": "abc",
                    "size_bytes": 65_539,
                },
            ]
        }
        with tempfile.TemporaryDirectory() as raw_directory:
            temp = Path(raw_directory)
            test.install_fixtures(case, test.ROOT, temp)

            self.assertEqual((temp / "text.txt").read_text(), "hello")
            self.assertEqual(
                int((temp / "text.txt").stat().st_mtime), 1_700_000_000
            )
            self.assertEqual((temp / "bytes.bin").read_bytes(), b"\x00\xff\x10")
            large = (temp / "large.bin").read_bytes()
            self.assertEqual(len(large), 65_539)
            self.assertEqual(large[:9], b"abcabcabc")
            self.assertEqual(large[-4:], b"aabc")

    def test_generated_request_bodies_are_bounded_and_reproducible(self) -> None:
        body, headers = test.request_body(
            {
                "headers": {"Accept-Encoding": "gzip"},
                "body_repeat": "abc",
                "body_size_bytes": 10,
            }
        )

        self.assertEqual(body, b"abcabcabca")
        self.assertEqual(headers, [("Accept-Encoding", "gzip")])

    def test_artifact_manifest_round_trip(self) -> None:
        defaults, apps = test.load_spec()
        with tempfile.TemporaryDirectory() as raw_directory:
            artifact_dir = Path(raw_directory)
            binaries = {}
            for app in apps:
                if not test.stage_enabled(defaults, app, "build"):
                    continue
                source = str(app["path"])
                binary = test.output_path(
                    test.ROOT / source, "x64musl", artifact_dir
                )
                binary.parent.mkdir(parents=True, exist_ok=True)
                binary.write_bytes(b"binary")
                binaries[source] = binary
            test.write_manifest("x64musl", binaries, artifact_dir)
            loaded = test.load_artifact_binaries(
                "x64musl", artifact_dir, defaults, apps
            )
            self.assertEqual(loaded, binaries)

    def test_discovers_every_independent_build_for_a_target(self) -> None:
        defaults, apps = test.load_spec()
        with tempfile.TemporaryDirectory() as raw_directory:
            artifact_dir = Path(raw_directory)
            for build_id in ("linux-x64", "macos-arm64"):
                build_root = artifact_dir / build_id
                binaries = {}
                for app in apps:
                    if not test.stage_enabled(defaults, app, "build"):
                        continue
                    source = str(app["path"])
                    binary = test.output_path(
                        test.ROOT / source, "x64musl", build_root
                    )
                    binary.parent.mkdir(parents=True, exist_ok=True)
                    binary.write_bytes(build_id.encode())
                    binaries[source] = binary
                test.write_manifest(
                    "x64musl", binaries, build_root, build_id
                )

            builds = test.load_artifact_builds(
                "x64musl", artifact_dir, defaults, apps
            )
            self.assertEqual(
                [build_id for build_id, _ in builds],
                ["linux-x64", "macos-arm64"],
            )

    def test_artifact_manifest_rejects_another_spec(self) -> None:
        defaults, apps = test.load_spec()
        with tempfile.TemporaryDirectory() as raw_directory:
            artifact_dir = Path(raw_directory)
            target_dir = artifact_dir / "x64musl"
            target_dir.mkdir()
            manifest = {
                "target": "x64musl",
                "spec_sha256": "stale",
                "examples_sha256": test.examples_hash(),
                "binaries": {},
            }
            (target_dir / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(test.TestFailure, "different test spec"):
                test.load_artifact_binaries(
                    "x64musl", artifact_dir, defaults, apps
                )

    def test_compare_results_requires_every_target(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            for target, platform_name in test.TARGET_PLATFORMS.items():
                target_dir = directory / target
                target_dir.mkdir()
                (target_dir / f"results-{target}.json").write_text(
                    json.dumps(
                        {
                            "target": target,
                            "platform": platform_name,
                            "cases": [
                                {
                                    "app": "examples/hello-web.roc",
                                    "case": "semantic-http",
                                    "status": "passed",
                                }
                            ],
                        }
                    ),
                    encoding="utf-8",
                )

            with contextlib.redirect_stdout(io.StringIO()):
                test.compare_results(directory)

            (directory / "x64win" / "results-x64win.json").unlink()
            with self.assertRaisesRegex(test.TestFailure, "Missing target results"):
                with contextlib.redirect_stdout(io.StringIO()):
                    test.compare_results(directory)

    def test_compare_results_allows_target_specific_compiler_hosts(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            for target, platform_name in test.TARGET_PLATFORMS.items():
                builders = (
                    ("linux-x64", "macos-arm64")
                    if target != "x64win"
                    else ("linux-x64",)
                )
                for build_id in builders:
                    path = directory / target / build_id
                    path.mkdir(parents=True)
                    (path / f"results-{target}-{build_id}.json").write_text(
                        json.dumps(
                            {
                                "target": target,
                                "platform": platform_name,
                                "build_id": build_id,
                                "cases": [
                                    {
                                        "app": "examples/hello-web.roc",
                                        "case": "semantic-http",
                                        "status": "passed",
                                    }
                                ],
                            }
                        ),
                        encoding="utf-8",
                    )

            with contextlib.redirect_stdout(io.StringIO()):
                test.compare_results(directory)

    def test_release_platform_url_uses_prepared_bundle_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            manifest = Path(raw_directory) / "release-bundles.json"
            manifest.write_text(
                json.dumps([{"artifact_file": "basic-webserver.tar.zst"}]),
                encoding="utf-8",
            )
            self.assertEqual(
                update_app_platform_urls.release_platform_url(
                    manifest,
                    "1.2.3",
                    "roc-lang/basic-webserver",
                ),
                "https://github.com/roc-lang/basic-webserver/releases/"
                "download/1.2.3/basic-webserver.tar.zst",
            )


if __name__ == "__main__":
    unittest.main()
