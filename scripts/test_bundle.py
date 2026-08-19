#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

from update_app_platform_urls import update_apps
from test import BundleServer, declared_targets, examples_hash


ROOT = Path(__file__).resolve().parents[1]


def write_text(path: Path, text: str, newline: str = "\n") -> None:
    """Write ``text`` to ``path`` with fixed line endings (Path.write_text has no
    ``newline`` argument before Python 3.10)."""
    with path.open("w", encoding="utf-8", newline=newline) as handle:
        handle.write(text)


def update_readme(platform_url: str) -> None:
    readme = ROOT / "README.md"
    source = readme.read_text(encoding="utf-8")
    rewritten, count = re.subn(
        r'(?m)(\bplatform\s+)"[^"]+"',
        lambda match: f'{match.group(1)}"{platform_url}"',
        source,
        count=1,
    )
    if count != 1:
        raise SystemExit(f"Expected exactly one README platform URL, found {count}")
    write_text(readme, rewritten)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run the basic-webserver suite against a packaged platform"
    )
    bundle_source = parser.add_mutually_exclusive_group(required=True)
    bundle_source.add_argument("--bundle-path", type=Path)
    bundle_source.add_argument("--bundle-dir", type=Path)
    parser.add_argument(
        "--operation",
        choices=("all", "build-all"),
        default="all",
    )
    parser.add_argument("--build-id", default="local")
    parser.add_argument(
        "--targets",
        nargs="+",
        choices=declared_targets(),
        help=(
            "targets to build with --operation build-all; defaults to every "
            "declared target"
        ),
    )
    parser.add_argument(
        "--artifact-dir",
        type=Path,
        default=ROOT / "dist" / "example-binaries",
    )
    args = parser.parse_args()
    if args.targets is not None and args.operation != "build-all":
        parser.error("--targets requires --operation build-all")

    bundle = args.bundle_path
    if args.bundle_dir is not None:
        bundle_dir = args.bundle_dir
        if not bundle_dir.is_absolute():
            bundle_dir = ROOT / bundle_dir
        matches = sorted(bundle_dir.glob("*.tar.zst"))
        if len(matches) != 1:
            raise SystemExit(
                f"Expected exactly one .tar.zst bundle in {bundle_dir}, "
                f"found {len(matches)}"
            )
        bundle = matches[0]
    assert bundle is not None
    if not bundle.is_absolute():
        bundle = ROOT / bundle
    bundle = bundle.resolve()
    if not bundle.is_file():
        raise SystemExit(f"Bundle does not exist: {bundle}")

    sources = sorted((ROOT / "examples").rglob("*.roc"))
    sources.append(ROOT / "README.md")
    backups = {path: path.read_bytes() for path in sources}
    original_examples_sha256 = examples_hash()

    try:
        with BundleServer(bundle) as bundle_url:
            print(f"Testing bundle: {bundle_url}")
            update_apps([ROOT / "examples"], bundle_url)
            update_readme(bundle_url)
            command = [
                sys.executable,
                str(ROOT / "scripts" / "test.py"),
                "--platform-dependency",
                "declared",
            ]
            if args.operation == "build-all":
                targets = args.targets or list(declared_targets())
                for target in targets:
                    subprocess.run(
                        command
                        + [
                            "--operation",
                            "build",
                            "--target",
                            target,
                            "--build-id",
                            args.build_id,
                            "--examples-sha256",
                            original_examples_sha256,
                            "--artifact-dir",
                            str(args.artifact_dir),
                        ],
                        cwd=ROOT,
                        env=os.environ.copy(),
                        check=True,
                    )
            else:
                subprocess.run(
                    command,
                    cwd=ROOT,
                    env=os.environ.copy(),
                    check=True,
                )
    finally:
        for path, contents in backups.items():
            path.write_bytes(contents)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
