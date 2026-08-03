#!/usr/bin/env python3
"""Build and exercise every active basic-webserver application.

The JSON specification is intentionally the single source of truth for test
discovery and runtime behaviour. The runner uses only Python's standard
library so that the same cases run on every supported host OS.
"""

from __future__ import annotations

import argparse
import contextlib
import gzip
import functools
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
import urllib.request
from http.server import (
    BaseHTTPRequestHandler,
    SimpleHTTPRequestHandler,
    ThreadingHTTPServer,
)
from pathlib import Path
from typing import Iterator


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "scripts" / "test_spec.json"
VALIDATION_ROOT = ROOT / "target" / "spec"
DEFAULT_ARTIFACT_DIR = ROOT / "dist" / "example-binaries"
MEMCHECK_ROOT = ROOT / "target" / "memcheck-spec"
STAGES = ("fmt", "check", "test", "build", "run")
BUILD_OPTIMIZATIONS = {"speed", "dev"}
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
PLATFORM_DEPENDENCY = re.compile(r'(?m)(\bplatform\s+)"[^"]+"')
LISTENING = re.compile(r"Listening on <http://(?:\[.*\]|[^:]+):([0-9]+)>")
HTTP2_CLIENT_PREFACE = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
HTTP2_FRAME_DATA = 0x0
HTTP2_FRAME_HEADERS = 0x1
HTTP2_FRAME_RST_STREAM = 0x3
HTTP2_FRAME_SETTINGS = 0x4
HTTP2_FRAME_PUSH_PROMISE = 0x5
HTTP2_FRAME_PING = 0x6
HTTP2_FRAME_GOAWAY = 0x7
HTTP2_FRAME_CONTINUATION = 0x9
HTTP2_FLAG_END_STREAM = 0x1
HTTP2_FLAG_ACK = 0x1
HTTP2_FLAG_END_HEADERS = 0x4
HTTP2_MAX_TEST_BODY_BYTES = 1024 * 1024
MAX_GENERATED_FIXTURE_BYTES = 64 * 1024 * 1024

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")


class TestFailure(RuntimeError):
    pass


