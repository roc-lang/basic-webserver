#!/usr/bin/env python3
"""Portable child process used by examples/command.roc."""

from __future__ import annotations

import os
import sys


mode, *args = sys.argv[1:]
if mode == "echo":
    sys.stdout.buffer.write(" ".join(args).encode() + b"\n")
elif mode == "env":
    for name in ("BAZ", "FOO", "XYZ"):
        sys.stdout.buffer.write(f"{name}={os.environ[name]}\n".encode())
elif mode == "fail":
    sys.stderr.buffer.write(b"requested failure\n")
    raise SystemExit(1)
else:
    raise SystemExit(f"unknown mode: {mode}")
