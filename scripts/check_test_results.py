#!/usr/bin/env python3
"""Verify that every CI target reported the same runtime case set."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGET_PLATFORMS = {
    "x64mac": "darwin",
    "arm64mac": "darwin",
    "x64musl": "linux",
    "arm64musl": "linux",
    "x64win": "windows",
}


def declared_targets() -> set[str]:
    source = (ROOT / "platform" / "main.roc").read_text(encoding="utf-8")
    match = re.search(r"(?ms)^\s*targets:\s*\{(.*?)^\s*\}", source)
    if match is None:
        raise SystemExit("platform/main.roc: targets block was not found")
    return set(
        re.findall(r"(?m)^\s*([A-Za-z0-9_]+):\s*\{\s*inputs:", match.group(1))
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()

    paths = sorted(args.directory.rglob("results-*.json"))
    expected_targets = declared_targets()
    if expected_targets != set(TARGET_PLATFORMS):
        raise SystemExit(
            "Platform/result target mismatch; "
            f"platform={sorted(expected_targets)}, "
            f"results={sorted(TARGET_PLATFORMS)}"
        )

    expected_cases: set[tuple[str, str]] | None = None
    actual_targets: set[str] = set()
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        target = data.get("target")
        if target not in expected_targets:
            raise SystemExit(f"{path}: unknown target {target!r}")
        if target in actual_targets:
            raise SystemExit(f"{path}: duplicate results for {target}")
        actual_targets.add(target)
        if data.get("platform") != TARGET_PLATFORMS[target]:
            raise SystemExit(
                f"{path}: {target} ran on {data.get('platform')!r}, "
                f"expected {TARGET_PLATFORMS[target]!r}"
            )
        cases = data.get("cases")
        if not isinstance(cases, list):
            raise SystemExit(f"{path}: cases must be an array")
        identities: set[tuple[str, str]] = set()
        for case in cases:
            if not isinstance(case, dict):
                raise SystemExit(f"{path}: invalid case result")
            identity = (str(case.get("app")), str(case.get("case")))
            if identity in identities:
                raise SystemExit(f"{path}: duplicate result for {identity}")
            identities.add(identity)
            status = case.get("status")
            if status not in ("passed", "skipped"):
                raise SystemExit(f"{path}: {identity} has status {status!r}")
            if status == "skipped" and (
                not case.get("reason") or not case.get("issue")
            ):
                raise SystemExit(f"{path}: {identity} has an unexplained skip")
        if expected_cases is None:
            expected_cases = identities
        elif identities != expected_cases:
            raise SystemExit(
                f"{path}: runtime case mismatch; "
                f"missing={sorted(expected_cases - identities)}, "
                f"extra={sorted(identities - expected_cases)}"
            )
        print(f"{path}: {target} accounted for {len(identities)} cases")

    if actual_targets != expected_targets:
        raise SystemExit(
            f"Missing target results: {sorted(expected_targets - actual_targets)}"
        )


if __name__ == "__main__":
    main()
