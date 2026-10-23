#!/usr/bin/env python3
"""Invoke Zig's C compiler as a Cargo-compatible cross compiler."""

from __future__ import annotations

import os
import subprocess
import sys


def compiler_args(target: str, args: list[str]) -> list[str]:
    # cc-rs may pass a Rust target triple, which Zig does not understand (for
    # example, `x86_64-unknown-linux-musl`). build.py supplies the
    # corresponding Zig triple through ZIG_CC_TARGET.
    result = []
    skip = False
    for arg in args:
        if skip:
            skip = False
        elif arg == "-target":
            skip = True
        elif not arg.startswith("--target="):
            result.append(arg)
    # Match /MD: use the DLL CRT declarations, without changing the MSVC ABI.
    runtime = ["-fms-runtime-lib=dll"] if target.endswith("-windows-msvc") else []
    return ["cc", "-target", target, *runtime, *result]


if __name__ == "__main__":
    target = os.environ.get("ZIG_CC_TARGET")
    if not target:
        raise SystemExit("ZIG_CC_TARGET must be set")
    zig = os.environ.get("ZIG", "zig")
    raise SystemExit(subprocess.call([zig, *compiler_args(target, sys.argv[1:])]))