class QuietFileHandler(SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        pass


class BundleServer:
    """Serve one immutable bundle on loopback for Roc dependency resolution."""

    def __init__(self, bundle: Path) -> None:
        handler = functools.partial(QuietFileHandler, directory=str(bundle.parent))
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.url = f"http://127.0.0.1:{self.server.server_port}/{bundle.name}"

    def __enter__(self) -> str:
        self.thread.start()
        with urllib.request.urlopen(
            urllib.request.Request(self.url, method="HEAD"), timeout=5
        ):
            pass
        return self.url

    def __exit__(self, *_: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


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


@contextlib.contextmanager
def locally_built_platform(roc: str, target: str) -> Iterator[str]:
    """Build, bundle, and host the checkout's platform for one Roc target."""

    bundle_dir = ROOT / "target" / "local-platform-bundle" / target
    if bundle_dir.exists():
        shutil.rmtree(bundle_dir)
    bundle_dir.mkdir(parents=True)

    command(
        sys.executable,
        ROOT / "scripts" / "build.py",
        "--target",
        target,
    )
    command(
        sys.executable,
        ROOT / "scripts" / "bundle.py",
        "--output-dir",
        bundle_dir,
        "--target",
        target,
        "--roc",
        roc,
    )
    bundles = sorted(bundle_dir.glob("*.tar.zst"))
    if len(bundles) != 1:
        fail(
            f"Expected one locally built platform bundle in {bundle_dir}, "
            f"found {len(bundles)}"
        )

    with BundleServer(bundles[0]) as platform_url:
        print(f"Using local platform bundle: {platform_url}", flush=True)
        yield platform_url


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


def validate_test_skip(owner: str, value: object) -> None:
    if not isinstance(value, dict) or set(value) != {"reason", "issue"}:
        fail(f"{owner}: test_skip must contain exactly reason and issue")
    if not isinstance(value["reason"], str) or not value["reason"].strip():
        fail(f"{owner}: a skipped test stage requires a non-empty reason")
    if not isinstance(value["issue"], str) or not ISSUE_URL.fullmatch(value["issue"]):
        fail(f"{owner}: a skipped test stage requires a GitHub tracking issue URL")


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
    startup_failure = case.get("expect_startup_failure", False)
    if not isinstance(startup_failure, bool):
        fail(f"{owner}: expect_startup_failure must be a boolean")
    if startup_failure:
        for incompatible in (
            "requests",
            "concurrent_requests",
            "http2_requests",
            "expect_exit",
            "wait_for_stdout",
        ):
            if case.get(incompatible):
                fail(f"{owner}: expect_startup_failure cannot be combined with {incompatible}")
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
    if not isinstance(fixtures, list):
        fail(f"{owner}: fixtures must be an array")
    for fixture in fixtures:
        if not isinstance(fixture, dict) or not isinstance(fixture.get("dest"), str):
            fail(f"{owner}: every fixture needs a string dest")
        keys = set(fixture)
        allowed_metadata = {"dest", "mtime_unix"}
        content_keys = keys - allowed_metadata
        valid_content = (
            content_keys == {"source"} and isinstance(fixture["source"], str)
        ) or (
            content_keys == {"text"} and isinstance(fixture["text"], str)
        ) or (
            content_keys == {"hex"} and isinstance(fixture["hex"], str)
        ) or (
            content_keys == {"repeat", "size_bytes"}
            and isinstance(fixture["repeat"], str)
            and bool(fixture["repeat"])
            and isinstance(fixture["size_bytes"], int)
            and 0 <= fixture["size_bytes"] <= MAX_GENERATED_FIXTURE_BYTES
        )
        if not valid_content:
            fail(
                f"{owner}: fixture content must be source, text, hex, "
                "or repeat with size_bytes up to 64 MiB"
            )
        if "mtime_unix" in fixture and not isinstance(fixture["mtime_unix"], int):
            fail(f"{owner}: fixture mtime_unix must be an integer")
    http2_requests = case.get("http2_requests", [])
    if not isinstance(http2_requests, list):
        fail(f"{owner}: http2_requests must be an array")
    http2_names: set[str] = set()
    for index, request in enumerate(http2_requests, 1):
        if not isinstance(request, dict):
            fail(f"{owner}: HTTP/2 request {index} must be an object")
        request_name = request.get("name")
        if not isinstance(request_name, str) or not request_name:
            fail(f"{owner}: HTTP/2 request {index} needs a non-empty name")
        if request_name in http2_names:
            fail(f"{owner}: duplicate HTTP/2 request name {request_name!r}")
        http2_names.add(request_name)
        if request.get("raw", False):
            fail(f"{owner}: raw HTTP/2 requests are not supported")
        if "status" in request:
            fail(f"{owner}: HTTP/2 test requests do not decode response headers")
        authority = request.get("authority", "")
        if authority is not None and not isinstance(authority, str):
            fail(f"{owner}: HTTP/2 authority must be a string or null")
    completion_order = case.get("http2_completion_order", [])
    if not isinstance(completion_order, list) or not all(
        isinstance(name, str) for name in completion_order
    ):
        fail(f"{owner}: http2_completion_order must be an array of names")
    if len(completion_order) != len(set(completion_order)):
        fail(f"{owner}: http2_completion_order names must be unique")
    if set(completion_order) != http2_names:
        fail(
            f"{owner}: http2_completion_order must name every HTTP/2 request "
            "exactly once"
        )


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
        test_enabled = overrides.get("test", defaults["test"])
        if test_enabled and "test_skip" in app:
            fail(f"{path}: test_skip is only valid when the test stage is disabled")
        if not test_enabled:
            validate_test_skip(path, app.get("test_skip"))
        if app.get("build_opt", "speed") not in BUILD_OPTIMIZATIONS:
            fail(
                f"{path}: build_opt must be one of "
                f"{sorted(BUILD_OPTIMIZATIONS)}"
            )
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


# TODO: Investigate the Roc compiler bugs that make the LLVM speed backend use
# several GiB for some applications. Remove per-app dev overrides once fixed.
def build_optimization(app: dict[str, object]) -> str:
    value = app.get("build_opt", "speed")
    assert isinstance(value, str) and value in BUILD_OPTIMIZATIONS
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


def compiler_runtime_input(name: str) -> Path:
    value = subprocess.check_output(
        ["cc", f"-print-file-name={name}"], text=True
    ).strip()
    path = Path(value)
    if value == name or not path.is_file():
        fail(f"C compiler could not locate required x64glibc input {name}")
    return path.resolve()


def prepare_memcheck_binaries(
    roc: str,
    defaults: dict[str, bool],
    apps: list[dict[str, object]],
) -> dict[str, Path]:
    if platform.system() != "Linux" or platform.machine().lower() not in {
        "amd64",
        "x86_64",
    }:
        fail("Memcheck validation currently requires x86-64 Linux")
    if shutil.which("valgrind") is None:
        fail("Valgrind is required for --operation memcheck")

    command("cargo", "build", "--locked", "--lib", "--profile", "memcheck")

    if MEMCHECK_ROOT.exists():
        shutil.rmtree(MEMCHECK_ROOT)
    platform_dir = MEMCHECK_ROOT / "platform"
    target_dir = platform_dir / "targets" / "x64glibc"
    app_dir = MEMCHECK_ROOT / "apps"
    binary_dir = MEMCHECK_ROOT / "binaries"
    target_dir.mkdir(parents=True)
    app_dir.mkdir(parents=True)
    binary_dir.mkdir(parents=True)

    for source in sorted((ROOT / "platform").glob("*.roc")):
        shutil.copy2(source, platform_dir / source.name)
    for source in sorted((ROOT / "examples").iterdir()):
        if source.is_file() and source.suffix != ".roc":
            shutil.copy2(source, app_dir / source.name)

    # Validation processes bind an ephemeral port so the complete suite can run
    # alongside a developer's server and parallel CI jobs.
    server_path = platform_dir / "Server.roc"
    server_source = server_path.read_text(encoding="utf-8")
    server_source, count = re.subn(
        r'(?m)^(\s*listen:\s*\{\s*host:\s*"127\.0\.0\.1",\s*port:\s*)8000(\s*\},)$',
        r"\g<1>0\2",
        server_source,
        count=1,
    )
    if count != 1:
        fail("could not set the validation-only listener to an ephemeral port")
    server_path.write_text(server_source, encoding="utf-8", newline="\n")

    runtime_inputs = (
        "Scrt1.o",
        "crti.o",
        "libgcc_s.so.1",
        "libm.so.6",
        "libc.so.6",
        "crtn.o",
    )
    shutil.copy2(ROOT / "target" / "memcheck" / "libhost.a", target_dir)
    for name in runtime_inputs:
        shutil.copy2(compiler_runtime_input(name), target_dir / name)

    main_path = platform_dir / "main.roc"
    main_source = main_path.read_text(encoding="utf-8")
    target_line = (
        '\t\tx64glibc: { inputs: ["Scrt1.o", "crti.o", "libhost.a", app, '
        '"libgcc_s.so.1", "libm.so.6", "libc.so.6", "crtn.o"] },'
    )
    main_source, count = re.subn(
        r'(?m)^(\s*arm64mac:\s*\{[^\n]+\},)\s*$',
        lambda match: f"{match.group(1)}\n{target_line}",
        main_source,
        count=1,
    )
    if count != 1:
        fail("could not add the validation-only x64glibc platform target")
    main_path.write_text(main_source, encoding="utf-8", newline="\n")

    binaries: dict[str, Path] = {}
    for app in apps:
        if not stage_enabled(defaults, app, "build"):
            continue
        source = ROOT / str(app["path"])
        copied_source = app_dir / source.name
        app_source = source.read_text(encoding="utf-8")
        app_source, count = re.subn(
            r'(?m)(\bplatform\s+)"[^"]+"',
            lambda match: f'{match.group(1)}"../platform/main.roc"',
            app_source,
            count=1,
        )
        if count != 1:
            fail(f"{source}: expected exactly one platform dependency")
        copied_source.write_text(app_source, encoding="utf-8", newline="\n")

        binary = binary_dir / source.stem
        print(f"==> memcheck build {app['path']} (x64glibc)", flush=True)
        # TODO: Investigate these Roc compiler bugs upstream, then restore the
        # LLVM speed backend without stripping debug information. The speed
        # backend can currently require several GiB while specializing one
        # application, and Valgrind 3.22 rejects the dev backend's DWARF.
        # Use the small native dev backend and remove only its debug sections
        # for now. The symbol table and executable host/ABI code remain
        # available to Memcheck.
        command(
            roc,
            "build",
            copied_source,
            "--target=x64glibc",
            "--opt=dev",
            f"--output={binary}",
        )
        command("strip", "--strip-debug", binary)
        binaries[str(app["path"])] = binary
    return binaries


def rewritten_app_source(app_path: str, platform_url: str | None) -> Path:
    source_path = ROOT / app_path
    if platform_url is None:
        return source_path

    source = source_path.read_text(encoding="utf-8")
    rewritten, count = PLATFORM_DEPENDENCY.subn(
        lambda match: f'{match.group(1)}"{platform_url}"',
        source,
        count=1,
    )
    if count != 1:
        fail(f"{app_path}: expected exactly one platform dependency")

    destination = VALIDATION_ROOT / "sources" / app_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    for sibling in source_path.parent.iterdir():
        if sibling.is_file() and sibling.suffix != ".roc":
            shutil.copy2(sibling, destination.parent / sibling.name)
    destination.write_text(rewritten, encoding="utf-8", newline="\n")
    return destination


def readme_example(*, platform_url: str | None = None) -> Path:
    source = (ROOT / "README.md").read_text(encoding="utf-8")
    match = re.search(r"(?ms)^```roc\n(.*?)^```$", source)
    if match is None:
        fail("README example check failed: no Roc code block found")
    directory = VALIDATION_ROOT / "readme"
    directory.mkdir(parents=True, exist_ok=True)
    rewritten = match.group(1)
    if platform_url is not None:
        rewritten, count = PLATFORM_DEPENDENCY.subn(
            lambda dependency: f'{dependency.group(1)}"{platform_url}"',
            rewritten,
            count=1,
        )
        if count != 1:
            fail("README example check failed: expected one platform dependency")
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
        dest = Path(expanded(str(fixture["dest"]), source, temp))
        dest.parent.mkdir(parents=True, exist_ok=True)
        if "source" in fixture:
            src = Path(expanded(str(fixture["source"]), source, temp))
            shutil.copy2(src, dest)
        elif "text" in fixture:
            dest.write_text(str(fixture["text"]), encoding="utf-8", newline="")
        elif "hex" in fixture:
            dest.write_bytes(bytes.fromhex(str(fixture["hex"])))
        else:
            pattern = str(fixture["repeat"]).encode()
            size = int(fixture["size_bytes"])
            with dest.open("wb") as output:
                block = (pattern * (65536 // len(pattern) + 1))[:65536]
                remaining = size
                while remaining:
                    chunk = block[:remaining]
                    output.write(chunk)
                    remaining -= len(chunk)
        if "mtime_unix" in fixture:
            timestamp = int(fixture["mtime_unix"])
            os.utime(dest, (timestamp, timestamp))


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


def case_timeout(case: dict[str, object], memcheck: bool) -> float:
    timeout = float(case.get("timeout", 10))
    if memcheck:
        return max(60, timeout * 10)
    return timeout


def process_command(
    binary: Path, temp: Path, *, memcheck: bool
) -> tuple[list[str], Path | None]:
    if not memcheck:
        return [str(binary)], None
    log_path = temp / "memcheck.log"
    return (
        [
            "valgrind",
            "--tool=memcheck",
            "--leak-check=full",
            "--show-leak-kinds=definite,indirect,possible",
            "--errors-for-leak-kinds=definite,indirect,possible",
            "--track-origins=yes",
            "--fair-sched=yes",
            "--num-callers=40",
            "--error-exitcode=97",
            f"--log-file={log_path}",
            str(binary),
        ],
        log_path,
    )


def validate_memcheck_log(log_path: Path | None, owner: str) -> None:
    if log_path is None:
        return
    if not log_path.is_file():
        fail(f"{owner}: Valgrind did not produce its Memcheck log")
    log = log_path.read_text(encoding="utf-8", errors="replace")
    allocation_match = re.search(
        r"total heap usage:\s*([0-9,]+) allocs", log
    )
    if allocation_match is None:
        fail(f"{owner}: Memcheck did not report allocator activity\n{log}")
    allocation_count = int(allocation_match.group(1).replace(",", ""))
    if allocation_count == 0:
        fail(
            f"{owner}: Memcheck observed zero allocations; allocator "
            f"interception is not valid\n{log}"
        )
    if re.search(r"ERROR SUMMARY:\s*0 errors", log) is None:
        fail(f"{owner}: Memcheck reported an error\n{log}")


def run_process_case(
    binary: Path,
    source: Path,
    case: dict[str, object],
    owner: str,
    *,
    memcheck: bool,
) -> None:
    timeout = case_timeout(case, memcheck)
    with tempfile.TemporaryDirectory(prefix="basic-webserver-spec-") as raw_temp:
        temp = Path(raw_temp)
        install_fixtures(case, source, temp)
        env = case_environment(case, source, temp)
        args, memcheck_log = process_command(binary, temp, memcheck=memcheck)
        args.extend(
            expanded(str(arg), source, temp) for arg in case.get("args", [])
        )
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
        validate_memcheck_log(memcheck_log, owner)
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
            if not isinstance(header, dict) or "name" not in header:
                fail("request headers must contain a name")
            if set(header) == {"name", "value"}:
                value = str(header["value"])
            elif set(header) == {"name", "value_repeat", "value_chars"}:
                pattern = str(header["value_repeat"])
                raw_length = header["value_chars"]
                if not isinstance(raw_length, int):
                    fail("repeated request-header value_chars must be an integer")
                length = raw_length
                if not pattern or length < 0 or length > HTTP2_MAX_TEST_BODY_BYTES:
                    fail("repeated request-header values need 0..1 MiB characters")
                value = (pattern * (length // len(pattern) + 1))[:length]
            else:
                fail(
                    "request headers need name/value or "
                    "name/value_repeat/value_chars"
                )
            headers.append((str(header["name"]), value))
    else:
        fail("request headers must be an object or array")

    if "body" in request:
        return str(request["body"]).encode(), headers
    if "body_hex" in request:
        return bytes.fromhex(str(request["body_hex"])), headers
    if "body_repeat" in request:
        pattern = str(request["body_repeat"]).encode()
        size = int(request.get("body_size_bytes", 0))
        if not pattern or size < 0 or size > MAX_GENERATED_FIXTURE_BYTES:
            fail("body_repeat needs a non-empty pattern and a size up to 64 MiB")
        return (pattern * (size // len(pattern) + 1))[:size], headers
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


# Native artifact runners intentionally require only Python's standard library,
# so this focused prior-knowledge client implements just enough HTTP/2 and HPACK
# to open concurrent request streams and validate their bodies and completion.
def http2_frame(frame_type: int, flags: int, stream_id: int, payload: bytes) -> bytes:
    if len(payload) > 0xFFFFFF:
        fail("HTTP/2 test frame payload exceeds the protocol maximum")
    if stream_id < 0 or stream_id > 0x7FFFFFFF:
        fail(f"invalid HTTP/2 stream identifier {stream_id}")
    return (
        len(payload).to_bytes(3, "big")
        + bytes((frame_type, flags))
        + stream_id.to_bytes(4, "big")
        + payload
    )


def hpack_integer(value: int, prefix_bits: int, first_byte: int = 0) -> bytes:
    prefix_max = (1 << prefix_bits) - 1
    if value < prefix_max:
        return bytes((first_byte | value,))
    encoded = bytearray((first_byte | prefix_max,))
    value -= prefix_max
    while value >= 128:
        encoded.append((value & 0x7F) | 0x80)
        value >>= 7
    encoded.append(value)
    return bytes(encoded)


def hpack_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return hpack_integer(len(encoded), 7) + encoded


def hpack_request_headers(
    port: int, request: dict[str, object], body: bytes, headers: list[tuple[str, str]]
) -> bytes:
    method = str(request.get("method", "GET")).upper()
    target = str(request.get("target", "/"))
    if not target.startswith("/") and not (method == "OPTIONS" and target == "*"):
        fail(f"HTTP/2 test request target must be a resource path or OPTIONS '*': {target!r}")

    block = bytearray()
    if method == "GET":
        block.append(0x82)  # Indexed static-table entry 2, :method GET.
    elif method == "POST":
        block.append(0x83)  # Indexed static-table entry 3, :method POST.
    else:
        block.extend(hpack_integer(2, 4))
        block.extend(hpack_string(method))
    block.append(0x86)  # Indexed static-table entry 6, :scheme http.
    if target == "/":
        block.append(0x84)  # Indexed static-table entry 4, :path /.
    else:
        block.extend(hpack_integer(4, 4))
        block.extend(hpack_string(target))
    authority = request.get("authority", f"127.0.0.1:{port}")
    if authority is not None:
        block.extend(hpack_integer(1, 4))  # Literal :authority, without indexing.
        block.extend(hpack_string(str(authority)))

    names = {name.lower() for name, _ in headers}
    if body and "content-length" not in names:
        headers.append(("content-length", str(len(body))))
    dynamic_indices: dict[tuple[str, str], int] = {}
    for raw_name, value in headers:
        name = raw_name.lower()
        if name in {"connection", "keep-alive", "proxy-connection", "upgrade"}:
            fail(f"connection-specific header {raw_name!r} is invalid in HTTP/2")
        pair = (name, value)
        dynamic_index = dynamic_indices.get(pair)
        if dynamic_index is not None:
            block.extend(hpack_integer(dynamic_index, 7, 0x80))
            continue

        # Literal with incremental indexing. Repeated identical fields can then
        # use one-byte dynamic-table references, exercising decoded limits
        # independently of compressed HPACK size.
        block.append(0x40)
        block.extend(hpack_string(name))
        block.extend(hpack_string(value))
        dynamic_indices = {
            existing: index + 1 for existing, index in dynamic_indices.items()
        }
        dynamic_indices[pair] = 62  # Static table has 61 entries.
    return bytes(block)


def receive_exact(sock: socket.socket, length: int, deadline: float) -> bytes:
    data = bytearray()
    while len(data) < length:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            fail("timed out waiting for an HTTP/2 frame")
        sock.settimeout(remaining)
        try:
            chunk = sock.recv(length - len(data))
        except TimeoutError:
            fail("timed out waiting for an HTTP/2 frame")
        if not chunk:
            fail("HTTP/2 connection closed before every stream completed")
        data.extend(chunk)
    return bytes(data)


def receive_http2_frame(
    sock: socket.socket, deadline: float
) -> tuple[int, int, int, bytes]:
    header = receive_exact(sock, 9, deadline)
    length = int.from_bytes(header[0:3], "big")
    frame_type = header[3]
    flags = header[4]
    stream_id = int.from_bytes(header[5:9], "big") & 0x7FFFFFFF
    return frame_type, flags, stream_id, receive_exact(sock, length, deadline)


def http2_data_fragment(flags: int, payload: bytes) -> bytes:
    if flags & 0x8 == 0:
        return payload
    if not payload:
        fail("truncated padded HTTP/2 DATA frame")
    padding = payload[0]
    if padding + 1 > len(payload):
        fail("invalid HTTP/2 DATA padding")
    return payload[1 : len(payload) - padding]


def assert_http2_response(
    request: dict[str, object], body: bytes, owner: str
) -> None:
    if "expect_body_hex" in request:
        expected = bytes.fromhex(str(request["expect_body_hex"]))
        if body != expected:
            fail(f"{owner}: response body expected {expected!r}, got {body!r}")
    elif "expect_body" in request:
        expected = str(request["expect_body"]).encode()
        if body != expected:
            fail(f"{owner}: response body expected {expected!r}, got {body!r}")
    assertion_text(
        owner,
        "response body",
        body.decode("utf-8", errors="replace"),
        request,
        "body_",
    )


def run_http2_exchanges(
    port: int,
    exchanges: list[object],
    expected_completion_order: list[object],
    owner: str,
    timeout: float,
) -> None:
    requests: dict[int, dict[str, object]] = {}
    names: dict[int, str] = {}
    outbound = bytearray(HTTP2_CLIENT_PREFACE)
    outbound.extend(http2_frame(HTTP2_FRAME_SETTINGS, 0, 0, b""))
    for index, raw_exchange in enumerate(exchanges):
        assert isinstance(raw_exchange, dict)
        stream_id = index * 2 + 1
        body, headers = request_body(raw_exchange)
        header_block = hpack_request_headers(port, raw_exchange, body, headers)
        flags = HTTP2_FLAG_END_HEADERS
        if not body:
            flags |= HTTP2_FLAG_END_STREAM
        outbound.extend(http2_frame(HTTP2_FRAME_HEADERS, flags, stream_id, header_block))
        if body:
            outbound.extend(
                http2_frame(HTTP2_FRAME_DATA, HTTP2_FLAG_END_STREAM, stream_id, body)
            )
        requests[stream_id] = raw_exchange
        names[stream_id] = str(raw_exchange["name"])

    bodies = {stream_id: bytearray() for stream_id in requests}
    completion_order: list[str] = []
    completed: set[int] = set()
    headers_end_stream: set[int] = set()
    deadline = time.monotonic() + timeout

    try:
        sock = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    except OSError as error:
        fail(f"{owner}: failed to connect HTTP/2 test client: {error}")
    with sock:
        sock.sendall(outbound)
        while len(completed) < len(requests):
            frame_type, flags, stream_id, payload = receive_http2_frame(sock, deadline)
            if frame_type == HTTP2_FRAME_SETTINGS:
                if stream_id != 0:
                    fail("HTTP/2 SETTINGS frame used a non-zero stream")
                if flags & HTTP2_FLAG_ACK:
                    if payload:
                        fail("HTTP/2 SETTINGS acknowledgement had a payload")
                else:
                    if len(payload) % 6 != 0:
                        fail("HTTP/2 SETTINGS payload was malformed")
                    sock.sendall(
                        http2_frame(
                            HTTP2_FRAME_SETTINGS, HTTP2_FLAG_ACK, 0, b""
                        )
                    )
                continue
            if frame_type == HTTP2_FRAME_PING:
                if stream_id != 0 or len(payload) != 8:
                    fail("HTTP/2 PING frame was malformed")
                if flags & HTTP2_FLAG_ACK == 0:
                    sock.sendall(
                        http2_frame(HTTP2_FRAME_PING, HTTP2_FLAG_ACK, 0, payload)
                    )
                continue
            if frame_type == HTTP2_FRAME_GOAWAY:
                error_code = (
                    int.from_bytes(payload[4:8], "big") if len(payload) >= 8 else -1
                )
                fail(f"HTTP/2 server sent GOAWAY with error code {error_code}")
            if frame_type == HTTP2_FRAME_PUSH_PROMISE:
                fail("HTTP/2 server unexpectedly sent PUSH_PROMISE")
            if frame_type == HTTP2_FRAME_RST_STREAM:
                error_code = int.from_bytes(payload, "big") if len(payload) == 4 else -1
                fail(
                    f"HTTP/2 stream {stream_id} was reset with error code "
                    f"{error_code}"
                )
            if frame_type not in {
                HTTP2_FRAME_DATA,
                HTTP2_FRAME_HEADERS,
                HTTP2_FRAME_CONTINUATION,
            }:
                continue
            if stream_id not in requests:
                fail(f"HTTP/2 response used unknown stream {stream_id}")

            if frame_type == HTTP2_FRAME_DATA:
                bodies[stream_id].extend(http2_data_fragment(flags, payload))
                if len(bodies[stream_id]) > HTTP2_MAX_TEST_BODY_BYTES:
                    fail(
                        f"HTTP/2 stream {stream_id} exceeded the test client's "
                        f"{HTTP2_MAX_TEST_BODY_BYTES}-byte response limit"
                    )
            elif (
                frame_type == HTTP2_FRAME_HEADERS
                and flags & HTTP2_FLAG_END_STREAM
            ):
                headers_end_stream.add(stream_id)

            stream_ended = (
                frame_type == HTTP2_FRAME_DATA and flags & HTTP2_FLAG_END_STREAM
            ) or (
                stream_id in headers_end_stream
                and frame_type in {HTTP2_FRAME_HEADERS, HTTP2_FRAME_CONTINUATION}
                and flags & HTTP2_FLAG_END_HEADERS
            )
            if stream_ended:
                if stream_id in completed:
                    fail(f"HTTP/2 stream {stream_id} ended more than once")
                completed.add(stream_id)
                completion_order.append(names[stream_id])

    for stream_id, request in requests.items():
        assert_http2_response(
            request,
            bytes(bodies[stream_id]),
            f"{owner} HTTP/2 stream {names[stream_id]!r}",
        )
    expected_names = [str(name) for name in expected_completion_order]
    if completion_order != expected_names:
        fail(
            f"{owner}: HTTP/2 completion order expected {expected_names!r}, "
            f"got {completion_order!r}"
        )


def run_http_exchange(port: int, request: dict[str, object], owner: str) -> None:
    body, headers = request_body(request)
    method = str(request.get("method", "GET"))
    target = str(request.get("target", "/"))
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=float(request.get("timeout", 5)))
    try:
        names = {name.lower() for name, _ in headers}
        connection.putrequest(
            method,
            target,
            skip_accept_encoding="accept-encoding" in names,
        )
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
    decode_response = request.get("decode_response")
    if decode_response is not None:
        if decode_response != "gzip":
            fail(f"{owner}: unsupported response decoder {decode_response!r}")
        try:
            response_body = gzip.decompress(response_body)
        except (OSError, EOFError) as error:
            fail(f"{owner}: invalid gzip response: {error}")
    if "expect_body_hex" in request:
        expected = bytes.fromhex(str(request["expect_body_hex"]))
        if response_body != expected:
            fail(f"{owner}: response body expected {expected!r}, got {response_body!r}")
    elif "expect_body" in request:
        expected = str(request["expect_body"]).encode()
        if response_body != expected:
            fail(f"{owner}: response body expected {expected!r}, got {response_body!r}")
    if "expect_body_bytes" in request:
        expected_length = int(request["expect_body_bytes"])
        if len(response_body) != expected_length:
            fail(
                f"{owner}: response body expected {expected_length} bytes, "
                f"got {len(response_body)}"
            )
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
    closed = False
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
                closed = True
                break
            received.extend(chunk)
    if request.get("expect_close", False) and not closed:
        fail(f"{owner}: raw connection did not close before its socket timeout")
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


def run_server_case(
    binary: Path,
    source: Path,
    case: dict[str, object],
    owner: str,
    *,
    memcheck: bool,
) -> None:
    timeout = case_timeout(case, memcheck)
    with tempfile.TemporaryDirectory(prefix="basic-webserver-spec-") as raw_temp:
        temp = Path(raw_temp)
        install_fixtures(case, source, temp)
        env = case_environment(case, source, temp)
        args, memcheck_log = process_command(binary, temp, memcheck=memcheck)
        with helper(case.get("helper")):
            process = subprocess.Popen(
                args,
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
            if case.get("expect_startup_failure", False):
                startup_error: BaseException | None = None
                try:
                    try:
                        process.wait(timeout=timeout)
                    except subprocess.TimeoutExpired:
                        fail(f"{owner}: invalid startup configuration did not exit")
                    expected_exit = int(case.get("exit_code", 1))
                    if process.returncode != expected_exit:
                        fail(
                            f"{owner}: expected startup failure exit {expected_exit}, "
                            f"got {process.returncode}"
                        )
                except BaseException as error:
                    startup_error = error
                finally:
                    stop_process(process)
                    stdout.thread.join(timeout=2)
                    stderr.thread.join(timeout=2)

                stdout_text = stdout.text()
                stderr_text = stderr.text()
                if LISTENING.search(stdout_text) is not None and startup_error is None:
                    startup_error = TestFailure(f"{owner}: startup failure exposed a listener")
                try:
                    validate_memcheck_log(memcheck_log, owner)
                except TestFailure as error:
                    startup_error = error if startup_error is None else TestFailure(
                        f"{startup_error}\n{error}"
                    )
                if startup_error is not None:
                    fail(
                        f"{owner}: startup-failure interaction failed: {startup_error}\n"
                        f"process exit: {process.returncode}\n"
                        f"--- stdout ---\n{stdout_text}"
                        f"--- stderr ---\n{stderr_text}"
                    )
                assertion_text(owner, "stdout", stdout_text, case, "stdout_")
                assertion_text(owner, "stderr", stderr_text, case, "stderr_")
                assertion_text(owner, "combined output", stdout_text + stderr_text, case)
                return

            interaction_error: BaseException | None = None
            try:
                if case.get("expect_startup_failure", False):
                    try:
                        process.wait(timeout=timeout)
                    except subprocess.TimeoutExpired:
                        fail(f"{owner}: server did not fail startup after {timeout}s")
                    expected_exit = int(case.get("exit_code", 1))
                    if process.returncode != expected_exit:
                        fail(f"{owner}: expected exit {expected_exit}, got {process.returncode}")
                    if LISTENING.search(stdout.text()) is not None:
                        fail(f"{owner}: invalid configuration reached listener readiness")
                else:
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
                    http2_requests = case.get("http2_requests", [])
                    http2_completion_order = case.get("http2_completion_order", [])
                    if not isinstance(http2_requests, list):
                        fail(f"{owner}: http2_requests must be an array")
                    if not isinstance(http2_completion_order, list):
                        fail(f"{owner}: http2_completion_order must be an array")
                    if http2_requests:
                        run_http2_exchanges(
                            port,
                            http2_requests,
                            http2_completion_order,
                            owner,
                            timeout,
                        )
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
            try:
                validate_memcheck_log(memcheck_log, owner)
            except TestFailure as error:
                if interaction_error is None:
                    interaction_error = error
                else:
                    interaction_error = TestFailure(
                        f"{interaction_error}\n{error}"
                    )
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
    *,
    memcheck: bool = False,
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
                    run_process_case(
                        binary, source, raw_case, owner, memcheck=memcheck
                    )
                else:
                    run_server_case(
                        binary, source, raw_case, owner, memcheck=memcheck
                    )
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


def validate_platform_sources(roc: str) -> None:
    print("==> fmt platform", flush=True)
    command(roc, "fmt", "--check", ROOT / "platform")
    print("==> test platform", flush=True)
    command(roc, "test", ROOT / "platform" / "main.roc")


def validate_sources(
    roc: str,
    defaults: dict[str, bool],
    apps: list[dict[str, object]],
    *,
    platform_url: str | None,
) -> None:
    if VALIDATION_ROOT.exists():
        shutil.rmtree(VALIDATION_ROOT)

    validate_platform_sources(roc)

    for stage in ("fmt", "check", "test"):
        for app in apps:
            if not stage_enabled(defaults, app, stage):
                continue
            source = rewritten_app_source(str(app["path"]), platform_url)
            print(f"==> {stage} {app['path']}", flush=True)
            if stage == "fmt":
                command(roc, "fmt", "--check", source)
            else:
                command(roc, stage, source)

    readme = readme_example(platform_url=platform_url)
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
    platform_url: str | None,
    examples_sha256: str | None = None,
) -> dict[str, Path]:
    prepare_artifact_output(target, artifact_dir)
    binaries: dict[str, Path] = {}
    for app in apps:
        if not stage_enabled(defaults, app, "build"):
            continue
        app_path = str(app["path"])
        source = rewritten_app_source(app_path, platform_url)
        binary = output_path(ROOT / app_path, target, artifact_dir)
        print(f"==> build {app['path']} ({target})", flush=True)
        command(
            roc,
            "build",
            source,
            f"--target={target}",
            f"--opt={build_optimization(app)}",
            f"--output={binary}",
        )
        binaries[str(app["path"])] = binary

    readme = readme_example(platform_url=platform_url)
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
        choices=("all", "validate", "build", "run", "compare", "memcheck"),
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
        "--platform-dependency",
        choices=("local-bundle", "declared"),
        default="local-bundle",
        help=(
            "build and host this checkout's platform bundle, or use the URLs "
            "already declared by the application sources"
        ),
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
    use_local_bundle = args.platform_dependency == "local-bundle"

    if args.operation == "memcheck":
        if args.target is not None or args.all_targets:
            parser.error("--operation memcheck builds its validation-only x64glibc target")
        command(sys.executable, "-m", "unittest", "scripts.test_harness_test")
        binaries = prepare_memcheck_binaries(args.roc, defaults, apps)
        results: list[dict[str, object]] = []
        run_cases(defaults, apps, binaries, results, memcheck=True)
        print(f"\nAll {len(results)} runtime cases passed under Memcheck.")
        return

    if args.all_targets:
        if args.target is not None:
            parser.error("--all-targets and --target are mutually exclusive")
        if args.operation != "build":
            parser.error("--all-targets requires --operation build")
        total = 0
        for build_target in declared_targets():
            dependency = (
                locally_built_platform(args.roc, build_target)
                if use_local_bundle
                else contextlib.nullcontext(None)
            )
            with dependency as platform_url:
                binaries = build_artifacts(
                    args.roc,
                    build_target,
                    artifact_dir,
                    defaults,
                    apps,
                    build_id=args.build_id,
                    platform_url=platform_url,
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

    compiles_sources = args.operation in ("all", "validate", "build")
    dependency = (
        locally_built_platform(args.roc, target)
        if use_local_bundle and compiles_sources
        else contextlib.nullcontext(None)
    )
    with dependency as platform_url:
        if args.operation in ("all", "validate"):
            command(sys.executable, "-m", "unittest", "scripts.test_harness_test")
            validate_sources(
                args.roc,
                defaults,
                apps,
                platform_url=platform_url,
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
                platform_url=platform_url,
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
