#!/usr/bin/env python3
"""Unified invariant validation and local performance orchestration."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import signal
import socket
import sqlite3
import statistics
import subprocess
import sys
import tempfile
import time
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
HARNESS_ROOT = ROOT / "target" / "benchmark-harness"
INSTRUMENTED_PLATFORM = HARNESS_ROOT / "platform"
DRIVER = ROOT / "target" / "release" / (
    "benchmark-driver.exe" if os.name == "nt" else "benchmark-driver"
)
SCHEMA_VERSION = 1

HTTP_SOURCE = ROOT / "scripts" / "perf" / "app.roc"
SSE_SOURCE = ROOT / "scripts" / "perf" / "sse_app.roc"
HTTP_BINARY = HARNESS_ROOT / (
    "basic-webserver-benchmark.exe" if os.name == "nt" else "basic-webserver-benchmark"
)
SSE_BINARY = HARNESS_ROOT / (
    "basic-webserver-sse-benchmark.exe"
    if os.name == "nt"
    else "basic-webserver-sse-benchmark"
)
SIMULATION_BINARY = HARNESS_ROOT / (
    "basic-webserver-simulation.exe" if os.name == "nt" else "basic-webserver-simulation"
)
SSE_SIMULATION_BINARY = HARNESS_ROOT / (
    "basic-webserver-sse-simulation.exe"
    if os.name == "nt"
    else "basic-webserver-sse-simulation"
)
SQLITE_SOURCE = ROOT / "scripts" / "perf" / "sqlite_app.roc"
SQLITE_SHARED_SOURCE = ROOT / "scripts" / "perf" / "sqlite_shared_app.roc"
SQLITE_BINARY = HARNESS_ROOT / (
    "basic-webserver-sqlite-benchmark.exe"
    if os.name == "nt"
    else "basic-webserver-sqlite-benchmark"
)
SQLITE_SHARED_BINARY = HARNESS_ROOT / (
    "basic-webserver-sqlite-shared-benchmark.exe"
    if os.name == "nt"
    else "basic-webserver-sqlite-shared-benchmark"
)
SQLITE_DATABASE = HARNESS_ROOT / "sqlite-load.db"


def positive(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def positive_csv(value: str) -> list[int]:
    try:
        parsed = [positive(item.strip()) for item in value.split(",")]
    except ValueError as error:
        raise argparse.ArgumentTypeError(str(error)) from error
    if not parsed:
        raise argparse.ArgumentTypeError("must contain at least one count")
    return parsed


def cpu_set(value: str) -> str:
    if re.fullmatch(r"[0-9]+(?:[-,][0-9]+)*", value) is None:
        raise argparse.ArgumentTypeError("must be a taskset CPU list such as 2 or 2,4-5")
    return value


def run(command: Iterable[str | os.PathLike[str]], **kwargs: Any) -> None:
    rendered = [str(item) for item in command]
    print("+", " ".join(rendered), flush=True)
    subprocess.run(rendered, cwd=ROOT, check=True, **kwargs)


def output(command: Iterable[str | os.PathLike[str]]) -> str:
    return subprocess.check_output(
        [str(item) for item in command], cwd=ROOT, text=True
    ).strip()


def git_metadata() -> dict[str, Any]:
    return {
        "commit": output(["git", "rev-parse", "HEAD"]),
        "dirty": bool(output(["git", "status", "--short"])),
    }


def environment_record(label: str) -> dict[str, Any]:
    cpu = platform.processor() or platform.machine()
    return {
        "schema_version": SCHEMA_VERSION,
        "kind": "run_environment",
        "label": label,
        "git": git_metadata(),
        "os": platform.platform(),
        "machine": platform.machine(),
        "cpu": cpu,
        "logical_cpus": os.cpu_count(),
        "python": platform.python_version(),
        "roc": output(["roc", "version"]),
        "rustc": output(["rustc", "--version"]),
    }


def write_record(destination: Any, record: dict[str, Any]) -> None:
    destination.write(json.dumps(record, sort_keys=True, separators=(",", ":")))
    destination.write("\n")
    destination.flush()


def build_driver() -> None:
    run(
        [
            "cargo",
            "build",
            "--locked",
            "--release",
            "--features",
            "benchmark-driver",
            "--bin",
            "benchmark-driver",
        ]
    )


def build_production_apps(apps: list[tuple[Path, Path]]) -> None:
    HARNESS_ROOT.mkdir(parents=True, exist_ok=True)
    run([sys.executable, "scripts/build.py"])
    for source, destination in apps:
        run(
            [
                "roc",
                "build",
                "--opt=speed",
                f"--output={destination}",
                source,
            ]
        )


def instrumented_source(source: Path) -> Path:
    relative = source.relative_to(ROOT)
    destination = HARNESS_ROOT / "sources" / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source.parent, destination.parent, dirs_exist_ok=True)
    text = destination.read_text(encoding="utf-8")
    platform_path = os.path.relpath(
        INSTRUMENTED_PLATFORM / "main.roc", destination.parent
    ).replace(os.sep, "/")
    rewritten, count = re.subn(
        r'(\bplatform\s+")[^"]+("\s*,?)',
        rf"\g<1>{platform_path}\g<2>",
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit(f"could not rewrite platform import in {source}")
    destination.write_text(rewritten, encoding="utf-8")
    return destination


def build_simulation_apps(apps: list[tuple[Path, Path]]) -> None:
    HARNESS_ROOT.mkdir(parents=True, exist_ok=True)
    run(
        [
            sys.executable,
            "scripts/build.py",
            "--features",
            "benchmark-simulation",
            "--output-platform",
            INSTRUMENTED_PLATFORM,
        ]
    )
    for source, destination in apps:
        rewritten = instrumented_source(source)
        run(
            [
                "roc",
                "build",
                "--no-cache",
                "--opt=speed",
                f"--output={destination}",
                rewritten,
            ]
        )


def sqlite_fixture_matches(path: Path, rows: int) -> bool:
    if not path.is_file():
        return False
    try:
        with sqlite3.connect(path) as connection:
            found = connection.execute(
                "SELECT value FROM benchmark_meta WHERE name = 'rows'"
            ).fetchone()
            return found == (str(rows),)
    except sqlite3.Error:
        return False


def create_sqlite_fixture(path: Path, rows: int, rebuild: bool) -> None:
    if rows < 125_000:
        raise SystemExit("--rows must be at least 125000 for the fixed point query")
    if not rebuild and sqlite_fixture_matches(path, rows):
        print(f"Reusing SQLite fixture with {rows:,} rows: {path}", flush=True)
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".building.db")
    for stale in (
        temporary,
        temporary.with_name(temporary.name + "-shm"),
        temporary.with_name(temporary.name + "-wal"),
    ):
        stale.unlink(missing_ok=True)
    print(f"Creating SQLite fixture with {rows:,} rows...", flush=True)
    started = time.monotonic()
    with sqlite3.connect(temporary) as connection:
        connection.execute("PRAGMA journal_mode=OFF")
        connection.execute("PRAGMA synchronous=OFF")
        connection.execute("PRAGMA temp_store=MEMORY")
        connection.executescript(
            """
            CREATE TABLE benchmark_meta (name TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE records (
                id INTEGER PRIMARY KEY,
                category TEXT NOT NULL,
                indexed_value INTEGER NOT NULL,
                unindexed_text TEXT NOT NULL,
                body TEXT NOT NULL
            );
            CREATE TABLE payloads (id INTEGER PRIMARY KEY, payload BLOB NOT NULL);
            CREATE TABLE counters (id INTEGER PRIMARY KEY, value INTEGER NOT NULL);
            """
        )
        body_suffix = "x" * 112
        for first in range(1, rows + 1, 10_000):
            last = min(rows + 1, first + 10_000)
            connection.executemany(
                """
                INSERT INTO records
                    (id, category, indexed_value, unindexed_text, body)
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    (
                        row_id,
                        f"category-{row_id % 100}",
                        row_id % 10_000,
                        (
                            "needle"
                            if row_id % 10_000 == 0
                            else f"haystack-{row_id % 4096}"
                        ),
                        f"record-{row_id}-{body_suffix}",
                    )
                    for row_id in range(first, last)
                ],
            )
        connection.execute("CREATE INDEX records_category ON records(category)")
        connection.execute("CREATE INDEX records_indexed_value ON records(indexed_value)")
        connection.executemany(
            "INSERT INTO payloads(id, payload) VALUES (?, ?)",
            [
                (1, b"a" * 1024),
                (2, b"b" * (64 * 1024)),
                (3, b"c" * (1024 * 1024)),
            ],
        )
        connection.execute("INSERT INTO counters(id, value) VALUES (1, 0)")
        connection.execute(
            "INSERT INTO benchmark_meta(name, value) VALUES ('rows', ?)",
            (str(rows),),
        )
        connection.execute("ANALYZE")
        connection.commit()
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=NORMAL")

    for existing in (
        path,
        path.with_name(path.name + "-shm"),
        path.with_name(path.name + "-wal"),
    ):
        existing.unlink(missing_ok=True)
    os.replace(temporary, path)
    print(
        f"SQLite fixture ready in {time.monotonic() - started:.1f}s "
        f"({path.stat().st_size / (1024 * 1024):.1f} MiB)",
        flush=True,
    )


