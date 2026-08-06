#!/usr/bin/env python3
"""Build and run the explicit Box(StreamState) ABI and Go comparison spike."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPIKE = ROOT / "docs" / "research" / "explicit-state-spike"
PLATFORM = SPIKE / "platform"
BUILD = ROOT / "build" / "explicit-state-spike"


def run(args: list[str], *, cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd, env=env, check=True)


def find_roc_source(roc: str) -> Path:
    explicit = os.environ.get("ROC_SRC")
    candidates = []
    if explicit:
        candidates.append(Path(explicit).expanduser())
    executable = Path(shutil.which(roc) or roc).resolve()
    candidates.extend((executable.parents[2], ROOT.parent / "roc", ROOT.parent.parent / "roc"))
    for candidate in candidates:
        if (candidate / "src" / "glue" / "src" / "CGlue.roc").is_file():
            return candidate.resolve()
    raise SystemExit("Could not find the Roc source tree; set ROC_SRC=/path/to/roc")


def prepare_host(roc: str, zig: str) -> None:
    roc_source = find_roc_source(roc)
    glue_dir = BUILD / "glue-c"
    glue_dir.mkdir(parents=True, exist_ok=True)
    run(
        [
            roc,
            "glue",
            "--no-cache",
            str(roc_source / "src" / "glue" / "src" / "CGlue.roc"),
            str(glue_dir),
            str(PLATFORM / "main.roc"),
        ]
    )

    host_object = BUILD / "host.o"
    run(
        [
            zig,
            "cc",
            "-target",
            "x86_64-linux-musl",
            "-std=c11",
            "-O3",
            "-fno-omit-frame-pointer",
            "-pthread",
            "-I",
            str(glue_dir),
            "-c",
            str(SPIKE / "host.c"),
            "-o",
            str(host_object),
        ]
    )

    target_dir = PLATFORM / "targets" / "x64musl"
    target_dir.mkdir(parents=True, exist_ok=True)
    platform_target = ROOT / "platform" / "targets" / "x64musl"
    for filename in ("crt1.o", "libc.a"):
        destination = target_dir / filename
        if destination.exists() or destination.is_symlink():
            destination.unlink()
        destination.symlink_to(platform_target / filename)
    run([zig, "ar", "rcs", str(target_dir / "libhost.a"), str(host_object)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--opt",
        choices=("dev", "speed", "all"),
        default="all",
        help="Roc backend/build mode to exercise",
    )
    parser.add_argument("--iterations", type=int, default=1_000_000)
    parser.add_argument("--repetitions", type=int, default=9)
    parser.add_argument(
        "--go",
        default=os.environ.get("GO_BIN", "/tmp/go1.26.5/bin/go"),
        help="Go 1.26.5 binary used for the comparison",
    )
    parser.add_argument("--skip-go", action="store_true")
    args = parser.parse_args()
    if args.iterations < 1000:
        parser.error("--iterations must be at least 1000")
    if args.repetitions < 3:
        parser.error("--repetitions must be at least 3")

    roc = os.environ.get("ROC", "roc")
    zig = os.environ.get("ZIG", "zig")
    BUILD.mkdir(parents=True, exist_ok=True)
    run([roc, "version"])
    prepare_host(roc, zig)

    run_env = os.environ.copy()
    run_env["EXPLICIT_STATE_ITERS"] = str(args.iterations)
    run_env["EXPLICIT_STATE_REPS"] = str(args.repetitions)
    modes = ("dev", "speed") if args.opt == "all" else (args.opt,)
    for mode in modes:
        executable = BUILD / f"explicit-state-{mode}"
        run(
            [
                roc,
                "build",
                "--no-cache",
                f"--opt={mode}",
                "--target=x64musl",
                f"--output={executable}",
                str(SPIKE / "app.roc"),
            ]
        )
        run([str(executable)], env=run_env)

    if not args.skip_go:
        go = Path(args.go)
        if not go.is_file():
            raise SystemExit(f"Go toolchain not found at {go}")
        run([str(go), "version"])
        go_executable = BUILD / "go-reference"
        go_env = os.environ.copy()
        go_env["GOTOOLCHAIN"] = "local"
        run(
            [
                str(go),
                "build",
                "-trimpath",
                "-o",
                str(go_executable),
                str(SPIKE / "go-reference.go"),
            ],
            env=go_env,
        )
        run([str(go_executable)], env=run_env)


if __name__ == "__main__":
    main()
