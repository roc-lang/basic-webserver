#!/usr/bin/env python3
"""Build and exercise every active basic-webserver application.

The JSON specification is intentionally the single source of truth for test
discovery and runtime behaviour. The runner uses only Python's standard
library so that the same cases run on every supported host OS.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import http.client
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Iterator


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "scripts" / "test_spec.json"
VALIDATION_ROOT = ROOT / "target" / "spec"
DEFAULT_ARTIFACT_DIR = ROOT / "dist" / "example-binaries"
STAGES = ("fmt", "check", "test", "build", "run")
PLATFORMS = {"linux", "darwin", "windows"}
TARGETS = ("x64mac", "arm64mac", "x64musl", "arm64musl", "x64win")
PORTABLE_TEXT_SUFFIXES = {".html", ".json", ".py", ".roc"}
TARGET_PLATFORMS = {
    "x64mac": "darwin",
    "arm64mac": "darwin",
    "x64musl": "linux",
    "arm64musl": "linux",
    "x64win": "windows",
}
ISSUE_URL = re.compile(r"^https://github\.com/[^/]+/[^/]+/issues/[1-9][0-9]*$")
LISTENING = re.compile(r"Listening on <http://(?:\[.*\]|[^:]+):([0-9]+)>")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")


class TestFailure(RuntimeError):
    pass


def fail(message: str) -> None:
    raise TestFailure(message)


def normalize_text(value: str) -> str:
    return value.replace("\r\n", "\n").replace("\r", "\n")


def portable_text_bytes(path: Path) -> bytes:
    return normalize_text(path.read_text(encoding="utf-8")).encode("utf-8")


def portable_file_bytes(path: Path) -> bytes:
    if path.suffix in PORTABLE_TEXT_SUFFIXES:
        return portable_text_bytes(path)
    return path.read_bytes()


def command(*args: str | Path, cwd: Path = ROOT) -> None:
    values = [str(arg) for arg in args]
    print(f"+ {' '.join(values)}", flush=True)
    subprocess.run(values, cwd=cwd, check=True)


def active_sources() -> set[str]:
    return {
        str(path.relative_to(ROOT).as_posix())
        for directory in (ROOT / "examples",)
        for path in directory.glob("*.roc")
    }


def declared_targets() -> tuple[str, ...]:
    source = (ROOT / "platform" / "main.roc").read_text(encoding="utf-8")
    match = re.search(r"(?ms)^\s*targets:\s*\{(.*?)^\s*\}", source)
    if match is None:
        fail("platform/main.roc: targets block was not found")
    targets = tuple(
        re.findall(r"(?m)^\s*([A-Za-z0-9_]+):\s*\{\s*inputs:", match.group(1))
    )
    if set(targets) != set(TARGETS):
        fail(
            f"Platform/test target mismatch; "
            f"missing={sorted(set(TARGETS) - set(targets))}, "
            f"extra={sorted(set(targets) - set(TARGETS))}"
        )
    return targets


def detect_native_target() -> str:
    system = platform.system()
    machine = platform.machine().lower()
    if system == "Windows" and machine in {"amd64", "x86_64"}:
        return "x64win"
    if system == "Darwin":
        if machine in {"arm64", "aarch64"}:
            return "arm64mac"
        if machine in {"amd64", "x86_64"}:
            return "x64mac"
    if system == "Linux":
        if machine in {"arm64", "aarch64"}:
            return "arm64musl"
        if machine in {"amd64", "x86_64"}:
            return "x64musl"
    fail(f"Unsupported native platform: {system} {machine}")
    raise AssertionError


def validate_skip(owner: str, value: object) -> None:
    if not isinstance(value, dict):
        fail(f"{owner}: skip must be an object")
    if set(value) != {"platforms", "reason", "issue"}:
        fail(f"{owner}: skip must contain exactly platforms, reason, and issue")
    platforms = value["platforms"]
    if (
        not isinstance(platforms, list)
        or not platforms
        or not all(isinstance(item, str) and item in PLATFORMS for item in platforms)
        or len(platforms) != len(set(platforms))
    ):
        fail(f"{owner}: skip.platforms must be unique values from {sorted(PLATFORMS)}")
    if not isinstance(value["reason"], str) or not value["reason"].strip():
        fail(f"{owner}: a skipped case requires a non-empty reason")
    if not isinstance(value["issue"], str) or not ISSUE_URL.fullmatch(value["issue"]):
        fail(f"{owner}: a skipped case requires a GitHub tracking issue URL")


def validate_assertions(owner: str, value: dict[str, object], prefix: str = "") -> None:
    allowed = {
        f"{prefix}exact",
        f"{prefix}contains",
        f"{prefix}regex",
    }
    for key in allowed & set(value):
        assertion = value[key]
        if key.endswith("exact") and not isinstance(assertion, str):
            fail(f"{owner}: {key} must be a string")
        if not key.endswith("exact") and (
            not isinstance(assertion, list)
            or not all(isinstance(item, str) for item in assertion)
        ):
            fail(f"{owner}: {key} must be an array of strings")


def reject_platform_variants(owner: str, value: object) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in {"platforms", "expectations", *PLATFORMS}:
                fail(f"{owner}: platform-specific expectations are forbidden")
            reject_platform_variants(owner, child)
    elif isinstance(value, list):
        for child in value:
            reject_platform_variants(owner, child)


def validate_case(app_path: str, case: object, names: set[str]) -> None:
    if not isinstance(case, dict):
        fail(f"{app_path}: each case must be an object")
    name = case.get("name")
    if not isinstance(name, str) or not name:
        fail(f"{app_path}: each case needs a non-empty name")
    if name in names:
        fail(f"{app_path}: duplicate case name {name!r}")
    names.add(name)
    owner = f"{app_path} [{name}]"
    if "skip" in case:
        validate_skip(owner, case["skip"])
    for key, value in case.items():
        if key != "skip":
            reject_platform_variants(owner, value)
    for prefix in ("", "stdout_", "stderr_", "body_", "response_"):
        validate_assertions(owner, case, prefix)
    env = case.get("env", {})
    if not isinstance(env, dict) or not all(
        isinstance(key, str) and isinstance(value, str) for key, value in env.items()
    ):
        fail(f"{owner}: env must be an object of strings")
    fixtures = case.get("fixtures", [])
    if not isinstance(fixtures, list) or not all(
        isinstance(item, dict)
        and set(item) == {"source", "dest"}
        and isinstance(item["source"], str)
        and isinstance(item["dest"], str)
        for item in fixtures
    ):
        fail(f"{owner}: fixtures must contain source/dest string objects")


def load_spec() -> tuple[dict[str, bool], list[dict[str, object]]]:
    try:
        data = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{SPEC_PATH}: {error}")
    if not isinstance(data, dict) or set(data) != {"stages", "apps"}:
        fail(f"{SPEC_PATH}: root must contain exactly stages and apps")
    defaults = data["stages"]
    apps = data["apps"]
    if (
        not isinstance(defaults, dict)
        or set(defaults) != set(STAGES)
        or not all(isinstance(defaults[name], bool) for name in STAGES)
    ):
        fail(f"{SPEC_PATH}: stages must define boolean values for {', '.join(STAGES)}")
    if not isinstance(apps, list) or not all(isinstance(app, dict) for app in apps):
        fail(f"{SPEC_PATH}: apps must be an array of objects")

    paths: list[str] = []
    for app in apps:
        path = app.get("path")
        mode = app.get("mode")
        if not isinstance(path, str):
            fail(f"{SPEC_PATH}: every app needs a string path")
        if mode not in ("process", "server"):
            fail(f"{path}: mode must be process or server")
        if "platforms" in app or "expectations" in app:
            fail(f"{path}: platform-specific expectations are forbidden")
        if "skip" in app:
            validate_skip(path, app["skip"])
        overrides = app.get("stages", {})
        if not isinstance(overrides, dict) or not set(overrides).issubset(STAGES):
            fail(f"{path}: stages contains an unknown stage")
        if not all(isinstance(value, bool) for value in overrides.values()):
            fail(f"{path}: stage overrides must be booleans")
        cases = app.get("cases")
        if not isinstance(cases, list) or not cases:
            fail(f"{path}: cases must be a non-empty array")
        names: set[str] = set()
        for case in cases:
            validate_case(path, case, names)
        paths.append(path)

    if len(paths) != len(set(paths)):
        fail(f"{SPEC_PATH}: app paths must be unique")
    discovered = active_sources()
    specified = set(paths)
    if discovered != specified:
        fail(
            f"Test spec discovery mismatch; missing={sorted(discovered - specified)}, "
            f"extra={sorted(specified - discovered)}"
        )
    return defaults, apps


def stage_enabled(defaults: dict[str, bool], app: dict[str, object], stage: str) -> bool:
    overrides = app.get("stages", {})
    assert isinstance(overrides, dict)
    value = overrides.get(stage, defaults[stage])
    assert isinstance(value, bool)
    return value


def current_platform() -> str:
    name = platform.system().lower()
    if name not in PLATFORMS:
        fail(f"Unsupported test host platform: {name}")
    return name


def skip_for_current(value: dict[str, object]) -> tuple[str, str] | None:
    skip = value.get("skip")
    if not isinstance(skip, dict) or current_platform() not in skip["platforms"]:
        return None
    return str(skip["reason"]), str(skip["issue"])


def executable_suffix(target: str) -> str:
    return ".exe" if target == "x64win" else ""


def output_path(source: Path, target: str, artifact_dir: Path) -> Path:
    return artifact_dir / target / f"{source.stem}{executable_suffix(target)}"


def prepare_artifact_output(target: str, artifact_dir: Path) -> None:
    output_dir = artifact_dir / target
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)


def readme_example(*, use_local_platform: bool = True) -> Path:
    source = (ROOT / "README.md").read_text(encoding="utf-8")
    match = re.search(r"(?ms)^```roc\n(.*?)^```$", source)
    if match is None:
        fail("README example check failed: no Roc code block found")
    directory = VALIDATION_ROOT / "readme"
    directory.mkdir(parents=True, exist_ok=True)
    rewritten = match.group(1)
    if use_local_platform:
        local_platform = os.path.relpath(
            ROOT / "platform" / "main.roc", directory
        ).replace(os.sep, "/")
        rewritten = re.sub(
            r'(?m)^(\s*pf:\s*platform\s+)"[^"]+"',
            lambda dependency: f'{dependency.group(1)}"{local_platform}"',
            rewritten,
            count=1,
        )
    path = directory / "readme.roc"
    path.write_text(rewritten, encoding="utf-8", newline="\n")
    return path


class Capture:
    def __init__(self, pipe: object) -> None:
        self.pipe = pipe
        self.data = bytearray()
        self.condition = threading.Condition()
        self.thread = threading.Thread(target=self._read, daemon=True)

    def _read(self) -> None:
        while True:
            chunk = os.read(self.pipe.fileno(), 4096)  # type: ignore[attr-defined]
            if not chunk:
                break
            with self.condition:
                self.data.extend(chunk)
                self.condition.notify_all()
        with self.condition:
            self.condition.notify_all()

    def start(self) -> None:
        self.thread.start()

    def text(self) -> str:
        with self.condition:
            return self.data.decode("utf-8", errors="replace")

    def wait_for(self, pattern: re.Pattern[str], process: subprocess.Popen[bytes], timeout: float) -> re.Match[str]:
        deadline = time.monotonic() + timeout
        with self.condition:
            while True:
                match = pattern.search(self.data.decode("utf-8", errors="replace"))
                if match is not None:
                    return match
                if process.poll() is not None:
                    fail(f"process exited before readiness with code {process.returncode}")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    fail(f"timed out after {timeout}s waiting for {pattern.pattern!r}")
                self.condition.wait(min(remaining, 0.1))


def expanded(value: str, source: Path, temp: Path) -> str:
    return value.format(
        root=ROOT,
        source=source,
        source_dir=source.parent,
        temp=temp,
        python=Path(sys.executable).resolve(),
    )


def case_environment(case: dict[str, object], source: Path, temp: Path) -> dict[str, str]:
    env = os.environ.copy()
    for name in case.get("unset_env", []):
        env.pop(str(name), None)
    values = case.get("env", {})
    assert isinstance(values, dict)
    for name, value in values.items():
        env[str(name)] = expanded(str(value), source, temp)
    return env


def install_fixtures(case: dict[str, object], source: Path, temp: Path) -> None:
    fixtures = case.get("fixtures", [])
    assert isinstance(fixtures, list)
    for fixture in fixtures:
        assert isinstance(fixture, dict)
        src = Path(expanded(str(fixture["source"]), source, temp))
        dest = Path(expanded(str(fixture["dest"]), source, temp))
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)


def assertion_text(
    owner: str, stream: str, actual: str, spec: dict[str, object], prefix: str = ""
) -> None:
    normalized = normalize_text(actual)
    if "[ROC CRASHED]" in normalized:
        fail(f"{owner}: Roc crashed\n--- {stream} ---\n{normalized}")
    exact = spec.get(f"{prefix}exact")
    if exact is not None and normalized != normalize_text(str(exact)):
        fail(
            f"{owner}: unexpected {stream}\n--- expected ---\n{normalize_text(str(exact))}"
            f"\n--- actual ---\n{normalized}"
        )
    for expected in spec.get(f"{prefix}contains", []):
        if str(expected) not in normalized:
            fail(f"{owner}: {stream} missing {expected!r}\n--- {stream} ---\n{normalized}")
    for pattern in spec.get(f"{prefix}regex", []):
        if re.search(str(pattern), normalized, re.MULTILINE | re.DOTALL) is None:
            fail(f"{owner}: {stream} did not match /{pattern}/\n--- {stream} ---\n{normalized}")


class FixtureHttpHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        if self.path == "/utf8test":
            body, content_type = b"Hello utf8", "text/plain"
        elif self.path == "/":
            body, content_type = b'{"foo":"Hello Json!"}', "application/json"
        elif self.path == "/example":
            body, content_type = b"<html><body>Example Domain</body></html>", "text/html"
        elif self.path == "/large":
            body, content_type = b"x" * 64, "application/octet-stream"
        elif self.path == "/slow":
            time.sleep(0.2)
            body, content_type = b"late", "text/plain"
        else:
            body, content_type = b"<html>\n</html>\n", "text/html"
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # Timeout tests deliberately close before the delayed fixture
            # response is written.
            pass

    def log_message(self, _format: str, *_args: object) -> None:
        pass


class TcpEchoServer:
    def __init__(self) -> None:
        self.socket = socket.socket()
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind(("127.0.0.1", 8085))
        self.socket.listen()
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def _serve(self) -> None:
        self.socket.settimeout(0.2)
        while not self.stop.is_set():
            try:
                connection, _ = self.socket.accept()
            except TimeoutError:
                continue
            except OSError:
                if self.stop.is_set():
                    return
                raise
            with connection:
                while True:
                    data = connection.recv(65536)
                    if not data:
                        break
                    connection.sendall(data)

    def __enter__(self) -> "TcpEchoServer":
        self.thread.start()
        return self

    def __exit__(self, *_args: object) -> None:
        self.stop.set()
        self.socket.close()
        self.thread.join(timeout=2)


@contextlib.contextmanager
def helper(name: object) -> Iterator[None]:
    if name is None:
        yield
    elif name == "http":
        server = ThreadingHTTPServer(("127.0.0.1", 9000), FixtureHttpHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
    elif name == "tcp":
        with TcpEchoServer():
            yield
    else:
        fail(f"unknown helper {name!r}")


def process_cwd(case: dict[str, object], temp: Path) -> Path:
    cwd = case.get("cwd", "root")
    if cwd == "root":
        return ROOT
    if cwd == "temp":
        return temp
    fail(f"invalid cwd {cwd!r}")
    raise AssertionError


def run_process_case(binary: Path, source: Path, case: dict[str, object], owner: str) -> None:
    timeout = float(case.get("timeout", 10))
    with tempfile.TemporaryDirectory(prefix="basic-webserver-spec-") as raw_temp:
        temp = Path(raw_temp)
        install_fixtures(case, source, temp)
        env = case_environment(case, source, temp)
        args = [str(binary), *[expanded(str(arg), source, temp) for arg in case.get("args", [])]]
        with helper(case.get("helper")):
            try:
                result = subprocess.run(
                    args,
                    cwd=process_cwd(case, temp),
                    env=env,
                    input=str(case.get("stdin", "")).encode(),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=timeout,
                )
            except subprocess.TimeoutExpired:
                fail(f"{owner}: timed out after {timeout}s")
        expected_exit = int(case.get("exit_code", 0))
        stdout = result.stdout.decode("utf-8", errors="replace")
        stderr = result.stderr.decode("utf-8", errors="replace")
        if result.returncode != expected_exit:
            fail(
                f"{owner}: expected exit {expected_exit}, got {result.returncode}"
                f"\n--- stdout ---\n{stdout}\n--- stderr ---\n{stderr}"
            )
        assertion_text(owner, "stdout", stdout, case, "stdout_")
        assertion_text(owner, "stderr", stderr, case, "stderr_")
        assertion_text(owner, "combined output", stdout + stderr, case)


def request_body(request: dict[str, object]) -> tuple[bytes, list[tuple[str, str]]]:
    headers: list[tuple[str, str]] = []
    raw_headers = request.get("headers", [])
    if isinstance(raw_headers, dict):
        headers.extend((str(name), str(value)) for name, value in raw_headers.items())
    elif isinstance(raw_headers, list):
        for header in raw_headers:
            if not isinstance(header, dict) or set(header) != {"name", "value"}:
                fail("request headers must contain name/value objects")
            headers.append((str(header["name"]), str(header["value"])))
    else:
        fail("request headers must be an object or array")

    if "body" in request:
        return str(request["body"]).encode(), headers
    if "body_hex" in request:
        return bytes.fromhex(str(request["body_hex"])), headers
    multipart = request.get("multipart")
    if multipart is None:
        return b"", headers
    if not isinstance(multipart, list):
        fail("multipart must be an array")
    boundary = "basic-webserver-spec-boundary"
    body = bytearray()
    for part in multipart:
        if not isinstance(part, dict) or "name" not in part:
            fail("multipart parts need a name")
        body.extend(f"--{boundary}\r\n".encode())
        disposition = f'Content-Disposition: form-data; name="{part["name"]}"'
        if "filename" in part:
            disposition += f'; filename="{part["filename"]}"'
        body.extend(f"{disposition}\r\n".encode())
        if "content_type" in part:
            body.extend(f'Content-Type: {part["content_type"]}\r\n'.encode())
        body.extend(b"\r\n")
        body.extend(
            bytes.fromhex(str(part["data_hex"]))
            if "data_hex" in part
            else str(part.get("data", "")).encode()
        )
        body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode())
    headers.append(("Content-Type", f"multipart/form-data; boundary={boundary}"))
    return bytes(body), headers


def run_http_exchange(port: int, request: dict[str, object], owner: str) -> None:
    body, headers = request_body(request)
    method = str(request.get("method", "GET"))
    target = str(request.get("target", "/"))
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=float(request.get("timeout", 5)))
    try:
        connection.putrequest(method, target)
        names = {name.lower() for name, _ in headers}
        if body and "content-length" not in names:
            headers.append(("Content-Length", str(len(body))))
        for name, value in headers:
            connection.putheader(name, value)
        connection.endheaders(body if body else None)
        response = connection.getresponse()
        response_body = response.read()
        response_headers = response.getheaders()
    finally:
        connection.close()

    expected_status = int(request.get("status", 200))
    if response.status != expected_status:
        fail(
            f"{owner}: {method} {target} expected HTTP {expected_status}, got {response.status}"
            f"\nbody={response_body!r}"
        )
    expected_headers = request.get("response_headers", {})
    if not isinstance(expected_headers, dict):
        fail(f"{owner}: response_headers must be an object")
    actual_headers: dict[str, list[str]] = {}
    for name, value in response_headers:
        actual_headers.setdefault(name.lower(), []).append(value)
    for name, expected in expected_headers.items():
        actual = actual_headers.get(str(name).lower(), [])
        wanted = [str(item) for item in expected] if isinstance(expected, list) else [str(expected)]
        if actual != wanted:
            fail(f"{owner}: header {name!r} expected {wanted!r}, got {actual!r}")
    if "expect_body_hex" in request:
        expected = bytes.fromhex(str(request["expect_body_hex"]))
        if response_body != expected:
            fail(f"{owner}: response body expected {expected!r}, got {response_body!r}")
    elif "expect_body" in request:
        expected = str(request["expect_body"]).encode()
        if response_body != expected:
            fail(f"{owner}: response body expected {expected!r}, got {response_body!r}")
    body_text = response_body.decode("utf-8", errors="replace")
    assertion_text(owner, "response body", body_text, request, "body_")


def run_concurrent_http_exchanges(
    port: int,
    exchanges: list[object],
    owner: str,
    timeout: float,
) -> None:
    failures: list[BaseException] = []
    failures_lock = threading.Lock()
    threads: list[threading.Thread] = []

    def run_one(exchange: dict[str, object], exchange_owner: str) -> None:
        try:
            run_http_exchange(port, exchange, exchange_owner)
        except BaseException as error:
            with failures_lock:
                failures.append(error)

    for index, exchange in enumerate(exchanges, 1):
        if not isinstance(exchange, dict):
            fail(f"{owner}: concurrent request {index} must be an object")
        delay_ms = float(exchange.get("launch_after_ms", 0))
        if delay_ms < 0:
            fail(f"{owner}: concurrent request {index} launch_after_ms must be non-negative")
        if delay_ms:
            time.sleep(delay_ms / 1000)
        thread = threading.Thread(
            target=run_one,
            args=(exchange, f"{owner} concurrent request {index}"),
            daemon=True,
        )
        thread.start()
        threads.append(thread)

    deadline = time.monotonic() + timeout
    for thread in threads:
        thread.join(max(0, deadline - time.monotonic()))
    if any(thread.is_alive() for thread in threads):
        fail(f"{owner}: concurrent requests did not finish after {timeout}s")
    if failures:
        raise failures[0]


def run_raw_exchange(port: int, request: dict[str, object], owner: str) -> None:
    fragments = request.get("fragments")
    if fragments is None:
        fragments = [{"data": request.get("data", ""), "data_hex": request.get("data_hex")}]
    if not isinstance(fragments, list):
        fail(f"{owner}: raw fragments must be an array")
    received = bytearray()
    with socket.create_connection(("127.0.0.1", port), timeout=float(request.get("timeout", 5))) as sock:
        sock.settimeout(float(request.get("timeout", 5)))
        for fragment in fragments:
            if not isinstance(fragment, dict):
                fail(f"{owner}: each raw fragment must be an object")
            if fragment.get("data_hex") is not None:
                payload = bytes.fromhex(str(fragment["data_hex"]))
            else:
                payload = str(fragment.get("data", "")).encode()
            sock.sendall(payload)
            if "delay_ms" in fragment:
                time.sleep(float(fragment["delay_ms"]) / 1000)
        if request.get("half_close", True):
            sock.shutdown(socket.SHUT_WR)
        while True:
            try:
                chunk = sock.recv(65536)
            except TimeoutError:
                break
            if not chunk:
                break
            received.extend(chunk)
    if "response_exact_hex" in request:
        expected = bytes.fromhex(str(request["response_exact_hex"]))
        if received != expected:
            fail(f"{owner}: raw response expected {expected!r}, got {bytes(received)!r}")
    text = received.decode("latin-1")
    if "response_exact" in request and text != str(request["response_exact"]):
        fail(f"{owner}: raw response did not match exactly\n--- raw response ---\n{text}")
    for expected in request.get("response_contains", []):
        if str(expected) not in text:
            fail(f"{owner}: raw response missing {expected!r}\n--- raw response ---\n{text}")
    for pattern in request.get("response_regex", []):
        if re.search(str(pattern), text, re.MULTILINE | re.DOTALL) is None:
            fail(f"{owner}: raw response did not match /{pattern}/\n--- raw response ---\n{text}")


def stop_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)


def run_server_case(binary: Path, source: Path, case: dict[str, object], owner: str) -> None:
    timeout = float(case.get("timeout", 10))
    with tempfile.TemporaryDirectory(prefix="basic-webserver-spec-") as raw_temp:
        temp = Path(raw_temp)
        install_fixtures(case, source, temp)
        env = case_environment(case, source, temp)
        with helper(case.get("helper")):
            process = subprocess.Popen(
                [str(binary)],
                cwd=process_cwd(case, temp),
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            assert process.stdout is not None and process.stderr is not None
            stdout = Capture(process.stdout)
            stderr = Capture(process.stderr)
            stdout.start()
            stderr.start()
            interaction_error: BaseException | None = None
            try:
                match = stdout.wait_for(LISTENING, process, timeout)
                port = int(match.group(1))
                exchanges = case.get("requests", [])
                if not isinstance(exchanges, list):
                    fail(f"{owner}: requests must be an array")
                for index, exchange in enumerate(exchanges, 1):
                    if not isinstance(exchange, dict):
                        fail(f"{owner}: request {index} must be an object")
                    exchange_owner = f"{owner} request {index}"
                    if exchange.get("raw", False):
                        run_raw_exchange(port, exchange, exchange_owner)
                    else:
                        run_http_exchange(port, exchange, exchange_owner)
                concurrent = case.get("concurrent_requests", [])
                if not isinstance(concurrent, list):
                    fail(f"{owner}: concurrent_requests must be an array")
                run_concurrent_http_exchanges(port, concurrent, owner, timeout)
                if case.get("expect_exit", False):
                    try:
                        process.wait(timeout=timeout)
                    except subprocess.TimeoutExpired:
                        fail(f"{owner}: server did not exit after {timeout}s")
                    expected_exit = int(case.get("exit_code", 0))
                    if process.returncode != expected_exit:
                        fail(f"{owner}: expected exit {expected_exit}, got {process.returncode}")
                wait_for = case.get("wait_for_stdout")
                if isinstance(wait_for, str):
                    stdout.wait_for(re.compile(re.escape(wait_for)), process, timeout)
            except BaseException as error:
                interaction_error = error
            finally:
                stop_process(process)
                stdout.thread.join(timeout=2)
                stderr.thread.join(timeout=2)

            stdout_text = stdout.text()
            stderr_text = stderr.text()
            if interaction_error is not None:
                fail(
                    f"{owner}: server interaction failed: {interaction_error}\n"
                    f"process exit: {process.returncode}\n"
                    f"--- stdout ---\n{stdout_text}"
                    f"--- stderr ---\n{stderr_text}"
                )
            assertion_text(owner, "stdout", stdout_text, case, "stdout_")
            assertion_text(owner, "stderr", stderr_text, case, "stderr_")
            assertion_text(owner, "combined output", stdout_text + stderr_text, case)


def run_cases(
    defaults: dict[str, bool],
    apps: list[dict[str, object]],
    binaries: dict[str, Path],
    results: list[dict[str, object]],
) -> None:
    for app in apps:
        if not stage_enabled(defaults, app, "run"):
            continue
        source = ROOT / str(app["path"])
        binary = binaries.get(str(app["path"]))
        if binary is None:
            fail(f"{app['path']}: run is enabled but its binary is missing")
        app_skip = skip_for_current(app)
        cases = app["cases"]
        assert isinstance(cases, list)
        for raw_case in cases:
            assert isinstance(raw_case, dict)
            owner = f"{app['path']} [{raw_case['name']}]"
            skipped = app_skip or skip_for_current(raw_case)
            if skipped is not None:
                reason, issue = skipped
                print(f"SKIP {owner}: {reason} ({issue})")
                results.append(
                    {"app": app["path"], "case": raw_case["name"], "status": "skipped",
                     "reason": reason, "issue": issue}
                )
                continue
            print(f"==> run {owner}", flush=True)
            try:
                if app["mode"] == "process":
                    run_process_case(binary, source, raw_case, owner)
                else:
                    run_server_case(binary, source, raw_case, owner)
            except TestFailure:
                results.append({"app": app["path"], "case": raw_case["name"], "status": "failed"})
                raise
            results.append({"app": app["path"], "case": raw_case["name"], "status": "passed"})


def write_results(
    target: str, build_id: str, results: list[dict[str, object]]
) -> None:
    if re.fullmatch(r"[A-Za-z0-9_.-]+", build_id) is None:
        fail(f"Invalid build identity {build_id!r}")
    VALIDATION_ROOT.mkdir(parents=True, exist_ok=True)
    path = VALIDATION_ROOT / f"results-{target}-{build_id}.json"
    path.write_text(
        json.dumps(
            {
                "platform": current_platform(),
                "target": target,
                "build_id": build_id,
                "cases": results,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"Results: {path.relative_to(ROOT)}")


def compare_results(directory: Path) -> None:
    paths = sorted(directory.rglob("results-*.json"))
    expected_targets = set(declared_targets())
    if expected_targets != set(TARGET_PLATFORMS):
        fail(
            "Platform/result target mismatch; "
            f"platform={sorted(expected_targets)}, "
            f"results={sorted(TARGET_PLATFORMS)}"
        )

    expected_cases: set[tuple[str, str]] | None = None
    actual_builds: set[tuple[str, str]] = set()
    builders_by_target: dict[str, set[str]] = {}
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        target = data.get("target")
        if target not in expected_targets:
            fail(f"{path}: unknown target {target!r}")
        build_id = str(data.get("build_id", "local"))
        build = (str(target), build_id)
        if build in actual_builds:
            fail(f"{path}: duplicate results for {target} built by {build_id}")
        actual_builds.add(build)
        builders_by_target.setdefault(str(target), set()).add(build_id)

        expected_platform = TARGET_PLATFORMS[str(target)]
        if data.get("platform") != expected_platform:
            fail(
                f"{path}: {target} ran on {data.get('platform')!r}, "
                f"expected {expected_platform!r}"
            )

        cases = data.get("cases")
        if not isinstance(cases, list):
            fail(f"{path}: cases must be an array")
        identities: set[tuple[str, str]] = set()
        for case in cases:
            if not isinstance(case, dict):
                fail(f"{path}: invalid case result")
            identity = (str(case.get("app")), str(case.get("case")))
            if identity in identities:
                fail(f"{path}: duplicate result for {identity}")
            identities.add(identity)
            status = case.get("status")
            if status not in ("passed", "skipped"):
                fail(f"{path}: {identity} has status {status!r}")
            if status == "skipped" and (
                not case.get("reason") or not case.get("issue")
            ):
                fail(f"{path}: {identity} has an unexplained skip")

        if expected_cases is None:
            expected_cases = identities
        elif identities != expected_cases:
            fail(
                f"{path}: runtime case mismatch; "
                f"missing={sorted(expected_cases - identities)}, "
                f"extra={sorted(identities - expected_cases)}"
            )
        print(
            f"{path}: {target} built by {build_id} "
            f"accounted for {len(identities)} cases"
        )

    actual_targets = set(builders_by_target)
    if actual_targets != expected_targets:
        fail(f"Missing target results: {sorted(expected_targets - actual_targets)}")


def spec_hash() -> str:
    return hashlib.sha256(portable_text_bytes(SPEC_PATH)).hexdigest()


def examples_hash() -> str:
    digest = hashlib.sha256()
    paths = [
        item
        for item in (ROOT / "examples").iterdir()
        if item.is_file() and item.suffix != ".todoroc"
    ]
    paths.append(ROOT / "scripts" / "command_helper.py")
    for path in sorted(paths):
        digest.update(path.relative_to(ROOT).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(portable_file_bytes(path))
        digest.update(b"\0")
    return digest.hexdigest()


def write_manifest(
    target: str,
    binaries: dict[str, Path],
    artifact_dir: Path,
    build_id: str = "local",
    examples_sha256: str | None = None,
) -> None:
    if re.fullmatch(r"[A-Za-z0-9_.-]+", build_id) is None:
        fail(f"Invalid build identity {build_id!r}")
    target_dir = artifact_dir / target
    manifest = {
        "target": target,
        "build_id": build_id,
        "spec_sha256": spec_hash(),
        "examples_sha256": examples_sha256 or examples_hash(),
        "binaries": {
            source: str(path.relative_to(target_dir).as_posix())
            for source, path in sorted(binaries.items())
        },
    }
    path = target_dir / "manifest.json"
    path.write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n"
    )


def load_artifact_manifest(
    manifest_path: Path,
    target: str,
    defaults: dict[str, bool],
    apps: list[dict[str, object]],
) -> tuple[str, dict[str, Path]]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("target") != target:
        fail(f"{manifest_path}: target does not match {target}")
    build_id = str(manifest.get("build_id", "local"))
    if re.fullmatch(r"[A-Za-z0-9_.-]+", build_id) is None:
        fail(f"{manifest_path}: invalid build identity {build_id!r}")
    if manifest.get("spec_sha256") != spec_hash():
        fail(f"{manifest_path}: binaries were built from a different test spec")
    if manifest.get("examples_sha256") != examples_hash():
        fail(f"{manifest_path}: binaries were built from different example sources")
    entries = manifest.get("binaries")
    if not isinstance(entries, dict):
        fail(f"{manifest_path}: binaries must be an object")
    expected = {
        str(app["path"])
        for app in apps
        if stage_enabled(defaults, app, "build")
    }
    if set(entries) != expected:
        fail(
            f"{manifest_path}: binary mismatch; "
            f"missing={sorted(expected - set(entries))}, "
            f"extra={sorted(set(entries) - expected)}"
        )
    binaries = {
        source: manifest_path.parent / str(relative)
        for source, relative in entries.items()
    }
    missing = sorted(
        source for source, binary in binaries.items() if not binary.is_file()
    )
    if missing:
        fail(f"{manifest_path}: missing binary files for {missing}")
    if os.name == "posix":
        for binary in binaries.values():
            binary.chmod(binary.stat().st_mode | 0o111)
    return build_id, binaries


def load_artifact_binaries(
    target: str,
    artifact_dir: Path,
    defaults: dict[str, bool],
    apps: list[dict[str, object]],
) -> dict[str, Path]:
    manifest_path = artifact_dir / target / "manifest.json"
    if not manifest_path.is_file():
        fail(f"Missing artifact manifest: {manifest_path}")
    _, binaries = load_artifact_manifest(
        manifest_path, target, defaults, apps
    )
    return binaries


def load_artifact_builds(
    target: str,
    artifact_dir: Path,
    defaults: dict[str, bool],
    apps: list[dict[str, object]],
) -> list[tuple[str, dict[str, Path]]]:
    direct = artifact_dir / target / "manifest.json"
    candidates = [direct] if direct.is_file() else sorted(
        artifact_dir.rglob("manifest.json")
    )
    builds: list[tuple[str, dict[str, Path]]] = []
    seen: set[str] = set()
    for manifest_path in candidates:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("target") != target:
            continue
        build_id, binaries = load_artifact_manifest(
            manifest_path, target, defaults, apps
        )
        if build_id in seen:
            fail(f"Duplicate {target} artifact built by {build_id}")
        seen.add(build_id)
        builds.append((build_id, binaries))
    if not builds:
        fail(f"No {target} artifact manifests found under {artifact_dir}")
    return builds


def validate_sources(
    roc: str,
    defaults: dict[str, bool],
    apps: list[dict[str, object]],
    *,
    use_local_readme_platform: bool = True,
) -> None:
    if VALIDATION_ROOT.exists():
        shutil.rmtree(VALIDATION_ROOT)
    for stage in ("fmt", "check", "test"):
        for app in apps:
            if not stage_enabled(defaults, app, stage):
                continue
            source = ROOT / str(app["path"])
            print(f"==> {stage} {app['path']}", flush=True)
            if stage == "fmt":
                command(roc, "fmt", "--check", source)
            else:
                command(roc, stage, source)

    readme = readme_example(use_local_platform=use_local_readme_platform)
    command(roc, "check", readme)
    command(roc, "test", readme)


def build_artifacts(
    roc: str,
    target: str,
    artifact_dir: Path,
    defaults: dict[str, bool],
    apps: list[dict[str, object]],
    *,
    build_id: str = "local",
    use_local_readme_platform: bool = True,
    examples_sha256: str | None = None,
) -> dict[str, Path]:
    prepare_artifact_output(target, artifact_dir)
    binaries: dict[str, Path] = {}
    for app in apps:
        if not stage_enabled(defaults, app, "build"):
            continue
        source = ROOT / str(app["path"])
        binary = output_path(source, target, artifact_dir)
        print(f"==> build {app['path']} ({target})", flush=True)
        command(
            roc,
            "build",
            source,
            f"--target={target}",
            f"--output={binary}",
        )
        binaries[str(app["path"])] = binary

    readme = readme_example(use_local_platform=use_local_readme_platform)
    command(
        roc,
        "build",
        readme,
        f"--target={target}",
        f"--output={artifact_dir / target / ('readme' + executable_suffix(target))}",
    )
    write_manifest(
        target,
        binaries,
        artifact_dir,
        build_id,
        examples_sha256,
    )
    return binaries


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--operation",
        choices=("all", "validate", "build", "run", "compare"),
        default="all",
        help="run the complete suite or one reusable phase",
    )
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    parser.add_argument("--target", choices=declared_targets())
    parser.add_argument(
        "--all-targets",
        action="store_true",
        help="build every declared target sequentially",
    )
    parser.add_argument(
        "--build-id",
        default=os.environ.get("BASIC_WEBSERVER_BUILD_ID", "local"),
        help="stable identity of the machine that produced a binary artifact",
    )
    parser.add_argument(
        "--readme-platform",
        choices=("local", "declared"),
        default="local",
        help="use the checkout platform or preserve the README platform URL",
    )
    parser.add_argument(
        "--examples-sha256",
        help="hash of the original sources when building rewritten bundle consumers",
    )
    parser.add_argument(
        "--artifact-dir", type=Path, default=DEFAULT_ARTIFACT_DIR
    )
    parser.add_argument(
        "--results-dir",
        type=Path,
        default=ROOT / "target" / "spec-results",
        help="directory containing per-target result manifests for compare",
    )
    args = parser.parse_args()

    if args.operation == "compare":
        compare_results(args.results_dir.resolve())
        return

    defaults, apps = load_spec()
    artifact_dir = args.artifact_dir.resolve()
    use_local_readme_platform = args.readme_platform == "local"

    if args.all_targets:
        if args.target is not None:
            parser.error("--all-targets and --target are mutually exclusive")
        if args.operation != "build":
            parser.error("--all-targets requires --operation build")
        total = 0
        for build_target in declared_targets():
            binaries = build_artifacts(
                args.roc,
                build_target,
                artifact_dir,
                defaults,
                apps,
                build_id=args.build_id,
                use_local_readme_platform=use_local_readme_platform,
                examples_sha256=args.examples_sha256,
            )
            total += len(binaries)
        print(
            f"\nBuilt {total} applications across "
            f"{len(declared_targets())} targets."
        )
        return

    target = args.target or detect_native_target()

    if args.operation == "run" and target != detect_native_target():
        fail(
            f"Cannot run {target} binaries on native target "
            f"{detect_native_target()}"
        )

    if args.operation in ("all", "validate"):
        command(sys.executable, "-m", "unittest", "scripts.test_harness_test")
        validate_sources(
            args.roc,
            defaults,
            apps,
            use_local_readme_platform=use_local_readme_platform,
        )
        if args.operation == "validate":
            print(f"\nValidated {len(apps)} applications.")
            return

    if args.operation in ("all", "build"):
        binaries = build_artifacts(
            args.roc,
            target,
            artifact_dir,
            defaults,
            apps,
            build_id=args.build_id,
            use_local_readme_platform=use_local_readme_platform,
            examples_sha256=args.examples_sha256,
        )
        if args.operation == "build":
            print(f"\nBuilt {len(binaries)} applications for {target}.")
            return
        builds = load_artifact_builds(target, artifact_dir, defaults, apps)
    else:
        builds = load_artifact_builds(target, artifact_dir, defaults, apps)

    total = 0
    failed_builds: list[tuple[str, str]] = []
    for build_id, binaries in builds:
        print(f"\n==> execute {target} artifacts built by {build_id}", flush=True)
        results: list[dict[str, object]] = []
        try:
            run_cases(defaults, apps, binaries, results)
        except TestFailure as error:
            failed_builds.append((build_id, str(error)))
            print(
                f"FAILED {target} artifacts built by {build_id}: {error}",
                file=sys.stderr,
                flush=True,
            )
        finally:
            write_results(target, build_id, results)
        total += len(results)
    if failed_builds:
        summary = "\n".join(
            f"- {build_id}: {error}" for build_id, error in failed_builds
        )
        fail(
            f"{len(failed_builds)} of {len(builds)} {target} artifact sets failed:\n"
            f"{summary}"
        )
    print(f"\nAll {total} runtime cases passed across {len(builds)} builds.")


if __name__ == "__main__":
    try:
        main()
    except TestFailure as error:
        raise SystemExit(f"TEST FAILURE: {error}") from None
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