def simulation_scenarios() -> list[tuple[Path, dict[str, Any]]]:
    common = {
        "schema_version": SCHEMA_VERSION,
        "concurrency": 32,
        "warmup_repeats": 2,
        "repeats": 8,
        "requests": [
            {"target": "/fast", "expect_body": "fast"},
            {"target": "/effect", "expect_body": "effect"},
        ],
    }
    return [
        (
            SIMULATION_BINARY,
            {
                **common,
                "name": "ordinary-http1",
                "protocol": "http1",
                "_expect_requests": 256,
                "_expect_min_resources": {"connections_high_water": 32},
            },
        ),
        (
            SIMULATION_BINARY,
            {
                **common,
                "name": "ordinary-http2",
                "protocol": "http2",
                "_expect_requests": 256,
                "_expect_min_resources": {"connections_high_water": 32},
            },
        ),
        (
            SIMULATION_BINARY,
            {
                **common,
                "name": "bounded-logical-connections",
                "protocol": "http1",
                "concurrency": 1_024,
                "warmup_repeats": 0,
                "repeats": 2,
                "requests": [{"target": "/fast", "expect_body": "fast"}],
                "_expect_requests": 2_048,
                "_expect_min_resources": {"connections_high_water": 1_024},
            },
        ),
        (
            SSE_SIMULATION_BINARY,
            {
                "schema_version": SCHEMA_VERSION,
                "name": "sse-identity-lifecycle",
                "protocol": "http1",
                "concurrency": 64,
                "warmup_repeats": 1,
                "repeats": 2,
                "requests": [
                    {
                        "target": "/hot-100",
                        "headers": {
                            "accept": "text/event-stream",
                            "accept-encoding": "identity",
                        },
                        "body_contains": ["event: benchmark-event"],
                        "expect_sse_events": 100,
                    }
                ],
                "_expect_requests": 128,
                "_expect_min_resources": {
                    "connections_high_water": 64,
                    "sse_streams_high_water": 64,
                },
            },
        ),
        (
            SSE_SIMULATION_BINARY,
            {
                "schema_version": SCHEMA_VERSION,
                "name": "sse-brotli-lifecycle",
                "protocol": "http2",
                "concurrency": 64,
                "warmup_repeats": 1,
                "repeats": 2,
                "requests": [
                    {
                        "target": "/hot-100",
                        "headers": {
                            "accept": "text/event-stream",
                            "accept-encoding": "br",
                        },
                        "expect_headers": {"content-encoding": "br"},
                        "body_contains": ["event: benchmark-event"],
                        "expect_sse_events": 100,
                    }
                ],
                "_expect_requests": 128,
                "_expect_min_resources": {
                    "connections_high_water": 64,
                    "sse_streams_high_water": 64,
                    "sse_brotli_lanes_high_water": 64,
                },
            },
        ),
    ]


