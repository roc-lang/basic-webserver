#!/usr/bin/env python3
"""Fetch and extract the checksum-pinned Ubuntu NGINX reference proxy."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.request import urlopen


PACKAGES = (
    (
        "nginx_1.24.0-2ubuntu7.15_amd64.deb",
        "http://au.archive.ubuntu.com/ubuntu/pool/main/n/nginx/nginx_1.24.0-2ubuntu7.15_amd64.deb",
        "3004458b1e9804ebe5e9c6a4c4fddcc80af012dbbe1a9f0669f275ee0aedc118",
    ),
    (
        "nginx-common_1.24.0-2ubuntu7.15_all.deb",
        "http://au.archive.ubuntu.com/ubuntu/pool/main/n/nginx/nginx-common_1.24.0-2ubuntu7.15_all.deb",
        "ce7211d826cb36f9454a5bae6270bdbc4da2dfd5d1137820914ba4555c25480d",
    ),
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if not shutil.which("dpkg-deb"):
        raise RuntimeError("dpkg-deb is required to extract the pinned packages")
    args.output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="datastar-nginx-download-") as directory:
        temporary = Path(directory)
        for filename, url, expected in PACKAGES:
            archive = temporary / filename
            with urlopen(url, timeout=30) as response:
                archive.write_bytes(response.read())
            actual = hashlib.sha256(archive.read_bytes()).hexdigest()
            if actual != expected:
                raise RuntimeError(f"{filename} SHA-256 {actual}, want {expected}")
            subprocess.run(
                ["dpkg-deb", "-x", str(archive), str(args.output)], check=True
            )

    nginx = args.output / "usr" / "sbin" / "nginx"
    subprocess.run([str(nginx), "-V"], check=True)
    print(nginx)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
