from __future__ import annotations

import unittest

from scripts import test


class SpecValidationTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
