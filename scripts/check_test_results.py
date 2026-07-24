#!/usr/bin/env python3
"""Verify that every CI target reported the same runtime case set."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()

    paths = sorted(args.directory.rglob("results-*.json"))
    if len(paths) < 2:
        raise SystemExit(f"Expected results from multiple targets, found {len(paths)}")

    expected_cases: set[tuple[str, str]] | None = None
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
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
        print(f"{path}: {len(identities)} cases accounted for")


if __name__ == "__main__":
    main()
