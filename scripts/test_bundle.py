#!/usr/bin/env python3
from __future__ import annotations

import argparse
import functools
import os
import re
import subprocess
import sys
import threading
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from update_app_platform_urls import update_apps


ROOT = Path(__file__).resolve().parents[1]


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        pass


class BundleServer:
    def __init__(self, bundle: Path) -> None:
        handler = functools.partial(QuietHandler, directory=str(bundle.parent))
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.url = f"http://127.0.0.1:{self.server.server_port}/{bundle.name}"

    def __enter__(self) -> str:
        self.thread.start()
        with urllib.request.urlopen(
            urllib.request.Request(self.url, method="HEAD"), timeout=5
        ):
            pass
        return self.url

    def __exit__(self, *_: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


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
    readme.write_text(rewritten, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run the basic-webserver suite against a packaged platform"
    )
    parser.add_argument("--bundle-path", required=True, type=Path)
    args = parser.parse_args()

    bundle = args.bundle_path
    if not bundle.is_absolute():
        bundle = ROOT / bundle
    bundle = bundle.resolve()
    if not bundle.is_file():
        raise SystemExit(f"Bundle does not exist: {bundle}")

    sources = sorted((ROOT / "examples").glob("*.roc"))
    sources.append(ROOT / "README.md")
    backups = {path: path.read_bytes() for path in sources}

    try:
        with BundleServer(bundle) as bundle_url:
            print(f"Testing bundle: {bundle_url}")
            update_apps([ROOT / "examples"], bundle_url)
            update_readme(bundle_url)
            subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "test.py")],
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
