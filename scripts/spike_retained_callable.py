#!/usr/bin/env python3
"""Build and run the disposable retained Roc callable ABI spike."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPIKE = ROOT / "docs" / "research" / "abi-spike"
PLATFORM = SPIKE / "platform"
BUILD = ROOT / "build" / "abi-spike"


def run(args: list[str], *, cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd, env=env, check=True)


def run_expect_failure(args: list[str], *, stderr_needle: str) -> None:
    print("+ !", " ".join(args), flush=True)
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if result.returncode == 0:
        raise SystemExit("expected command to fail, but it succeeded")
    if stderr_needle not in result.stderr:
        print(result.stderr, end="")
        raise SystemExit(f"expected compiler failure containing {stderr_needle!r}")


def find_roc_source(roc: str) -> Path:
    explicit = os.environ.get("ROC_SRC")
    candidates = []
    if explicit:
        candidates.append(Path(explicit).expanduser())
    executable = Path(shutil.which(roc) or roc).resolve()
    candidates.extend(
        (
            executable.parents[2],
            ROOT.parent / "roc",
            ROOT.parent.parent / "roc",
        )
    )
    for candidate in candidates:
        if (candidate / "src" / "glue" / "src" / "CGlue.roc").is_file():
            return candidate.resolve()
    raise SystemExit("Could not find the Roc source tree; set ROC_SRC=/path/to/roc")


def prepare_host(roc: str, zig: str, rustc: str, *, direct_diagnostic: bool, host: str) -> None:
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

    if host == "rust":
        rust_glue_dir = BUILD / "glue-rust"
        rust_glue_dir.mkdir(parents=True, exist_ok=True)
        run(
            [
                roc,
                "glue",
                "--no-cache",
                str(roc_source / "src" / "glue" / "src" / "RustGlue.roc"),
                str(rust_glue_dir),
                str(PLATFORM / "main.roc"),
            ]
        )

    host_object = BUILD / "host.o"
    compile_args = [
        zig,
        "cc",
        "-target",
        "x86_64-linux-musl",
        "-std=c11",
        "-O3",
        "-pthread",
        "-I",
        str(glue_dir),
        "-c",
        str(SPIKE / "host.c"),
        "-o",
        str(host_object),
    ]
    if direct_diagnostic:
        compile_args.insert(2, "-DABI_SPIKE_DIRECT_ERASED_CALLABLE=1")
    if host == "rust":
        compile_args.insert(2, "-DABI_SPIKE_RUST_HOST=1")
    run(compile_args)

    host_objects = [host_object]
    if host == "rust":
        rust_host_object = BUILD / "rust-host.o"
        rust_compile_args = [
            rustc,
            "--edition=2021",
            "--crate-type=lib",
            "--emit=obj",
            "--target=x86_64-unknown-linux-musl",
            "-C",
            "panic=abort",
            "-C",
            "opt-level=3",
            "--cfg",
            "no_roc_std_helpers",
            "-D",
            "warnings",
            str(SPIKE / "rust_host.rs"),
        ]
        run([*rust_compile_args, "-o", str(rust_host_object)])
        run_expect_failure(
            [
                *rust_compile_args,
                "--cfg",
                "prove_non_copy",
                "-o",
                str(BUILD / "rust-host-must-not-compile.o"),
            ],
            stderr_needle="use of moved value: `step`",
        )
        host_objects.append(rust_host_object)

    target_dir = PLATFORM / "targets" / "x64musl"
    target_dir.mkdir(parents=True, exist_ok=True)
    platform_target = ROOT / "platform" / "targets" / "x64musl"
    for filename in ("crt1.o", "libc.a"):
        destination = target_dir / filename
        if destination.exists() or destination.is_symlink():
            destination.unlink()
        destination.symlink_to(platform_target / filename)
    host_archive = target_dir / "libhost.a"
    host_archive.unlink(missing_ok=True)
    run([zig, "ar", "rcs", str(host_archive), *map(str, host_objects)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--opt",
        choices=("dev", "speed", "all"),
        default="all",
        help="Roc backend/build mode to exercise",
    )
    parser.add_argument(
        "--host",
        choices=("c", "rust"),
        default="c",
        help="host-language ownership adapter to exercise",
    )
    parser.add_argument(
        "--iterations",
        type=int,
        default=1_000_000,
        help="advance calls per benchmark repetition",
    )
    parser.add_argument(
        "--mode",
        choices=("wrapper", "diagnostic"),
        default="wrapper",
        help="run through generated provided wrappers or the development-only direct helper",
    )
    args = parser.parse_args()
    if args.iterations < 1000:
        parser.error("--iterations must be at least 1000")
    if args.mode == "diagnostic" and args.opt != "dev":
        parser.error("direct erased-callable diagnostics are available only with --opt dev")
    if args.host == "rust" and args.mode != "wrapper":
        parser.error("the Rust ownership adapter uses generated wrappers only")

    roc = os.environ.get("ROC", "roc")
    zig = os.environ.get("ZIG", "zig")
    rustc = os.environ.get("RUSTC", "rustc")
    BUILD.mkdir(parents=True, exist_ok=True)
    run([roc, "version"])
    prepare_host(
        roc,
        zig,
        rustc,
        direct_diagnostic=args.mode == "diagnostic",
        host=args.host,
    )

    modes = ("dev", "speed") if args.opt == "all" else (args.opt,)
    run_env = os.environ.copy()
    run_env["ABI_SPIKE_ITERS"] = str(args.iterations)
    if args.mode == "wrapper":
        run_env["ABI_SPIKE_MODE"] = "wrapper"
    for mode in modes:
        run_env["ABI_SPIKE_EXPECT_REUSE"] = "1" if mode == "speed" else "0"
        executable = BUILD / f"retained-callable-{args.host}-{mode}"
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


if __name__ == "__main__":
    main()
