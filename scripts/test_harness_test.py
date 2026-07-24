from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts import test


class SpecValidationTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
