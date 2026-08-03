#!/usr/bin/env python3
"""Build, verify, and compare the Roc and official Go Datastar SSE servers."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
import platform
import signal
import shutil
import socket
import statistics
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "target" / "datastar-e2e"
ROC_SERVER = BUILD / "roc-server"
ROC_INSTRUMENTED_SERVER = BUILD / "roc-server-instrumented"
GO_SERVER = BUILD / "go-server"
GO_MODULE = ROOT / "research" / "datastar-parity" / "go-reference"
GO_DEFAULT = Path("/tmp/go1.26.5/bin/go")
ROC_DEFAULT = Path(shutil.which("roc") or "roc")
SERVER_CPU = "2"
CLIENT_CPU = "3"
CLOCK_TICKS = os.sysconf("SC_CLK_TCK")


def run(command: list[str], *, cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True)


def build(roc: Path, go: Path, *, instrumented: bool) -> None:
    BUILD.mkdir(parents=True, exist_ok=True)
    run([sys.executable, "scripts/build.py"])
    run(
        [
            str(roc),
            "build",
            "--no-cache",
            "--opt=speed",
            "--target=x64musl",
            f"--output={ROC_SERVER}",
            "research/datastar-e2e/app.roc",
        ]
    )
    environment = os.environ.copy()
    environment["GOTOOLCHAIN"] = "local"
    run(
        [str(go), "build", "-trimpath", "-o", str(GO_SERVER), "./cmd/reference-server"],
        cwd=GO_MODULE,
        env=environment,
    )
    if instrumented:
        build_instrumented_roc_server(roc)


def build_instrumented_roc_server(roc: Path) -> None:
    target = "x86_64-unknown-linux-musl"
    host_archive = ROOT / "platform" / "targets" / "x64musl" / "libhost.a"
    saved_archive = BUILD / "libhost-production.a"
    shutil.copy2(host_archive, saved_archive)
    environment = os.environ.copy()
    environment.update(
        {
            "ZIG_CC_TARGET": "x86_64-linux-musl",
            "CC_x86_64_unknown_linux_musl": str(ROOT / "scripts" / "zig_cc.py"),
            "AR_x86_64_unknown_linux_musl": "zig ar",
            "CFLAGS_x86_64_unknown_linux_musl": "-Wno-error",
        }
    )
    try:
        run(
            [
                "cargo",
                "build",
                "--locked",
                "--release",
                "--lib",
                "--target",
                target,
                "--features",
                "sse-benchmark-instrumentation",
            ],
            env=environment,
        )
        shutil.copy2(ROOT / "target" / target / "release" / "libhost.a", host_archive)
        run(
            [
                str(roc),
                "build",
                "--no-cache",
                "--opt=speed",
                "--target=x64musl",
                f"--output={ROC_INSTRUMENTED_SERVER}",
                "research/datastar-e2e/app.roc",
            ]
        )
    finally:
        shutil.copy2(saved_archive, host_archive)


def wait_until_listening(process: subprocess.Popen[bytes], port: int) -> None:
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"server exited early with status {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.025)
    raise RuntimeError(f"server did not listen on port {port}")


@dataclass
class Server:
    name: str
    coding: str
    process: subprocess.Popen[bytes]
    port: int
    stdout_file: BinaryIO
    stderr_file: BinaryIO

    @classmethod
    def start(
        cls, name: str, coding: str, *, allocations: bool = False
    ) -> "Server":
        environment = os.environ.copy()
        if name == "roc":
            binary = ROC_INSTRUMENTED_SERVER if allocations else ROC_SERVER
            command = ["taskset", "-c", SERVER_CPU, str(binary)]
            environment["TOKIO_WORKER_THREADS"] = "1"
            port = 8000
        else:
            command = [
                "taskset",
                "-c",
                SERVER_CPU,
                str(GO_SERVER),
                "-coding",
                coding,
            ]
            if allocations:
                command.append("-measure-allocations")
            environment["GOMAXPROCS"] = "1"
            port = 8099
        stdout_file = tempfile.TemporaryFile()
        stderr_file = tempfile.TemporaryFile()
        process = subprocess.Popen(
            command,
            cwd=ROOT,
            env=environment,
            stdout=stdout_file,
            stderr=stderr_file,
        )
        server = cls(name, coding, process, port, stdout_file, stderr_file)
        wait_until_listening(process, port)
        return server

    def stop(self) -> None:
        if self.process.poll() is None:
            self.process.send_signal(signal.SIGINT)
            try:
                self.process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()

    def stderr(self) -> str:
        self.stderr_file.flush()
        self.stderr_file.seek(0)
        return self.stderr_file.read().decode("utf-8", errors="replace")

    def close_logs(self) -> None:
        self.stdout_file.close()
        self.stderr_file.close()


def proc_cpu_seconds(pid: int) -> float:
    text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
    fields = text.rsplit(")", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / CLOCK_TICKS


def proc_status_kib(pid: int, field: str) -> int:
    for line in Path(f"/proc/{pid}/status").read_text(encoding="utf-8").splitlines():
        if line.startswith(field + ":"):
            return int(line.split()[1])
    raise RuntimeError(f"{field} absent from /proc/{pid}/status")


def curl_command(server: Server, path: str, coding: str, output: str) -> list[str]:
    command = [
        "taskset",
        "-c",
        CLIENT_CPU,
        "curl",
        "--http1.1",
        "--silent",
        "--show-error",
        "--output",
        output,
    ]
    if coding == "scale":
        command.extend(["--compressed", "--header", "Accept-Encoding: br"])
    command.append(f"http://127.0.0.1:{server.port}{path}")
    return command


def decoded_body(server: Server, path: str, coding: str) -> bytes:
    return subprocess.check_output(curl_command(server, path, coding, "-"), cwd=ROOT)


def verify(server: Server) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for path, expected in (("/finite", 1), ("/hot-100", 100)):
        body = decoded_body(server, path, server.coding)
        count = body.count(b"event: datastar-patch-elements\n")
        if count != expected:
            raise RuntimeError(
                f"{server.name}/{server.coding}{path}: {count} events, expected {expected}"
            )
        if b'data-seq="1"' not in body or f'data-seq="{expected}"'.encode() not in body:
            raise RuntimeError(f"{server.name}/{server.coding}{path}: sequence boundary missing")
        records.append(
            {
                "kind": "correctness",
                "implementation": server.name,
                "coding": server.coding,
                "path": path,
                "events": count,
                "decoded_bytes": len(body),
            }
        )
    return records


def hot_sample(server: Server, path: str, events: int, sample: int) -> dict[str, object]:
    write_out = (
        "starttransfer=%{time_starttransfer} total=%{time_total} "
        "wire=%{size_download} speed=%{speed_download} code=%{response_code}"
    )
    command = curl_command(server, path, server.coding, "/dev/null")
    command[command.index(f"http://127.0.0.1:{server.port}{path}"):command.index(f"http://127.0.0.1:{server.port}{path}")] = [
        "--write-out",
        write_out,
    ]
    cpu_before = proc_cpu_seconds(server.process.pid)
    started = time.perf_counter()
    output = subprocess.check_output(command, cwd=ROOT, text=True)
    wall = time.perf_counter() - started
    cpu = proc_cpu_seconds(server.process.pid) - cpu_before
    values = dict(field.split("=", 1) for field in output.strip().split())
    if values["code"] != "200":
        raise RuntimeError(f"unexpected HTTP status: {output}")
    return {
        "kind": "hot",
        "implementation": server.name,
        "coding": server.coding,
        "path": path,
        "events": events,
        "sample": sample,
        "wall_seconds": wall,
        "curl_total_seconds": float(values["total"]),
        "start_transfer_seconds": float(values["starttransfer"]),
        "server_cpu_seconds": cpu,
        "wall_ns_per_event": wall * 1e9 / events,
        "server_cpu_ns_per_event": cpu * 1e9 / events,
        "wire_bytes": int(values["wire"]),
        "download_bytes_per_second": int(values["speed"]),
        "rss_kib": proc_status_kib(server.process.pid, "VmRSS"),
        "rss_high_water_kib": proc_status_kib(server.process.pid, "VmHWM"),
    }


def progressive_sample(server: Server, sample: int) -> dict[str, object]:
    request = (
        "GET /progressive HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{server.port}\r\n"
        "Accept-Encoding: identity\r\n"
        "Connection: close\r\n\r\n"
    ).encode()
    started = time.perf_counter()
    header_at: float | None = None
    event_times: list[float] = []
    received = bytearray()
    with socket.create_connection(("127.0.0.1", server.port), timeout=5) as connection:
        connection.sendall(request)
        connection.settimeout(5)
        while True:
            chunk = connection.recv(65536)
            now = time.perf_counter()
            if not chunk:
                break
            received.extend(chunk)
            if header_at is None and b"\r\n\r\n" in received:
                header_at = now
            complete = received.count(b"event: datastar-patch-elements")
            while len(event_times) < min(complete, 3):
                event_times.append(now)
        ended = time.perf_counter()
    if header_at is None or len(event_times) != 3:
        raise RuntimeError(f"progressive response incomplete: {len(event_times)} events")
    return {
        "kind": "progressive",
        "implementation": server.name,
        "coding": "identity",
        "sample": sample,
        "headers_ms": (header_at - started) * 1000,
        "event_1_ms": (event_times[0] - started) * 1000,
        "event_2_ms": (event_times[1] - started) * 1000,
        "event_3_ms": (event_times[2] - started) * 1000,
        "gap_1_2_ms": (event_times[1] - event_times[0]) * 1000,
        "gap_2_3_ms": (event_times[2] - event_times[1]) * 1000,
        "eof_ms": (ended - started) * 1000,
    }


def open_idle_stream(server: Server) -> socket.socket:
    return open_parked_stream(server, "/idle")


def open_parked_stream(server: Server, path: str) -> socket.socket:
    connection = socket.create_connection(("127.0.0.1", server.port), timeout=5)
    coding_header = "Accept-Encoding: br\r\n" if server.coding == "scale" else ""
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{server.port}\r\n"
        f"{coding_header}"
        "Connection: close\r\n\r\n"
    ).encode()
    connection.sendall(request)
    received = bytearray()
    while b"\r\n\r\n" not in received or len(received.split(b"\r\n\r\n", 1)[1]) == 0:
        chunk = connection.recv(65536)
        if not chunk:
            connection.close()
            raise RuntimeError("idle stream ended before its first encoded body bytes")
        received.extend(chunk)
    return connection


def percentile(values: list[float], quantile: float) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * quantile) - 1)]


def request_once(server: Server, path: str) -> tuple[int, float]:
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{server.port}\r\n"
        "Accept-Encoding: identity\r\n"
        "Connection: close\r\n\r\n"
    ).encode()
    started = time.perf_counter()
    received = bytearray()
    with socket.create_connection(("127.0.0.1", server.port), timeout=5) as connection:
        connection.sendall(request)
        connection.settimeout(10)
        while chunk := connection.recv(65536):
            received.extend(chunk)
    elapsed = time.perf_counter() - started
    first_line = bytes(received).split(b"\r\n", 1)[0]
    try:
        status = int(first_line.split()[1])
    except (IndexError, ValueError) as error:
        raise RuntimeError(f"invalid HTTP response: {first_line!r}") from error
    return status, elapsed


def load_sample(
    server: Server,
    *,
    parked_streams: int,
    requests: int,
    concurrency: int,
    sample: int,
) -> dict[str, object]:
    parked: list[socket.socket] = []
    try:
        for _ in range(parked_streams):
            parked.append(open_idle_stream(server))
        started = time.perf_counter()
        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
            results = list(pool.map(lambda _: request_once(server, "/ordinary"), range(requests)))
        elapsed = time.perf_counter() - started
    finally:
        for connection in parked:
            connection.close()
    statuses = [status for status, _ in results]
    latencies_ms = [duration * 1000 for _, duration in results]
    if any(status != 200 for status in statuses):
        raise RuntimeError(f"ordinary mixed-load statuses were {sorted(set(statuses))}")
    return {
        "kind": "mixed-load",
        "implementation": server.name,
        "coding": server.coding,
        "parked_streams": parked_streams,
        "requests": requests,
        "concurrency": concurrency,
        "sample": sample,
        "elapsed_seconds": elapsed,
        "requests_per_second": requests / elapsed,
        "p50_ms": percentile(latencies_ms, 0.50),
        "p95_ms": percentile(latencies_ms, 0.95),
        "p99_ms": percentile(latencies_ms, 0.99),
        "max_ms": max(latencies_ms),
    }


def simultaneous_wake_sample(server: Server, streams: int, sample: int) -> dict[str, object]:
    def observe(_: int) -> float:
        request = (
            "GET /wake-100 HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{server.port}\r\n"
            "Accept-Encoding: identity\r\n"
            "Connection: close\r\n\r\n"
        ).encode()
        received = bytearray()
        with socket.create_connection(("127.0.0.1", server.port), timeout=5) as connection:
            connection.sendall(request)
            connection.settimeout(5)
            while received.count(b"event: datastar-patch-elements") < 2:
                chunk = connection.recv(65536)
                if not chunk:
                    raise RuntimeError("wake stream ended before its second event")
                received.extend(chunk)
        return time.perf_counter()

    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=streams) as pool:
        completed = list(pool.map(observe, range(streams)))
    wake_ms = [(finished - started) * 1000 for finished in completed]
    return {
        "kind": "simultaneous-wake",
        "implementation": server.name,
        "coding": "identity",
        "streams": streams,
        "sample": sample,
        "p50_ms": percentile(wake_ms, 0.50),
        "p95_ms": percentile(wake_ms, 0.95),
        "p99_ms": percentile(wake_ms, 0.99),
        "spread_ms": max(wake_ms) - min(wake_ms),
    }


def saturation_sample(server: Server, capacity: int, sample: int) -> dict[str, object]:
    parked: list[socket.socket] = []
    try:
        for _ in range(capacity):
            parked.append(open_idle_stream(server))
        saturated_status, saturated_seconds = request_once(server, "/idle")
        parked.pop().close()
        deadline = time.monotonic() + 5
        while True:
            recovered_status, recovered_seconds = request_once(server, "/finite")
            if recovered_status == 200 or time.monotonic() >= deadline:
                break
            time.sleep(0.01)
    finally:
        for connection in parked:
            connection.close()
    if saturated_status != 503 or recovered_status != 200:
        raise RuntimeError(
            f"stream saturation/recovery statuses = {saturated_status}/{recovered_status}"
        )
    return {
        "kind": "saturation",
        "implementation": server.name,
        "coding": server.coding,
        "capacity": capacity,
        "sample": sample,
        "saturated_status": saturated_status,
        "saturated_response_ms": saturated_seconds * 1000,
        "recovered_status": recovered_status,
        "recovery_response_ms": recovered_seconds * 1000,
    }


def disconnect_storm_sample(server: Server, disconnects: int, sample: int) -> dict[str, object]:
    started = time.perf_counter()
    for _ in range(disconnects):
        connection = open_idle_stream(server)
        connection.close()
    storm_seconds = time.perf_counter() - started
    status, recovery_seconds = request_once(server, "/finite")
    if status != 200:
        raise RuntimeError(f"server did not recover after disconnect storm: {status}")
    return {
        "kind": "disconnect-storm",
        "implementation": server.name,
        "coding": server.coding,
        "disconnects": disconnects,
        "sample": sample,
        "storm_seconds": storm_seconds,
        "recovery_ms": recovery_seconds * 1000,
    }


def idle_sample(server: Server, streams: int, sample: int) -> dict[str, object]:
    rss_before = proc_status_kib(server.process.pid, "VmRSS")
    cpu_before = proc_cpu_seconds(server.process.pid)
    connections: list[socket.socket] = []
    try:
        for _ in range(streams):
            connections.append(open_idle_stream(server))
        time.sleep(0.25)
        rss_active = proc_status_kib(server.process.pid, "VmRSS")
        cpu_active = proc_cpu_seconds(server.process.pid) - cpu_before
        idle_cpu_before = proc_cpu_seconds(server.process.pid)
        time.sleep(1)
        idle_cpu = proc_cpu_seconds(server.process.pid) - idle_cpu_before
    finally:
        for connection in connections:
            connection.close()
        time.sleep(0.25)
    return {
        "kind": "idle",
        "implementation": server.name,
        "coding": server.coding,
        "streams": streams,
        "sample": sample,
        "rss_before_kib": rss_before,
        "rss_active_kib": rss_active,
        "rss_delta_kib": rss_active - rss_before,
        "rss_delta_bytes_per_stream": (rss_active - rss_before) * 1024 / streams,
        "admission_cpu_seconds": cpu_active,
        "one_second_idle_cpu_seconds": idle_cpu,
    }


def allocation_total(
    implementation: str,
    coding: str,
    workload: str,
    path: str,
    events: int,
    sample: int,
) -> dict[str, object]:
    server = Server.start(implementation, coding, allocations=True)
    try:
        decoded_body(server, path, coding)
        server.stop()
        stderr = server.stderr()
    finally:
        server.stop()
        server.close_logs()

    if implementation == "roc":
        marker = "SSE_BENCH_ALLOC "
        line = next((item for item in stderr.splitlines() if item.startswith(marker)), None)
        if line is None:
            raise RuntimeError(f"Roc allocation report missing:\n{stderr}")
        values = dict(field.split("=", 1) for field in line[len(marker) :].split())
        result: dict[str, object] = {
            "kind": "allocation-total",
            "implementation": implementation,
            "coding": coding,
            "workload": workload,
            "path": path,
            "events": events,
            "sample": sample,
        }
        result.update({name: int(value) for name, value in values.items()})
        return result

    json_line = next(
        (
            item[item.index("{") :]
            for item in stderr.splitlines()
            if '"kind":"go-request-allocations"' in item
        ),
        None,
    )
    if json_line is None:
        raise RuntimeError(f"Go allocation report missing:\n{stderr}")
    measured = json.loads(json_line)
    return {
        "kind": "allocation-total",
        "implementation": implementation,
        "coding": coding,
        "workload": workload,
        "path": path,
        "events": events,
        "sample": sample,
        "global_allocs": measured["mallocs"],
        "global_allocated_bytes": measured["allocated_bytes"],
    }


def allocation_slopes(records: list[dict[str, object]]) -> list[dict[str, object]]:
    summaries: list[dict[str, object]] = []
    measured_fields = (
        "global_allocs",
        "global_deallocs",
        "global_reallocs",
        "global_allocated_bytes",
        "global_reallocated_bytes",
        "roc_allocs",
        "roc_deallocs",
        "roc_reallocs",
        "roc_allocated_bytes",
        "roc_reallocated_bytes",
    )
    for implementation in ("roc", "go"):
        for coding in ("identity", "scale"):
            for workload in ("dynamic", "repeat", "assemble", "transport"):
                sample_ids = sorted(
                    {
                        int(record["sample"])
                        for record in records
                        if record["kind"] == "allocation-total"
                        and record["implementation"] == implementation
                        and record["coding"] == coding
                        and record["workload"] == workload
                    }
                )
                for sample in sample_ids:
                    selected = {
                        int(record["events"]): record
                        for record in records
                        if record["kind"] == "allocation-total"
                        and record["implementation"] == implementation
                        and record["coding"] == coding
                        and record["workload"] == workload
                        and record["sample"] == sample
                    }
                    low, high = selected[100], selected[1000]
                    summary: dict[str, object] = {
                        "kind": "allocation-slope",
                        "implementation": implementation,
                        "coding": coding,
                        "workload": workload,
                        "sample": sample,
                        "event_delta": 900,
                    }
                    for field in measured_fields:
                        if field in low and field in high:
                            summary[f"{field}_per_event"] = (
                                int(high[field]) - int(low[field])
                            ) / 900
                    summaries.append(summary)
    return summaries


def median_summary(records: list[dict[str, object]]) -> list[dict[str, object]]:
    grouped: dict[tuple[object, ...], list[dict[str, object]]] = {}
    for record in records:
        if record["kind"] not in {
            "hot",
            "idle",
            "progressive",
            "mixed-load",
            "simultaneous-wake",
            "saturation",
            "disconnect-storm",
        }:
            continue
        key = (
            record["kind"],
            record["implementation"],
            record["coding"],
            record.get("path", ""),
            record.get("parked_streams", ""),
            record.get("streams", ""),
            record.get("capacity", ""),
            record.get("disconnects", ""),
        )
        grouped.setdefault(key, []).append(record)
    summaries: list[dict[str, object]] = []
    for key, samples in grouped.items():
        numeric = {
            field
            for field, value in samples[0].items()
            if isinstance(value, (int, float)) and field not in {"sample", "events"}
        }
        summary: dict[str, object] = {
            "kind": "summary",
            "scenario": key[0],
            "implementation": key[1],
            "coding": key[2],
            "path": key[3],
            "parked_streams": key[4],
            "streams": key[5],
            "capacity": key[6],
            "disconnects": key[7],
            "samples": len(samples),
        }
        for field in sorted(numeric):
            summary[f"median_{field}"] = statistics.median(float(item[field]) for item in samples)
        summaries.append(summary)
    return summaries


def environment_record(roc: Path, go: Path, samples: int) -> dict[str, object]:
    def output(command: list[str]) -> str:
        return subprocess.check_output(command, cwd=ROOT, text=True).strip()

    return {
        "kind": "environment",
        "date": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "git_commit": output(["git", "rev-parse", "HEAD"]),
        "roc": output([str(roc), "version"]),
        "roc_binary": str(roc.resolve()),
        "rustc": output(["rustc", "--version"]),
        "go": output([str(go), "version"]),
        "curl": output(["curl", "--version"]).splitlines()[0],
        "platform": platform.platform(),
        "machine": platform.machine(),
        "cpu_count": os.cpu_count(),
        "server_cpu": SERVER_CPU,
        "client_cpu": CLIENT_CPU,
        "samples": samples,
    }


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--warmup", type=int, default=2)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--skip-allocations", action="store_true")
    parser.add_argument("--skip-hot", action="store_true")
    parser.add_argument("--skip-idle", action="store_true")
    parser.add_argument("--skip-progressive", action="store_true")
    parser.add_argument("--skip-load", action="store_true")
    parser.add_argument("--skip-wakes", action="store_true")
    parser.add_argument("--skip-saturation", action="store_true")
    parser.add_argument("--skip-disconnect-storm", action="store_true")
    parser.add_argument("--load-requests", type=int, default=128)
    parser.add_argument("--load-concurrency", type=int, default=16)
    parser.add_argument("--wake-streams", type=int, default=32)
    parser.add_argument("--stream-capacity", type=int, default=128)
    parser.add_argument("--disconnects", type=int, default=100)
    parser.add_argument("--idle-streams", default="10,50,100")
    parser.add_argument("--allocation-samples", type=int, default=3)
    parser.add_argument("--roc", type=Path, default=ROC_DEFAULT)
    parser.add_argument("--go", type=Path, default=GO_DEFAULT)
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    if args.samples < 3 or args.warmup < 1 or args.allocation_samples < 1:
        raise SystemExit(
            "--samples must be at least 3; --warmup and --allocation-samples must be positive"
        )
    idle_stream_counts = [int(value) for value in args.idle_streams.split(",")]
    if (
        any(value <= 0 for value in idle_stream_counts)
        or args.load_requests <= 0
        or args.load_concurrency <= 0
        or args.wake_streams <= 0
        or args.stream_capacity <= 0
        or args.disconnects <= 0
    ):
        raise SystemExit("load, stream, disconnect, and idle counts must be positive")
    if not sys.platform.startswith("linux"):
        raise SystemExit("this controlled /proc benchmark currently requires Linux")
    if not args.skip_build:
        build(args.roc, args.go, instrumented=not args.skip_allocations)
    if not ROC_SERVER.is_file() or not GO_SERVER.is_file():
        raise SystemExit("benchmark servers are missing; rerun without --skip-build")

    records: list[dict[str, object]] = [
        environment_record(args.roc, args.go, args.samples)
    ]
    for coding in ("identity", "scale"):
        for implementation in ("roc", "go"):
            server = Server.start(implementation, coding)
            try:
                records.extend(verify(server))
                if not args.skip_hot:
                    for path, events in (
                        ("/transport-256", 10000),
                        ("/transport-4096", 2000),
                        ("/transport-65536", 200),
                        ("/repeat-256", 10000),
                        ("/repeat-4096", 2000),
                        ("/repeat-65536", 200),
                        ("/assemble-256", 10000),
                        ("/assemble-4096", 2000),
                        ("/assemble-65536", 200),
                        ("/hot-10000", 10000),
                        ("/hot-4096", 2000),
                        ("/hot-65536", 200),
                    ):
                        for _ in range(args.warmup):
                            hot_sample(server, path, events, -1)
                        for sample in range(args.samples):
                            records.append(hot_sample(server, path, events, sample))
                if coding == "identity" and not args.skip_progressive:
                    for _ in range(args.warmup):
                        progressive_sample(server, -1)
                    for sample in range(args.samples):
                        records.append(progressive_sample(server, sample))
            finally:
                server.stop()
                server.close_logs()

    if not args.skip_idle:
        for coding in ("identity", "scale"):
            for implementation in ("roc", "go"):
                for streams in idle_stream_counts:
                    for sample in range(args.samples):
                        server = Server.start(implementation, coding)
                        try:
                            records.append(idle_sample(server, streams, sample))
                        finally:
                            server.stop()
                            server.close_logs()

    if not args.skip_load:
        for implementation in ("roc", "go"):
            server = Server.start(implementation, "identity")
            try:
                for parked_streams in (0, min(50, args.stream_capacity - 1)):
                    for sample in range(args.samples):
                        records.append(
                            load_sample(
                                server,
                                parked_streams=parked_streams,
                                requests=args.load_requests,
                                concurrency=args.load_concurrency,
                                sample=sample,
                            )
                        )
            finally:
                server.stop()
                server.close_logs()

    if not args.skip_wakes:
        for implementation in ("roc", "go"):
            server = Server.start(implementation, "identity")
            try:
                for sample in range(args.samples):
                    records.append(
                        simultaneous_wake_sample(server, args.wake_streams, sample)
                    )
            finally:
                server.stop()
                server.close_logs()

    if not args.skip_saturation:
        for coding in ("identity", "scale"):
            for implementation in ("roc", "go"):
                for sample in range(args.samples):
                    server = Server.start(implementation, coding)
                    try:
                        records.append(
                            saturation_sample(server, args.stream_capacity, sample)
                        )
                    finally:
                        server.stop()
                        server.close_logs()

    if not args.skip_disconnect_storm:
        for coding in ("identity", "scale"):
            for implementation in ("roc", "go"):
                for sample in range(args.samples):
                    server = Server.start(implementation, coding)
                    try:
                        records.append(
                            disconnect_storm_sample(server, args.disconnects, sample)
                        )
                    finally:
                        server.stop()
                        server.close_logs()

    if not args.skip_allocations:
        if not ROC_INSTRUMENTED_SERVER.is_file():
            raise SystemExit(
                "instrumented Roc server is missing; rerun without --skip-build or pass --skip-allocations"
            )
        for coding in ("identity", "scale"):
            for implementation in ("roc", "go"):
                for sample in range(args.allocation_samples):
                    for workload, low_path, high_path in (
                        ("dynamic", "/hot-100", "/hot-1000"),
                        ("repeat", "/repeat-100", "/repeat-1000"),
                        ("assemble", "/assemble-100", "/assemble-1000"),
                        ("transport", "/transport-100", "/transport-1000"),
                    ):
                        records.append(
                            allocation_total(
                                implementation, coding, workload, low_path, 100, sample
                            )
                        )
                        records.append(
                            allocation_total(
                                implementation, coding, workload, high_path, 1000, sample
                            )
                        )
        records.extend(allocation_slopes(records))

    records.extend(median_summary(records))
    encoded = "".join(json.dumps(record, sort_keys=True) + "\n" for record in records)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
        print(f"Wrote {args.output}")
    else:
        print(encoded, end="")


if __name__ == "__main__":
    main()
