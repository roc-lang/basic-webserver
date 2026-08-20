#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLATFORM_RE = re.compile(r'(?m)(\bplatform\s+)"[^"]+"')
APPLICATION_HEADER = re.compile(r"(?m)^\s*app\s+\[")


def write_text(path: Path, text: str, newline: str = "\n") -> None:
    """Write ``text`` to ``path`` with fixed line endings (Path.write_text has no
    ``newline`` argument before Python 3.10)."""
    with path.open("w", encoding="utf-8", newline=newline) as handle:
        handle.write(text)


def update_apps(paths: list[Path], platform_url: str) -> list[Path]:
    roc_files: list[Path] = []
    for path in paths:
        if path.is_dir():
            roc_files.extend(sorted(path.rglob("*.roc")))
        elif path.suffix == ".roc":
            roc_files.append(path)
        else:
            raise SystemExit(f"Expected a Roc app or directory: {path}")

    app_files = [
        path
        for path in roc_files
        if APPLICATION_HEADER.search(path.read_text(encoding="utf-8")) is not None
    ]
    if not app_files:
        raise SystemExit("No Roc apps found")

    updated: list[Path] = []
    for roc_file in app_files:
        source = roc_file.read_text(encoding="utf-8")
        rewritten, count = PLATFORM_RE.subn(
            lambda match: f'{match.group(1)}"{platform_url}"',
            source,
            count=1,
        )
        if count != 1:
            raise SystemExit(
                f"Expected exactly one platform URL in {roc_file}, found {count}"
            )
        if rewritten != source:
            write_text(roc_file, rewritten)
            updated.append(roc_file)

    return updated


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def release_platform_url(manifest_path: Path, release_version: str, repository: str) -> str:
    bundles = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(bundles, list) or len(bundles) != 1:
        count = len(bundles) if isinstance(bundles, list) else "non-list"
        raise SystemExit(f"Expected exactly one release bundle, found {count}")
    artifact_file = bundles[0].get("artifact_file")
    if not isinstance(artifact_file, str) or not artifact_file:
        raise SystemExit(f"{manifest_path}: bundle is missing artifact_file")
    return (
        f"https://github.com/{repository}/releases/download/"
        f"{release_version}/{artifact_file}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--platform-url")
    source.add_argument("--release-manifest", type=Path)
    parser.add_argument(
        "--release-version",
        default=os.environ.get("RELEASE_VERSION"),
    )
    parser.add_argument(
        "--repository",
        default=os.environ.get("GITHUB_REPOSITORY"),
    )
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()

    platform_url = args.platform_url
    if args.release_manifest is not None:
        if not args.release_version:
            parser.error("--release-version or RELEASE_VERSION is required")
        if not args.repository:
            parser.error("--repository or GITHUB_REPOSITORY is required")
        platform_url = release_platform_url(
            args.release_manifest,
            args.release_version,
            args.repository,
        )
    assert platform_url is not None

    updated = update_apps(args.paths, platform_url)
    if updated:
        print("Updated app platform URLs:")
        for path in updated:
            print(f"- {display_path(path)}")
    else:
        print("App platform URLs are already up to date.")


if __name__ == "__main__":
    main()
