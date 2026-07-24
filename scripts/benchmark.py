#!/usr/bin/env python3
"""Build and run an indicative, local-only basic-webserver load test."""

from __future__ import annotations

import argparse
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PERF_DIR = ROOT / "target" / "perf-harness"
SERVER = PERF_DIR / ("basic-webserver-benchmark.exe" if os.name == "nt" else "basic-webserver-benchmark")
LOAD = ROOT / "target" / "release" / ("local-load.exe" if os.name == "nt" else "local-load")


def positive(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run rough local HTTP/1.1 and HTTP/2 measurements against an "
            "optimized compiled Roc application. This is not a CI benchmark."
        )
    )
    parser.add_argument("--duration", type=positive, default=10, help="measured seconds per scenario")
    parser.add_argument("--warmup", type=positive, default=2, help="warmup seconds per scenario")
    parser.add_argument("--concurrency", type=positive, default=64)
    parser.add_argument("--http2-connections", type=positive, default=1)
    parser.add_argument("--server-workers", type=positive, default=max(1, (os.cpu_count() or 2) // 2))
    parser.add_argument("--client-threads", type=positive, default=max(1, (os.cpu_count() or 2) // 2))
    parser.add_argument(
        "--protocol",
        choices=("http1", "http2", "both"),
        default="both",
    )
    parser.add_argument(
        "--scenario",
        choices=("fast", "effect", "mixed", "both", "all"),
        default="both",
        help=(
            "fast handler, 1 ms effect, or an 80/10/10 mix of fast, "
            "10 ms effect, and 50 ms effect requests"
        ),
    )
    parser.add_argument("--skip-build", action="store_true")
    return parser.parse_args()


def run(command: list[str], **kwargs: object) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True, **kwargs)


def build() -> None:
    PERF_DIR.mkdir(parents=True, exist_ok=True)
    run([sys.executable, "scripts/build.py"])
    run(
        [
            "roc",
            "build",
            "--opt=speed",
            f"--output={SERVER}",
            "scripts/perf/app.roc",
        ]
    )
    run(
        [
            "cargo",
            "build",
            "--locked",
            "--release",
            "--features",
            "local-load-test",
            "--bin",
            "local-load",
        ]
    )


def wait_until_listening(process: subprocess.Popen[bytes], timeout: float = 10.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise SystemExit(f"benchmark server exited early with status {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise SystemExit("benchmark server did not listen on 127.0.0.1:8000")


def load_command(
    args: argparse.Namespace, protocol: str, path: str | None, duration: int
) -> list[str]:
    command = [
        str(LOAD),
        "--protocol",
        protocol,
        "--duration",
        str(duration),
        "--concurrency",
        str(args.concurrency),
        "--threads",
        str(args.client_threads),
    ]
    if protocol == "http2":
        command.extend(["--connections", str(args.http2_connections)])
    if path is None:
        command.append("--mixed")
    else:
        command.extend(["--path", path])
    return command


def stop_server(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        process.terminate()
    else:
        process.send_signal(signal.SIGINT)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def main() -> None:
    args = arguments()
    if args.http2_connections > args.concurrency:
        raise SystemExit("--http2-connections cannot exceed --concurrency")
    if not args.skip_build:
        build()
    if not SERVER.is_file() or not LOAD.is_file():
        raise SystemExit("benchmark binaries are missing; rerun without --skip-build")

    protocols = ["http1", "http2"] if args.protocol == "both" else [args.protocol]
    if args.scenario == "both":
        scenarios = [("fast", "/fast"), ("effect", "/effect")]
    elif args.scenario == "all":
        scenarios = [("fast", "/fast"), ("effect", "/effect"), ("mixed", None)]
    elif args.scenario == "mixed":
        scenarios = [("mixed", None)]
    else:
        scenarios = [(args.scenario, f"/{args.scenario}")]
    environment = os.environ.copy()
    environment["TOKIO_WORKER_THREADS"] = str(args.server_workers)
    print(
        f"\nLocal-only indicative run: server_workers={args.server_workers}, "
        f"client_threads={args.client_threads}, concurrency={args.concurrency}\n"
        "The generator is closed-loop and shares this machine with the server; "
        "use results for comparisons, not capacity promises.\n",
        flush=True,
    )
    process = subprocess.Popen(
        [str(SERVER)],
        cwd=ROOT,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_until_listening(process)
        for name, path in scenarios:
            for protocol in protocols:
                print(f"==> warmup {name} over {protocol}", flush=True)
                run(
                    load_command(args, protocol, path, args.warmup),
                    stdout=subprocess.DEVNULL,
                )
                print(f"==> measure {name} over {protocol}", flush=True)
                run(load_command(args, protocol, path, args.duration))
    finally:
        stop_server(process)


if __name__ == "__main__":
    main()
