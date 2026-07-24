#!/usr/bin/env python3
"""Invoke Zig's C compiler as a Cargo-compatible cross compiler."""

from __future__ import annotations

import os
import subprocess
import sys


# cc-rs may append a Rust target triple, which Zig does not understand (for
# example, `x86_64-unknown-linux-musl`). build.py supplies the corresponding
# Zig triple through ZIG_CC_TARGET.
target = os.environ.get("ZIG_CC_TARGET")
if not target:
    raise SystemExit("ZIG_CC_TARGET must be set")

zig_args = [arg for arg in sys.argv[1:] if not arg.startswith("--target=")]
raise SystemExit(
    subprocess.run(
        ["zig", "cc", "-target", target, *zig_args],
        check=False,
    ).returncode
)