def parse_prefixed_json(text: str, prefix: str) -> dict[str, Any]:
    for line in reversed(text.splitlines()):
        if line.startswith(prefix):
            return json.loads(line.removeprefix(prefix))
    raise SystemExit(f"instrumented server did not emit {prefix.strip()}:\n{text}")


def check(args: argparse.Namespace) -> None:
    if not args.skip_build:
        build_simulation_apps(
            [
                (HTTP_SOURCE, SIMULATION_BINARY),
                (SSE_SOURCE, SSE_SIMULATION_BINARY),
            ]
        )
    if not SIMULATION_BINARY.is_file() or not SSE_SIMULATION_BINARY.is_file():
        raise SystemExit("simulation binary is missing; rerun without --skip-build")

    failures: list[str] = []
    reports: list[dict[str, Any]] = []
    for binary, scenario in simulation_scenarios():
        print(f"==> simulate {scenario['name']}", flush=True)
        wire_scenario = {
            key: value for key, value in scenario.items() if not key.startswith("_")
        }
        completed = subprocess.run(
            [str(binary)],
            cwd=ROOT,
            input=json.dumps(wire_scenario).encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=args.timeout,
        )
        stdout = completed.stdout.decode(errors="replace")
        stderr = completed.stderr.decode(errors="replace")
        report = parse_prefixed_json(stdout, "BENCHMARK_SIMULATION ")
        reports.append(report)
        errors = report.get("errors", [])
        roc_requested = report["allocations"]["roc_requested"]
        roc_live = (roc_requested["live_blocks"], roc_requested["live_bytes"])
        tracking_misses = report["allocations"]["tracking_misses"]
        allocation_domains = report["allocations"]
        resources = report.get("resources") or {}
        expected_requests = scenario.get("_expect_requests")
        if expected_requests is not None and report.get("requests") != expected_requests:
            failures.append(
                f"{scenario['name']} completed {report.get('requests')} measured requests; "
                f"expected {expected_requests}"
            )
        for name, minimum in scenario.get("_expect_min_resources", {}).items():
            if resources.get(name, 0) < minimum:
                failures.append(
                    f"{scenario['name']} resource {name} reached "
                    f"{resources.get(name, 0)}; expected at least {minimum}"
                )
        live_resources = {
            name: value
            for name, value in resources.items()
            if (name.endswith("_active") or name in {
                "handlers_queued",
                "sse_brotli_operations_queued",
                "sse_brotli_operations_running",
            })
            and value != 0
        }
        if completed.returncode != 0:
            failures.append(
                f"{scenario['name']} exited {completed.returncode}: {stderr[-2000:]}"
            )
        if errors:
            failures.append(f"{scenario['name']} assertions: {errors}")
        if roc_live != (0, 0):
            failures.append(
                f"{scenario['name']} retained {roc_live[0]} measured Roc allocations "
                f"({roc_live[1]} bytes)"
            )
        if tracking_misses != 0:
            failures.append(
                f"{scenario['name']} exceeded allocation tracker capacity "
                f"({tracking_misses} untracked allocations)"
            )
        for domain in ("process", "roc_backing", "host", "harness", "roc_requested"):
            for field in ("live_blocks", "live_bytes", "peak_live_blocks", "peak_live_bytes"):
                if allocation_domains[domain][field] < 0:
                    failures.append(
                        f"{scenario['name']} allocation field {domain}.{field} was negative"
                    )
        for field in (
            "allocs",
            "deallocs",
            "reallocs",
            "allocated_bytes",
            "deallocated_bytes",
            "reallocated_bytes",
        ):
            classified = sum(
                allocation_domains[domain][field]
                for domain in ("roc_backing", "host", "harness")
            )
            if allocation_domains["process"][field] != classified:
                failures.append(
                    f"{scenario['name']} allocation field {field} was not fully classified"
                )
        if live_resources:
            failures.append(
                f"{scenario['name']} did not quiesce resources: {live_resources}"
            )
        print(
            f"    requests={report['requests']} errors={len(errors)} "
            f"host_allocs={report['allocations']['host']['allocs']} "
            f"roc_allocs={report['allocations']['roc_requested']['allocs']}",
            flush=True,
        )
    if failures:
        raise SystemExit("substituted-transport checks failed:\n- " + "\n- ".join(failures))
    if args.output:
        destination = args.output.resolve()
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("w", encoding="utf-8") as results:
            write_record(results, environment_record(args.label))
            for report in reports:
                report["label"] = args.label
                write_record(results, report)
        print(f"Wrote {destination}", flush=True)
    print("Substituted-transport server invariants passed.", flush=True)


