#!/usr/bin/env python3
"""Pin the Roc nightly used by this repository and by every example manifest."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROC_VERSION_FILE = ROOT / ".roc-version"
EXAMPLES = ROOT / "examples"
NIGHTLY_TAG = re.compile(
    r"^nightly-[0-9]{4}-(?:[A-Za-z]+|[0-9]{2})-[0-9]{2}-[0-9a-f]{7}$"
)
APP_HEADER = re.compile(r"(?ms)^app\s+\[[^\]]*\]\s*\{\n(?P<body>.*?)^\}")
ROC_PIN = re.compile(r'(?m)^[ \t]*roc:\s*"(?P<version>[^"]*)",?[ \t]*$')


def pinned_version() -> str:
    tag = ROC_VERSION_FILE.read_text(encoding="utf-8").strip()
    if NIGHTLY_TAG.fullmatch(tag) is None:
        raise SystemExit(f"Invalid Roc nightly tag in {ROC_VERSION_FILE}: {tag!r}")
    return tag


def app_manifests() -> list[Path]:
    manifests = [
        path
        for path in sorted(EXAMPLES.rglob("*.roc"))
        if APP_HEADER.search(path.read_text(encoding="utf-8")) is not None
    ]
    if not manifests:
        raise SystemExit(f"No Roc apps found under {EXAMPLES}")
    return manifests


def write_text(path: Path, text: str) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def display_path(path: Path) -> str:
    return str(path.relative_to(ROOT))


def pinned_in(source: str, path: Path) -> str | None:
    """Return the Roc version pinned by an app header, or None when unpinned."""
    header = APP_HEADER.search(source)
    if header is None:
        raise SystemExit(f"{display_path(path)}: app header was not found")
    match = ROC_PIN.search(header.group("body"))
    return None if match is None else match.group("version")


def rewrite_header(source: str, path: Path, version: str) -> str:
    header = APP_HEADER.search(source)
    if header is None:
        raise SystemExit(f"{display_path(path)}: app header was not found")

    body = header.group("body")
    if ROC_PIN.search(body) is not None:
        updated = ROC_PIN.sub(lambda match: f'\troc: "{version}",', body, count=1)
    else:
        entries = body.rstrip("\n").split("\n")
        if not entries[-1].rstrip().endswith(","):
            entries[-1] = entries[-1].rstrip() + ","
        entries.append(f'\troc: "{version}",')
        updated = "\n".join(entries) + "\n"

    return source[: header.start("body")] + updated + source[header.end("body") :]


def update(version: str) -> None:
    if NIGHTLY_TAG.fullmatch(version) is None:
        raise SystemExit(
            "Expected a nightly release tag like nightly-2026-08-13-2fdd90e, "
            f"got: {version}"
        )

    write_text(ROC_VERSION_FILE, f"{version}\n")

    updated = []
    for path in app_manifests():
        source = path.read_text(encoding="utf-8")
        rewritten = rewrite_header(source, path, version)
        if rewritten != source:
            write_text(path, rewritten)
            updated.append(path)

    for path in updated:
        print(f"updated {display_path(path)}")
    print(f"Pinned Roc version updated to {version}.")


def check() -> None:
    version = pinned_version()
    stale = []
    for path in app_manifests():
        found = pinned_in(path.read_text(encoding="utf-8"), path)
        if found != version:
            stale.append((path, found))

    if stale:
        for path, found in stale:
            actual = "no roc version" if found is None else found
            print(f"{display_path(path)}: pins {actual}, expected {version}")
        raise SystemExit(
            f"{len(stale)} example manifest(s) do not pin the Roc version in "
            f"{display_path(ROC_VERSION_FILE)}. "
            "Run: python scripts/update_roc_version.py $(cat .roc-version)"
        )

    print(f"All example manifests pin Roc {version}.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "version",
        nargs="?",
        help="Roc nightly tag to pin, for example nightly-2026-08-13-2fdd90e",
    )
    group.add_argument(
        "--check",
        action="store_true",
        help="Fail when an example manifest does not pin the version in .roc-version",
    )
    args = parser.parse_args()

    if args.check:
        check()
    else:
        update(args.version)


if __name__ == "__main__":
    main()
