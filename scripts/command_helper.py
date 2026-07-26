#!/usr/bin/env python3
"""Portable child process used by examples/command.roc."""

from __future__ import annotations

import os
import sys
import time


mode, *args = sys.argv[1:]
if mode == "echo":
    sys.stdout.buffer.write(" ".join(args).encode() + b"\n")
elif mode == "env":
    for name in ("BAZ", "FOO", "XYZ"):
        sys.stdout.buffer.write(f"{name}={os.environ[name]}\n".encode())
elif mode == "fail":
    sys.stderr.buffer.write(b"requested failure\n")
    raise SystemExit(1)
elif mode == "bytes":
    sys.stdout.buffer.write(b"x" * int(args[0]))
elif mode == "sleep":
    time.sleep(float(args[0]))
elif mode == "cwd":
    time.sleep(float(args[0]))
    sys.stdout.buffer.write((os.path.basename(os.getcwd()) + "\n").encode())
else:
    raise SystemExit(f"unknown mode: {mode}")
