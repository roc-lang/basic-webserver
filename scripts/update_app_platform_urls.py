#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLATFORM_RE = re.compile(r'(?m)(\bplatform\s+)"[^"]+"')


def update_apps(paths: list[Path], platform_url: str) -> list[Path]:
    roc_files: list[Path] = []
    for path in paths:
        if path.is_dir():
            roc_files.extend(sorted(path.glob("*.roc")))
        elif path.suffix == ".roc":
            roc_files.append(path)
        else:
            raise SystemExit(f"Expected a Roc app or directory: {path}")

    if not roc_files:
        raise SystemExit("No Roc apps found")

    updated: list[Path] = []
    for roc_file in roc_files:
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
            roc_file.write_text(rewritten, encoding="utf-8", newline="\n")
            updated.append(roc_file)

    return updated


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform-url", required=True)
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()

    updated = update_apps(args.paths, args.platform_url)
    if updated:
        print("Updated app platform URLs:")
        for path in updated:
            print(f"- {display_path(path)}")
    else:
        print("App platform URLs are already up to date.")


if __name__ == "__main__":
    main()
