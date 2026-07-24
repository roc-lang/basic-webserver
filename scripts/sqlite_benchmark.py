#!/usr/bin/env python3
"""Run local-only SQLite load experiments against a compiled Roc application."""

from __future__ import annotations

import argparse
import os
import signal
import socket
import sqlite3
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PERF_DIR = ROOT / "target" / "perf-harness"
DATABASE = PERF_DIR / "sqlite-load.db"
SERVER = PERF_DIR / (
    "basic-webserver-sqlite-benchmark.exe"
    if os.name == "nt"
    else "basic-webserver-sqlite-benchmark"
)
SHARED_SERVER = PERF_DIR / (
    "basic-webserver-sqlite-shared-benchmark.exe"
    if os.name == "nt"
    else "basic-webserver-sqlite-shared-benchmark"
)
LOAD = ROOT / "target" / "release" / (
    "local-load.exe" if os.name == "nt" else "local-load"
)


@dataclass(frozen=True)
class Scenario:
    name: str
    protocol: str
    concurrency: int
    path: str | None = None
    routes: str | None = None
    seconds: int | None = None
    server: str = "main"


def positive(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create a deterministic SQLite fixture and run local-only load "
            "experiments. Results are exploratory and never used as CI thresholds."
        )
    )
    parser.add_argument("--rows", type=positive, default=250_000)
    parser.add_argument("--duration", type=positive, default=5)
    parser.add_argument("--warmup", type=positive, default=1)
    parser.add_argument(
        "--server-workers",
        type=positive,
        default=max(1, (os.cpu_count() or 2) // 2),
    )
    parser.add_argument(
        "--client-threads",
        type=positive,
        default=max(1, (os.cpu_count() or 2) // 2),
    )
    parser.add_argument(
        "--pool-size",
        type=positive,
        default=8,
        help="SQLite connections opened by the compiled Roc application (1-64)",
    )
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--rebuild-database", action="store_true")
    parser.add_argument(
        "--suite",
        choices=("core", "full"),
        default="full",
        help="core runs scaling/contention; full adds large results and HTTP/2",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        help="run scenarios whose names contain this text; may be repeated",
    )
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
            "scripts/perf/sqlite_app.roc",
        ]
    )
    run(
        [
            "roc",
            "build",
            "--opt=speed",
            f"--output={SHARED_SERVER}",
            "scripts/perf/sqlite_shared_app.roc",
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


def fixture_matches(path: Path, rows: int) -> bool:
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


def create_database(path: Path, rows: int, rebuild: bool) -> None:
    if rows < 125_000:
        raise SystemExit("--rows must be at least 125000 for the fixed point query")
    if not rebuild and fixture_matches(path, rows):
        print(f"Reusing SQLite fixture with {rows:,} rows: {path}", flush=True)
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".building.db")
    for stale in (
        temporary,
        temporary.with_name(temporary.name + "-shm"),
        temporary.with_name(temporary.name + "-wal"),
    ):
        if stale.exists():
            stale.unlink()

    print(f"Creating SQLite fixture with {rows:,} rows...", flush=True)
    started = time.monotonic()
    with sqlite3.connect(temporary) as connection:
        connection.execute("PRAGMA journal_mode=OFF")
        connection.execute("PRAGMA synchronous=OFF")
        connection.execute("PRAGMA temp_store=MEMORY")
        connection.executescript(
            """
            CREATE TABLE benchmark_meta (
                name TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE records (
                id INTEGER PRIMARY KEY,
                category TEXT NOT NULL,
                indexed_value INTEGER NOT NULL,
                unindexed_text TEXT NOT NULL,
                body TEXT NOT NULL
            );
            CREATE TABLE payloads (
                id INTEGER PRIMARY KEY,
                payload BLOB NOT NULL
            );
            CREATE TABLE counters (
                id INTEGER PRIMARY KEY,
                value INTEGER NOT NULL
            );
            """
        )
        batch_size = 10_000
        body_suffix = "x" * 112
        for first in range(1, rows + 1, batch_size):
            last = min(rows + 1, first + batch_size)
            batch = [
                (
                    row_id,
                    f"category-{row_id % 100}",
                    row_id % 10_000,
                    "needle" if row_id % 10_000 == 0 else f"haystack-{row_id % 4096}",
                    f"record-{row_id}-{body_suffix}",
                )
                for row_id in range(first, last)
            ]
            connection.executemany(
                """
                INSERT INTO records
                    (id, category, indexed_value, unindexed_text, body)
                VALUES (?, ?, ?, ?, ?)
                """,
                batch,
            )
            if first % 100_000 == 1:
                print(f"  inserted {last - 1:,}/{rows:,}", flush=True)

        connection.execute("CREATE INDEX records_category ON records(category)")
        connection.execute(
            "CREATE INDEX records_indexed_value ON records(indexed_value)"
        )
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
        if existing.exists():
            existing.unlink()
    os.replace(temporary, path)
    print(
        f"SQLite fixture ready in {time.monotonic() - started:.1f}s "
        f"({path.stat().st_size / (1024 * 1024):.1f} MiB)",
        flush=True,
    )


def wait_until_listening(process: subprocess.Popen[bytes]) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise SystemExit(f"SQLite benchmark server exited with {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise SystemExit("SQLite benchmark server did not listen on 127.0.0.1:8000")


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


def scenarios(suite: str) -> list[Scenario]:
    core = [
        Scenario("indexed point read", "http1", 1, path="/point"),
        Scenario("indexed point read at concurrency 32", "http1", 32, path="/point"),
        Scenario("indexed point read under load", "http1", 64, path="/point"),
        Scenario("single writer", "http1", 1, path="/write"),
        Scenario("concurrent writers", "http1", 32, path="/write"),
        Scenario("transactional writer", "http1", 1, path="/transaction"),
        Scenario(
            "concurrent transactional writers",
            "http1",
            32,
            path="/transaction",
        ),
        Scenario(
            "90/10 read-write mixture",
            "http1",
            64,
            routes="/point=90,/write=10",
        ),
        Scenario(
            "slow-query isolation with queueing",
            "http1",
            96,
            routes="/point=90,/range-1000=5,/scan=5",
        ),
        Scenario(
            "shared prepared statement serial",
            "http1",
            1,
            path="/",
            server="shared",
        ),
        Scenario(
            "shared prepared statement contention 2",
            "http1",
            2,
            path="/",
            server="shared",
        ),
        Scenario(
            "shared prepared statement contention 8",
            "http1",
            8,
            path="/",
            server="shared",
        ),
    ]
    if suite == "core":
        return core
    return [
        *core,
        Scenario("decode 10 rows", "http1", 16, path="/range-10"),
        Scenario("decode 1,000 rows", "http1", 8, path="/range-1000"),
        Scenario("decode 10,000 rows", "http1", 2, path="/range-10000", seconds=3),
        Scenario("decode 100,000 rows", "http1", 1, path="/range-100000", seconds=3),
        Scenario("64 KiB blob", "http1", 32, path="/blob-64k"),
        Scenario("1 MiB blob", "http1", 8, path="/blob-1m"),
        Scenario("unindexed full scan", "http1", 16, path="/scan"),
        Scenario(
            "HTTP/2 slow-query isolation",
            "http2",
            96,
            routes="/point=90,/range-1000=5,/scan=5",
        ),
    ]


def load_command(
    args: argparse.Namespace, scenario: Scenario, duration: int
) -> list[str]:
    command = [
        str(LOAD),
        "--protocol",
        scenario.protocol,
        "--duration",
        str(duration),
        "--concurrency",
        str(scenario.concurrency),
        "--threads",
        str(args.client_threads),
        "--allow-errors",
        "--error-backoff-ms",
        "1",
    ]
    if scenario.protocol == "http2":
        command.extend(["--connections", "1"])
    if scenario.routes is not None:
        command.extend(["--routes", scenario.routes])
    elif scenario.path is not None:
        command.extend(["--path", scenario.path])
    else:
        raise AssertionError("scenario needs a path or weighted routes")
    return command


def process_memory(process: subprocess.Popen[bytes]) -> str | None:
    status = Path(f"/proc/{process.pid}/status")
    if not status.is_file():
        return None
    values: dict[str, str] = {}
    for line in status.read_text().splitlines():
        name, separator, value = line.partition(":")
        if separator and name in {"VmRSS", "VmHWM"}:
            values[name] = value.strip()
    if not values:
        return None
    return f"rss={values.get('VmRSS', '?')} high_water={values.get('VmHWM', '?')}"


def run_scenarios(
    args: argparse.Namespace,
    binary: Path,
    selected: list[Scenario],
    environment: dict[str, str],
) -> None:
    if not selected:
        return
    process = subprocess.Popen(
        [str(binary)],
        cwd=ROOT,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_until_listening(process)
        for scenario in selected:
            duration = scenario.seconds or args.duration
            print(
                f"==> warmup: {scenario.name} "
                f"({scenario.protocol}, concurrency={scenario.concurrency})",
                flush=True,
            )
            run(
                load_command(args, scenario, args.warmup),
                stdout=subprocess.DEVNULL,
            )
            print(f"==> measure: {scenario.name}", flush=True)
            run(load_command(args, scenario, duration))
            memory = process_memory(process)
            if memory is not None:
                print(f"server_memory {memory}", flush=True)
    finally:
        stop_server(process)


def main() -> None:
    args = arguments()
    if not args.skip_build:
        build()
    if not SERVER.is_file() or not SHARED_SERVER.is_file() or not LOAD.is_file():
        raise SystemExit("benchmark binaries are missing; rerun without --skip-build")
    create_database(DATABASE, args.rows, args.rebuild_database)

    environment = os.environ.copy()
    environment["SQLITE_BENCH_DB"] = str(DATABASE.resolve())
    if args.pool_size > 64:
        raise SystemExit("--pool-size must be at most 64")
    environment["SQLITE_BENCH_POOL"] = str(args.pool_size)
    environment["TOKIO_WORKER_THREADS"] = str(args.server_workers)
    print(
        f"\nSQLite exploratory run: rows={args.rows:,}, "
        f"server_workers={args.server_workers}, "
        f"client_threads={args.client_threads}, "
        f"sqlite_pool={args.pool_size}\n"
        "The compiled Roc app has 64 active and 64 queued handler slots. "
        "Non-200 responses are reported rather than aborting the suite.\n",
        flush=True,
    )
    selected = scenarios(args.suite)
    if args.only:
        selected = [
            scenario
            for scenario in selected
            if any(fragment.lower() in scenario.name.lower() for fragment in args.only)
        ]
        if not selected:
            raise SystemExit("--only did not match any benchmark scenarios")
    run_scenarios(
        args,
        SERVER,
        [scenario for scenario in selected if scenario.server == "main"],
        environment,
    )
    run_scenarios(
        args,
        SHARED_SERVER,
        [scenario for scenario in selected if scenario.server == "shared"],
        environment,
    )


if __name__ == "__main__":
    main()
