from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import test, update_app_platform_urls


class SpecValidationTests(unittest.TestCase):
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
            ],
        )

    def test_platform_and_harness_targets_match(self) -> None:
        self.assertEqual(set(test.declared_targets()), set(test.TARGETS))

    def test_current_spec_covers_every_active_example(self) -> None:
        _, apps = test.load_spec()
        self.assertEqual({str(app["path"]) for app in apps}, test.active_sources())

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