def wait_until_listening(process: subprocess.Popen[bytes], timeout: float = 15.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise SystemExit(f"benchmark server exited early with {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise SystemExit("benchmark server did not listen on 127.0.0.1:8000")


def stop_server(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        process.terminate()
    else:
        process.send_signal(signal.SIGINT)
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def linux_process_snapshot(pid: int) -> dict[str, Any]:
    if sys.platform != "linux":
        return {"supported": False, "reason": "process snapshot currently requires Linux"}
    values: dict[str, int] = {}
    for line in Path(f"/proc/{pid}/status").read_text(encoding="utf-8").splitlines():
        name, separator, raw = line.partition(":")
        if separator and name in {"VmRSS", "VmHWM", "Threads"}:
            values[name] = int(raw.strip().split()[0])
    stat = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8").split()
    ticks = os.sysconf("SC_CLK_TCK")
    record: dict[str, Any] = {
        "supported": True,
        "rss_kib": values.get("VmRSS"),
        "rss_high_water_kib": values.get("VmHWM"),
        "threads": values.get("Threads"),
        "cpu_seconds": (int(stat[13]) + int(stat[14])) / ticks,
        "file_descriptors": len(list(Path(f"/proc/{pid}/fd").iterdir())),
        "minor_faults": int(stat[9]),
        "major_faults": int(stat[11]),
    }
    rollup = Path(f"/proc/{pid}/smaps_rollup")
    if rollup.is_file():
        for line in rollup.read_text(encoding="utf-8").splitlines():
            if line.startswith("Pss:"):
                record["pss_kib"] = int(line.split()[1])
                break
    return record


def scenario_file(
    *,
    name: str,
    protocol: str,
    duration_ms: int,
    concurrency: int,
    threads: int,
    connections: int,
    routes: list[dict[str, Any]],
    workload: str = "request",
    expected_events: int = 0,
    accept_encoding: str = "identity",
    request_timeout_ms: int = 5_000,
    allow_errors: bool = False,
    error_backoff_ms: int = 0,
) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "name": name,
        "workload": workload,
        "protocol": protocol,
        "address": "127.0.0.1:8000",
        "routes": routes,
        "duration_ms": duration_ms,
        "request_timeout_ms": request_timeout_ms,
        "concurrency": concurrency,
        "connections": connections,
        "threads": threads,
        "expected_events": expected_events,
        "accept_encoding": accept_encoding,
        "allow_errors": allow_errors,
        "error_backoff_ms": error_backoff_ms,
    }


def http_scenarios(args: argparse.Namespace) -> list[dict[str, Any]]:
    protocols = ["http1", "http2"] if args.protocol == "both" else [args.protocol]
    definitions = [
        ("fast", [{"path": "/fast", "weight": 1}]),
        ("effect", [{"path": "/effect", "weight": 1}]),
        (
            "mixed",
            [
                {"path": "/fast", "weight": 80},
                {"path": "/effect-10", "weight": 10},
                {"path": "/effect-50", "weight": 10},
            ],
        ),
    ]
    scenarios = []
    for protocol in protocols:
        for name, routes in definitions:
            scenarios.append(
                scenario_file(
                    name=f"{name}-{protocol}",
                    protocol=protocol,
                    duration_ms=args.duration * 1_000,
                    concurrency=args.concurrency,
                    threads=args.client_threads,
                    connections=(
                        args.http2_connections if protocol == "http2" else args.concurrency
                    ),
                    routes=routes,
                )
            )
    return scenarios


def sse_scenarios(args: argparse.Namespace) -> list[dict[str, Any]]:
    protocols = ["http1", "http2"] if args.protocol == "both" else [args.protocol]
    encodings = ["identity", "br"] if args.encoding == "both" else [args.encoding]
    scenarios: list[dict[str, Any]] = []
    for protocol in protocols:
        connections = args.http2_connections if protocol == "http2" else args.sse_concurrency
        for encoding in encodings:
            scenarios.extend(
                [
                    scenario_file(
                        name=f"hot-1000-{encoding}-{protocol}",
                        workload="sse",
                        protocol=protocol,
                        duration_ms=1,
                        concurrency=args.sse_concurrency,
                        connections=connections,
                        threads=args.client_threads,
                        routes=[{"path": "/hot-1000", "weight": 1}],
                        expected_events=1_000,
                        accept_encoding=encoding,
                        request_timeout_ms=max(30_000, args.duration * 1_000),
                    ),
                    scenario_file(
                        name=f"wake-100-{encoding}-{protocol}",
                        workload="sse",
                        protocol=protocol,
                        duration_ms=1,
                        concurrency=min(args.sse_concurrency, 96),
                        connections=(
                            args.http2_connections
                            if protocol == "http2"
                            else min(args.sse_concurrency, 96)
                        ),
                        threads=args.client_threads,
                        routes=[{"path": "/wake-100", "weight": 1}],
                        expected_events=2,
                        accept_encoding=encoding,
                        request_timeout_ms=10_000,
                    ),
                    scenario_file(
                        name=f"demo-2500-elements-{encoding}-{protocol}",
                        workload="sse",
                        protocol=protocol,
                        duration_ms=1,
                        concurrency=min(args.sse_concurrency, 64),
                        connections=(
                            args.http2_connections
                            if protocol == "http2"
                            else min(args.sse_concurrency, 64)
                        ),
                        threads=args.client_threads,
                        routes=[{"path": "/demo-2500-elements", "weight": 1}],
                        expected_events=25,
                        accept_encoding=encoding,
                        request_timeout_ms=15_000,
                    ),
                ]
            )
            if not args.skip_fairness:
                fairness_streams = min(args.sse_concurrency, 64)
                fairness_connections = (
                    args.http2_connections
                    if protocol == "http2"
                    else fairness_streams
                )
                scenarios.append(
                    {
                        **scenario_file(
                            name=f"fairness-sse-{encoding}-{protocol}",
                            workload="sse",
                            protocol=protocol,
                            duration_ms=1,
                            concurrency=fairness_streams,
                            connections=fairness_connections,
                            threads=args.client_threads,
                            routes=[{"path": "/hot-10000", "weight": 1}],
                            expected_events=10_000,
                            accept_encoding=encoding,
                            request_timeout_ms=120_000,
                        ),
                        "_ordinary": scenario_file(
                            name=f"fairness-ordinary-{encoding}-{protocol}",
                            protocol=protocol,
                            duration_ms=args.fairness_seconds * 1_000,
                            concurrency=64,
                            connections=(
                                args.http2_connections if protocol == "http2" else 64
                            ),
                            threads=args.client_threads,
                            routes=[{"path": "/ordinary", "weight": 1}],
                            request_timeout_ms=30_000,
                        ),
                    }
                )
            if protocol == "http1":
                for streams in args.parked_streams:
                    scenarios.append(
                        scenario_file(
                            name=f"parked-{streams}-{encoding}-{protocol}",
                            workload="sse_hold",
                            protocol=protocol,
                            duration_ms=args.hold_seconds * 1_000,
                            concurrency=streams,
                            connections=streams,
                            threads=args.client_threads,
                            routes=[{"path": "/idle", "weight": 1}],
                            expected_events=1,
                            accept_encoding=encoding,
                            request_timeout_ms=max(30_000, streams * 20),
                        )
                    )
                if args.capacity_check:
                    scenarios.extend(
                        [
                            {
                                **scenario_file(
                                    name=f"capacity-4097-{encoding}-{protocol}",
                                    workload="sse_hold",
                                    protocol=protocol,
                                    duration_ms=1_000,
                                    concurrency=4_097,
                                    connections=4_097,
                                    threads=args.client_threads,
                                    routes=[{"path": "/idle", "weight": 1}],
                                    expected_events=1,
                                    accept_encoding=encoding,
                                    request_timeout_ms=120_000,
                                    allow_errors=True,
                                ),
                                "_expect_opened": 4_096,
                                "_expect_errors": 1,
                            },
                            scenario_file(
                                name=f"capacity-recovery-{encoding}-{protocol}",
                                workload="sse",
                                protocol=protocol,
                                duration_ms=1,
                                concurrency=1,
                                connections=1,
                                threads=args.client_threads,
                                routes=[{"path": "/finite", "weight": 1}],
                                expected_events=1,
                                accept_encoding=encoding,
                                request_timeout_ms=10_000,
                            ),
                        ]
                    )
    return scenarios


def sqlite_scenarios(
    args: argparse.Namespace,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    definitions = [
        ("indexed-point-serial", "http1", 1, [("/point", 1)], "main", None),
        ("indexed-point-32", "http1", 32, [("/point", 1)], "main", None),
        ("indexed-point-64", "http1", 64, [("/point", 1)], "main", None),
        ("single-writer", "http1", 1, [("/write", 1)], "main", None),
        ("concurrent-writers", "http1", 32, [("/write", 1)], "main", None),
        ("transaction-serial", "http1", 1, [("/transaction", 1)], "main", None),
        ("transaction-32", "http1", 32, [("/transaction", 1)], "main", None),
        (
            "read-write-90-10",
            "http1",
            64,
            [("/point", 90), ("/write", 10)],
            "main",
            None,
        ),
        (
            "slow-query-isolation",
            "http1",
            96,
            [("/point", 90), ("/range-1000", 5), ("/scan", 5)],
            "main",
            None,
        ),
        ("shared-statement-serial", "http1", 1, [("/", 1)], "shared", None),
        ("shared-statement-2", "http1", 2, [("/", 1)], "shared", None),
        ("shared-statement-8", "http1", 8, [("/", 1)], "shared", None),
    ]
    if args.sqlite_suite == "full":
        definitions.extend(
            [
                ("decode-10", "http1", 16, [("/range-10", 1)], "main", None),
                ("decode-1000", "http1", 8, [("/range-1000", 1)], "main", None),
                ("decode-10000", "http1", 2, [("/range-10000", 1)], "main", 3),
                ("decode-100000", "http1", 1, [("/range-100000", 1)], "main", 3),
                ("blob-64k", "http1", 32, [("/blob-64k", 1)], "main", None),
                ("blob-1m", "http1", 8, [("/blob-1m", 1)], "main", None),
                ("full-scan", "http1", 16, [("/scan", 1)], "main", None),
                (
                    "http2-slow-query-isolation",
                    "http2",
                    96,
                    [("/point", 90), ("/range-1000", 5), ("/scan", 5)],
                    "main",
                    None,
                ),
            ]
        )
    grouped: dict[str, list[dict[str, Any]]] = {"main": [], "shared": []}
    for name, protocol, concurrency, routes, server, seconds in definitions:
        grouped[server].append(
            scenario_file(
                name=name,
                protocol=protocol,
                duration_ms=(seconds or args.duration) * 1_000,
                concurrency=concurrency,
                threads=args.client_threads,
                connections=(1 if protocol == "http2" else concurrency),
                routes=[{"path": path, "weight": weight} for path, weight in routes],
                request_timeout_ms=10_000,
                allow_errors=True,
                error_backoff_ms=1,
            )
        )
    return grouped["main"], grouped["shared"]


def invoke_driver(
    scenario: dict[str, Any],
    phase_callback: Any | None = None,
    command_prefix: tuple[str, ...] = (),
) -> list[dict[str, Any]]:
    HARNESS_ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", dir=HARNESS_ROOT, delete=False, encoding="utf-8"
    ) as scenario_file_handle:
        json.dump(scenario, scenario_file_handle)
        path = Path(scenario_file_handle.name)
    try:
        process = subprocess.Popen(
            [*command_prefix, str(DRIVER), "--scenario-file", str(path)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=None,
            text=True,
        )
        assert process.stdout is not None
        records = []
        for line in process.stdout:
            if not line.strip():
                continue
            record = json.loads(line)
            records.append(record)
            if record.get("kind") == "phase" and phase_callback is not None:
                phase_callback(record)
        returncode = process.wait()
        if returncode != 0:
            raise subprocess.CalledProcessError(returncode, process.args)
    finally:
        path.unlink(missing_ok=True)
    return records


def require_file_descriptor_capacity(scenarios: list[dict[str, Any]]) -> None:
    if os.name == "nt":
        return
    import resource

    required = max(scenario["concurrency"] for scenario in scenarios) + 256
    soft, _hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    if soft < required:
        raise SystemExit(
            f"the largest scenario needs roughly {required} file descriptors per process, "
            f"but the soft limit is {soft}; raise it with `ulimit -n {required}`"
        )


def select_scenarios(
    scenarios: list[dict[str, Any]], fragments: list[str], *, required: bool = True
) -> list[dict[str, Any]]:
    if not fragments:
        return scenarios
    selected = [
        scenario
        for scenario in scenarios
        if any(fragment.lower() in scenario["name"].lower() for fragment in fragments)
    ]
    if not selected and required:
        raise SystemExit("--only did not match any benchmark scenarios")
    return selected


def measure_group(
    args: argparse.Namespace,
    results: Any,
    binary: Path,
    scenarios: list[dict[str, Any]],
    extra_environment: dict[str, str] | None = None,
) -> None:
    require_file_descriptor_capacity(scenarios)
    if (args.server_cpu or args.client_cpu) and (
        sys.platform != "linux" or shutil.which("taskset") is None
    ):
        raise SystemExit("--server-cpu and --client-cpu require Linux taskset")
    server_prefix = ("taskset", "-c", args.server_cpu) if args.server_cpu else ()
    client_prefix = ("taskset", "-c", args.client_cpu) if args.client_cpu else ()
    environment = os.environ.copy()
    environment["TOKIO_WORKER_THREADS"] = str(args.server_workers)
    if extra_environment:
        environment.update(extra_environment)
    process = subprocess.Popen(
        [*server_prefix, str(binary)],
        cwd=ROOT,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_until_listening(process)
        write_record(
            results,
            {
                "schema_version": SCHEMA_VERSION,
                "kind": "server_process",
                "phase": "baseline",
                "server": binary.name,
                "snapshot": linux_process_snapshot(process.pid),
            },
        )
        for scenario in scenarios:
            wire_scenario = {
                key: value for key, value in scenario.items() if not key.startswith("_")
            }
            warmup = {**wire_scenario, "name": f"warmup-{scenario['name']}"}
            if scenario.get("workload", "request") == "request":
                warmup["duration_ms"] = args.warmup * 1_000
            elif scenario.get("workload") == "sse_hold":
                warmup["duration_ms"] = 1_000
            warmup_ordinary = scenario.get("_ordinary")

            def warmup_phase(phase: dict[str, Any]) -> None:
                if phase.get("phase") == "load_started" and warmup_ordinary:
                    invoke_driver(
                        {
                            **warmup_ordinary,
                            "name": f"warmup-{warmup_ordinary['name']}",
                        },
                        command_prefix=client_prefix,
                    )

            invoke_driver(warmup, warmup_phase, client_prefix)
            for sample in range(args.samples):
                print(f"==> measure {scenario['name']} sample {sample + 1}", flush=True)
                concurrent_records: list[dict[str, Any]] = []

                def record_phase(phase: dict[str, Any]) -> None:
                    write_record(
                        results,
                        {
                            "schema_version": SCHEMA_VERSION,
                            "kind": "server_process",
                            "phase": phase["phase"],
                            "scenario": scenario["name"],
                            "sample": sample + 1,
                            "driver": phase,
                            "snapshot": linux_process_snapshot(process.pid),
                        },
                    )
                    ordinary = scenario.get("_ordinary")
                    if phase.get("phase") == "load_started" and ordinary:
                        concurrent_records.extend(
                            invoke_driver(ordinary, command_prefix=client_prefix)
                        )

                measured_records = invoke_driver(
                    wire_scenario, record_phase, client_prefix
                )
                for record in [*measured_records, *concurrent_records]:
                    record["sample"] = sample + 1
                    record["label"] = args.label
                    write_record(results, record)
                expected_opened = scenario.get("_expect_opened")
                expected_errors = scenario.get("_expect_errors")
                if expected_opened is not None:
                    hold = next(
                        (
                            record
                            for record in measured_records
                            if record.get("kind") == "sse_hold_measurement"
                        ),
                        None,
                    )
                    if hold is None or hold["opened_streams"] != expected_opened:
                        raise SystemExit(
                            f"{scenario['name']} expected {expected_opened} opened streams"
                        )
                    if expected_errors is not None and hold["errors"] != expected_errors:
                        raise SystemExit(
                            f"{scenario['name']} expected {expected_errors} rejected streams"
                        )
            write_record(
                results,
                {
                    "schema_version": SCHEMA_VERSION,
                    "kind": "server_process",
                    "phase": "recovered",
                    "scenario": scenario["name"],
                    "snapshot": linux_process_snapshot(process.pid),
                },
            )
    finally:
        stop_server(process)


def measure(args: argparse.Namespace) -> None:
    if not args.skip_build:
        apps: list[tuple[Path, Path]] = []
        if args.suite in {"http", "all"}:
            apps.append((HTTP_SOURCE, HTTP_BINARY))
        if args.suite in {"sse", "all"}:
            apps.append((SSE_SOURCE, SSE_BINARY))
        if args.suite == "sqlite":
            apps.extend(
                [
                    (SQLITE_SOURCE, SQLITE_BINARY),
                    (SQLITE_SHARED_SOURCE, SQLITE_SHARED_BINARY),
                ]
            )
        build_production_apps(apps)
        build_driver()
    required = [DRIVER]
    if args.suite in {"http", "all"}:
        required.append(HTTP_BINARY)
    if args.suite in {"sse", "all"}:
        required.append(SSE_BINARY)
    if args.suite == "sqlite":
        required.extend([SQLITE_BINARY, SQLITE_SHARED_BINARY])
    if any(not path.is_file() for path in required):
        raise SystemExit("benchmark binaries are missing; rerun without --skip-build")

    destination = args.output.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", encoding="utf-8") as results:
        write_record(results, environment_record(args.label))
        write_record(
            results,
            {
                "schema_version": SCHEMA_VERSION,
                "kind": "run_configuration",
                "server_cpu": args.server_cpu,
                "client_cpu": args.client_cpu,
                "server_workers": args.server_workers,
                "client_threads": args.client_threads,
                "samples": args.samples,
                "warmup_seconds": args.warmup,
            },
        )
        if args.suite in {"http", "all"}:
            selected = select_scenarios(
                http_scenarios(args), args.only, required=args.suite == "http"
            )
            if selected:
                measure_group(args, results, HTTP_BINARY, selected)
        if args.suite in {"sse", "all"}:
            selected = select_scenarios(
                sse_scenarios(args), args.only, required=args.suite == "sse"
            )
            if selected:
                measure_group(args, results, SSE_BINARY, selected)
        if args.suite == "sqlite":
            if args.pool_size > 64:
                raise SystemExit("--pool-size must be at most 64")
            create_sqlite_fixture(SQLITE_DATABASE, args.rows, args.rebuild_database)
            main_scenarios, shared_scenarios = sqlite_scenarios(args)
            if args.only:
                combined = select_scenarios(
                    [*main_scenarios, *shared_scenarios], args.only
                )
                selected_names = {scenario["name"] for scenario in combined}
                main_scenarios = [
                    scenario
                    for scenario in main_scenarios
                    if scenario["name"] in selected_names
                ]
                shared_scenarios = [
                    scenario
                    for scenario in shared_scenarios
                    if scenario["name"] in selected_names
                ]
            sqlite_environment = {
                "SQLITE_BENCH_DB": str(SQLITE_DATABASE.resolve()),
                "SQLITE_BENCH_POOL": str(args.pool_size),
            }
            if main_scenarios:
                measure_group(
                    args,
                    results,
                    SQLITE_BINARY,
                    main_scenarios,
                    sqlite_environment,
                )
            if shared_scenarios:
                measure_group(
                    args,
                    results,
                    SQLITE_SHARED_BINARY,
                    shared_scenarios,
                    sqlite_environment,
                )
    print(f"Wrote {destination}", flush=True)


def load_measurements(
    path: Path,
) -> dict[tuple[str, str, str, str], dict[str, float]]:
    grouped: dict[tuple[str, str, str, str], dict[str, list[float]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for line in path.read_text(encoding="utf-8").splitlines():
        record = json.loads(line)
        kind = record.get("kind")
        if kind == "measurement":
            key = ("http", record["scenario"], record["protocol"], record["route"])
            grouped[key]["primary"].append(float(record["requests_per_second"]))
            grouped[key]["tail"].append(float(record["latency_ms_p99"]))
            grouped[key]["errors"].append(float(record["errors"]))
        elif kind == "sse_measurement":
            key = ("sse", record["scenario"], record["protocol"], record["route"])
            grouped[key]["primary"].append(float(record["events_per_second"]))
            grouped[key]["tail"].append(float(record["completion_ms_p99"]))
            grouped[key]["errors"].append(float(record["errors"]))
        elif kind == "sse_hold_measurement":
            key = ("sse-hold", record["scenario"], record["protocol"], record["route"])
            grouped[key]["primary"].append(float(record["opened_streams"]))
            grouped[key]["tail"].append(float(record["first_byte_ms_p99"]))
            grouped[key]["errors"].append(float(record["errors"]))
        elif kind == "server_process" and record.get("phase") == "streams_ready":
            snapshot = record.get("snapshot", {})
            if not snapshot.get("supported") or snapshot.get("rss_kib") is None:
                continue
            scenario = record.get("scenario", "unknown")
            key = ("parked-memory", scenario, "-", "rss")
            grouped[key]["primary"].append(float(snapshot["rss_kib"]))
            grouped[key]["tail"].append(float(snapshot.get("pss_kib") or 0))
            grouped[key]["errors"].append(0.0)
        elif kind == "simulation":
            requests = max(1, int(record["requests"]))
            for domain in ("host", "roc_backing", "roc_requested"):
                allocation = record["allocations"][domain]
                key = (
                    "allocation",
                    record["scenario"],
                    record["protocol"],
                    domain,
                )
                grouped[key]["primary"].append(
                    float(allocation["allocated_bytes"]) / requests
                )
                grouped[key]["tail"].append(float(allocation["peak_live_bytes"]))
                grouped[key]["errors"].append(float(len(record.get("errors", []))))
        else:
            continue
    return {
        key: {metric: statistics.median(values) for metric, values in metrics.items()}
        for key, metrics in grouped.items()
    }


def percentage(before: float, after: float) -> str:
    if before == 0:
        return "n/a" if after != 0 else "0.0%"
    return f"{(after - before) * 100.0 / before:+.1f}%"


def compare(args: argparse.Namespace) -> None:
    before = load_measurements(args.before)
    after = load_measurements(args.after)
    keys = sorted(before.keys() & after.keys())
    if not keys:
        raise SystemExit("the result files have no matching measurements")
    lines = [
        "| Kind | Scenario | Protocol | Route | Primary before | Primary after | Primary Δ | Secondary before | Secondary after | Secondary Δ |",
        "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for kind, scenario, protocol_name, route in keys:
        old = before[(kind, scenario, protocol_name, route)]
        new = after[(kind, scenario, protocol_name, route)]
        lines.append(
            "| "
            + " | ".join(
                [
                    kind,
                    scenario,
                    protocol_name,
                    route,
                    f"{old['primary']:.1f}",
                    f"{new['primary']:.1f}",
                    percentage(old["primary"], new["primary"]),
                    f"{old['tail']:.3f}",
                    f"{new['tail']:.3f}",
                    percentage(old["tail"], new["tail"]),
                ]
            )
            + " |"
        )
    rendered = "\n".join(lines) + "\n"
    if args.markdown:
        args.markdown.write_text(rendered, encoding="utf-8")
        print(f"Wrote {args.markdown}")
    else:
        print(rendered, end="")


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_parser = subparsers.add_parser(
        "check", help="run socketless real-Roc invariant scenarios"
    )
    check_parser.add_argument("--skip-build", action="store_true")
    check_parser.add_argument("--timeout", type=positive, default=120)
    check_parser.add_argument("--output", type=Path)
    check_parser.add_argument("--label", default="check")
    check_parser.set_defaults(action=check)

    measure_parser = subparsers.add_parser(
        "measure", help="run local real-TCP measurements"
    )
    measure_parser.add_argument("--output", type=Path, required=True)
    measure_parser.add_argument("--label", required=True)
    measure_parser.add_argument("--duration", type=positive, default=10)
    measure_parser.add_argument("--warmup", type=positive, default=2)
    measure_parser.add_argument("--samples", type=positive, default=3)
    measure_parser.add_argument("--concurrency", type=positive, default=64)
    measure_parser.add_argument("--sse-concurrency", type=positive, default=64)
    measure_parser.add_argument(
        "--parked-streams",
        type=positive_csv,
        default=[100, 1_000, 2_500],
        help="comma-separated HTTP/1.1 parked SSE counts",
    )
    measure_parser.add_argument("--hold-seconds", type=positive, default=5)
    measure_parser.add_argument("--fairness-seconds", type=positive, default=2)
    measure_parser.add_argument("--skip-fairness", action="store_true")
    measure_parser.add_argument(
        "--capacity-check",
        action="store_true",
        help="open 4,097 streams, assert the 4,096-stream bound, then recover",
    )
    measure_parser.add_argument("--http2-connections", type=positive, default=1)
    measure_parser.add_argument(
        "--server-workers", type=positive, default=max(1, (os.cpu_count() or 2) // 2)
    )
    measure_parser.add_argument(
        "--client-threads", type=positive, default=max(1, (os.cpu_count() or 2) // 2)
    )
    measure_parser.add_argument("--server-cpu", type=cpu_set)
    measure_parser.add_argument("--client-cpu", type=cpu_set)
    measure_parser.add_argument(
        "--protocol", choices=("http1", "http2", "both"), default="both"
    )
    measure_parser.add_argument(
        "--encoding", choices=("identity", "br", "both"), default="both"
    )
    measure_parser.add_argument(
        "--suite", choices=("http", "sse", "sqlite", "all"), default="http"
    )
    measure_parser.add_argument("--rows", type=positive, default=250_000)
    measure_parser.add_argument("--pool-size", type=positive, default=8)
    measure_parser.add_argument("--rebuild-database", action="store_true")
    measure_parser.add_argument(
        "--sqlite-suite", choices=("core", "full"), default="full"
    )
    measure_parser.add_argument("--skip-build", action="store_true")
    measure_parser.add_argument(
        "--only",
        action="append",
        default=[],
        help="run scenarios whose names contain this text; may be repeated",
    )
    measure_parser.set_defaults(action=measure)

    compare_parser = subparsers.add_parser(
        "compare", help="render a before/after Markdown summary"
    )
    compare_parser.add_argument("before", type=Path)
    compare_parser.add_argument("after", type=Path)
    compare_parser.add_argument("--markdown", type=Path)
    compare_parser.set_defaults(action=compare)

    return parser.parse_args()


def main() -> None:
    args = arguments()
    args.action(args)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
