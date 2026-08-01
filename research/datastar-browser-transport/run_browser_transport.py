#!/usr/bin/env python3
"""Drive pinned Datastar through a real Firefox and H1/H2 listener.

No Python packages are required. Firefox is controlled through geckodriver's
W3C WebDriver HTTP API, and curl supplies the cleartext-prior-knowledge H2
client that browsers do not expose on an http:// origin.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from typing import Any, Callable
from urllib.parse import urlsplit
from urllib.error import HTTPError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / "research" / "datastar-browser-transport"
ASSET = RESEARCH / "vendor" / "datastar-v1.0.2.js"
ASSET_SHA256 = "2837d87acf6ee0ba8e4e63765926c25a98d63883b02f88be194a86b81d3fd24a"
DEFAULT_SERVER = (
    ROOT
    / "research"
    / "datastar-transport"
    / "target"
    / "release"
    / "browser_transport_server"
)


def request_json(url: str) -> dict[str, Any]:
    with urlopen(url, timeout=2) as response:
        return json.load(response)


def request_text(url: str) -> str:
    with urlopen(url, timeout=2) as response:
        return response.read().decode("utf-8")


def wait_until(
    predicate: Callable[[], Any], timeout: float = 10.0, interval: float = 0.02
) -> Any:
    deadline = time.monotonic() + timeout
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except (HTTPError, OSError, RuntimeError) as error:
            last_error = error
        time.sleep(interval)
    suffix = f"; last error: {last_error}" if last_error else ""
    raise RuntimeError(f"condition did not become true within {timeout:.1f}s{suffix}")


def free_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=30) as response:
        return json.load(response)


class WebDriver:
    def __init__(self, geckodriver: str, firefox: str | None) -> None:
        self.port = free_port()
        self.log = tempfile.NamedTemporaryFile(
            prefix="datastar-geckodriver-", suffix=".log", delete=False
        )
        self.log.close()
        command = [geckodriver, "--port", str(self.port)]
        with open(self.log.name, "wb") as output:
            self.process = subprocess.Popen(command, stdout=output, stderr=output)
        wait_until(self._is_listening, timeout=10)
        options: dict[str, Any] = {"args": ["-headless"]}
        if firefox:
            options["binary"] = firefox
        created = post_json(
            self.url("/session"),
            {
                "capabilities": {
                    "alwaysMatch": {
                        "browserName": "firefox",
                        "acceptInsecureCerts": True,
                        "moz:firefoxOptions": options,
                    }
                }
            },
        )["value"]
        self.session_id = created["sessionId"]
        self.capabilities = created["capabilities"]

    def _is_listening(self) -> bool:
        if self.process.poll() is not None:
            raise RuntimeError(f"geckodriver exited; see {self.log.name}")
        with socket.create_connection(("127.0.0.1", self.port), timeout=0.2):
            return True

    def url(self, suffix: str) -> str:
        return f"http://127.0.0.1:{self.port}{suffix}"

    def navigate(self, url: str) -> None:
        post_json(self.url(f"/session/{self.session_id}/url"), {"url": url})

    def execute(self, script: str) -> Any:
        return post_json(
            self.url(f"/session/{self.session_id}/execute/sync"),
            {"script": script, "args": []},
        )["value"]

    def close(self) -> None:
        if hasattr(self, "session_id"):
            try:
                request = Request(
                    self.url(f"/session/{self.session_id}"), method="DELETE"
                )
                with urlopen(request, timeout=10):
                    pass
            except OSError:
                pass
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)


class NginxProxy:
    def __init__(self, nginx: str, upstream: str) -> None:
        self.port = free_port()
        self.directory = tempfile.TemporaryDirectory(prefix="datastar-nginx-")
        root = Path(self.directory.name)
        self.root = root
        for name in ("client", "proxy", "fastcgi", "scgi", "uwsgi"):
            (root / name).mkdir()
        upstream_address = urlsplit(upstream).netloc
        certificate = root / "certificate.pem"
        private_key = root / "private-key.pem"
        subprocess.run(
            [
                executable(None, "openssl"),
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "1",
                "-subj",
                "/CN=localhost",
                "-addext",
                "subjectAltName=IP:127.0.0.1,DNS:localhost",
                "-keyout",
                str(private_key),
                "-out",
                str(certificate),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        configuration = f"""
pid {root / 'nginx.pid'};
error_log {root / 'error.log'} info;
daemon off;
worker_processes 1;

events {{ worker_connections 64; }}

http {{
    access_log {root / 'access.log'};
    client_body_temp_path {root / 'client'};
    proxy_temp_path {root / 'proxy'};
    fastcgi_temp_path {root / 'fastcgi'};
    scgi_temp_path {root / 'scgi'};
    uwsgi_temp_path {root / 'uwsgi'};
    server {{
        listen 127.0.0.1:{self.port} ssl http2;
        ssl_certificate {certificate};
        ssl_certificate_key {private_key};
        location / {{
            proxy_pass http://{upstream_address};
            proxy_http_version 1.1;
            proxy_buffering on;
            proxy_read_timeout 10s;
        }}
    }}
}}
"""
        config = root / "nginx.conf"
        config.write_text(configuration, encoding="utf-8")
        self.process = subprocess.Popen(
            [nginx, "-p", f"{root}/", "-c", str(config)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.base = f"https://127.0.0.1:{self.port}"
        wait_until(self._is_ready, timeout=10)

    def _is_ready(self) -> bool:
        if self.process.poll() is not None:
            error = self.process.stderr.read() if self.process.stderr else ""
            error_log = self.root / "error.log"
            if error_log.exists():
                error += "\n" + error_log.read_text(encoding="utf-8")
            raise RuntimeError(
                f"NGINX exited before its listener became ready: {error.strip()}"
            )
        with socket.create_connection(("127.0.0.1", self.port), timeout=0.2):
            return True

    def close(self) -> None:
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        self.directory.cleanup()


def start_server(binary: Path) -> tuple[subprocess.Popen[str], str]:
    process = subprocess.Popen(
        [str(binary), "--port", "0"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=1,
    )
    assert process.stdout is not None
    line = process.stdout.readline()
    if not line:
        stderr = process.stderr.read() if process.stderr else ""
        raise RuntimeError(f"server failed before startup: {stderr}")
    startup = json.loads(line)
    return process, f"http://{startup['address']}"


def browser_progressive_case(
    driver: WebDriver, page_base: str, control_base: str, case_id: str, coding: str
) -> dict[str, Any]:
    started = time.monotonic_ns()
    driver.navigate(f"{page_base}/?id={case_id}&coding={coding}")
    wait_until(
        lambda: driver.execute(
            'return document.querySelector(\'[data-phase="one"]\') !== null'
        )
    )
    first_visible = time.monotonic_ns()
    before_release = request_json(f"{control_base}/status?id={case_id}")
    assert before_release["second_generated_us"] is None, before_release
    assert before_release["selected_encoding"] == coding, before_release
    assert before_release["datastar_request"] == "true", before_release

    request_text(f"{control_base}/release?id={case_id}")
    wait_until(
        lambda: driver.execute(
            'return document.querySelector(\'[data-phase="two"]\') !== null'
        )
    )
    second_visible = time.monotonic_ns()
    finished = wait_until(
        lambda: (
            status
            if (status := request_json(f"{control_base}/status?id={case_id}"))[
                "finished_us"
            ]
            is not None
            else None
        )
    )
    time.sleep(0.25)
    final = request_json(f"{control_base}/status?id={case_id}")
    assert final["requests"] == 1, final
    assert not final["aborted"], final
    if coding == "br":
        assert final["finish_tail_bytes"] > 0, final
        assert "br" in final["accept_encoding"].lower(), final
    else:
        assert final["finish_tail_bytes"] == 0, final
    next_hop = driver.execute(
        "const entries = performance.getEntriesByType('resource')"
        ".filter((entry) => entry.name.includes('/stream?id='));"
        "return entries.length ? entries.at(-1).nextHopProtocol : '';"
    )
    expected_next_hop = "http/1.1" if page_base == control_base else "h2"
    assert next_hop == expected_next_hop, (next_hop, expected_next_hop)
    return {
        "case": "firefox-progressive",
        "path": "direct" if page_base == control_base else "proxy",
        "coding": coding,
        "first_visible_ms": (first_visible - started) / 1_000_000,
        "second_visible_after_first_ms": (second_visible - first_visible) / 1_000_000,
        "before_release": before_release,
        "final": final,
        "finish_observation": finished,
        "browser_next_hop_protocol": next_hop,
    }


def browser_cancellation_case(
    driver: WebDriver, page_base: str, control_base: str, case_id: str
) -> dict[str, Any]:
    driver.navigate(f"{page_base}/?id={case_id}&coding=br")
    wait_until(
        lambda: driver.execute(
            'return document.querySelector(\'[data-phase="one"]\') !== null'
        )
    )
    before_abort = request_json(f"{control_base}/status?id={case_id}")
    assert before_abort["second_generated_us"] is None, before_abort
    aborted_at = time.monotonic_ns()
    driver.navigate("about:blank")
    cleaned = wait_until(
        lambda: (
            status
            if (status := request_json(f"{control_base}/status?id={case_id}"))[
                "aborted"
            ]
            else None
        )
    )
    cleanup_seen = time.monotonic_ns()
    assert cleaned["finished_us"] is None, cleaned
    assert cleaned["finish_tail_bytes"] == 0, cleaned
    assert cleaned["second_generated_us"] is None, cleaned
    return {
        "case": "firefox-navigation-cancellation",
        "path": "direct" if page_base == control_base else "proxy",
        "coding": "br",
        "cleanup_observed_ms": (cleanup_seen - aborted_at) / 1_000_000,
        "before_abort": before_abort,
        "final": cleaned,
    }


def h2_progressive_case(base: str, case_id: str, coding: str) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="datastar-h2-") as temporary:
        headers_path = Path(temporary) / "headers.txt"
        command = [
            "curl",
            "--silent",
            "--show-error",
            "--http2-prior-knowledge",
            "--no-buffer",
            "--compressed",
            "--dump-header",
            str(headers_path),
            f"{base}/stream?id={case_id}&coding={coding}",
        ]
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert process.stdout is not None
        chunks: list[bytes] = []

        def read_output() -> None:
            while chunk := process.stdout.read(1):
                chunks.append(chunk)

        reader = threading.Thread(target=read_output, daemon=True)
        reader.start()
        started = time.monotonic_ns()
        wait_until(lambda: b'data-phase="one"' in b"".join(chunks))
        first_visible = time.monotonic_ns()
        before_release = request_json(f"{base}/status?id={case_id}")
        assert before_release["second_generated_us"] is None, before_release
        assert before_release["protocol"] == "HTTP/2.0", before_release
        request_text(f"{base}/release?id={case_id}")
        process.wait(timeout=10)
        reader.join(timeout=2)
        stderr = process.stderr.read().decode("utf-8") if process.stderr else ""
        if process.returncode != 0:
            raise RuntimeError(f"curl H2 failed: {stderr}")
        decoded = b"".join(chunks)
        assert b'data-phase="two"' in decoded, decoded
        final = request_json(f"{base}/status?id={case_id}")
        assert final["finished_us"] is not None, final
        assert not final["aborted"], final
        raw_headers = headers_path.read_text(encoding="iso-8859-1")
        if coding == "br":
            assert "content-encoding: br" in raw_headers.lower(), raw_headers
            assert final["finish_tail_bytes"] > 0, final
        return {
            "case": "curl-progressive",
            "path": "direct",
            "protocol": "HTTP/2 prior knowledge",
            "coding": coding,
            "first_decoded_ms": (first_visible - started) / 1_000_000,
            "before_release": before_release,
            "final": final,
            "response_headers": raw_headers.strip().splitlines(),
            "decoded_bytes": len(decoded),
        }


def verify_asset() -> None:
    digest = hashlib.sha256(ASSET.read_bytes()).hexdigest()
    if digest != ASSET_SHA256:
        raise RuntimeError(f"Datastar asset SHA-256 {digest}, want {ASSET_SHA256}")


def executable(name_or_path: str | None, default: str) -> str:
    value = name_or_path or shutil.which(default)
    if not value:
        raise RuntimeError(f"required executable not found: {default}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", type=Path, default=DEFAULT_SERVER)
    parser.add_argument("--geckodriver")
    parser.add_argument("--firefox")
    parser.add_argument(
        "--nginx",
        help="optional real NGINX binary; exercises proxy_buffering on with X-Accel-Buffering: no",
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    verify_asset()
    if not args.server.is_file():
        raise RuntimeError(
            f"server binary not found at {args.server}; build the release binary first"
        )
    geckodriver = executable(args.geckodriver, "geckodriver")
    # Let geckodriver resolve Firefox by default. In snap-based installations
    # `/usr/bin/firefox` is a launcher script, not a browser binary accepted by
    # the `moz:firefoxOptions.binary` capability.
    firefox = args.firefox

    server, base = start_server(args.server)
    driver: WebDriver | None = None
    proxy: NginxProxy | None = None
    results: list[dict[str, Any]] = []
    try:
        wait_until(lambda: request_text(f"{base}/health") == "ok\n")
        driver = WebDriver(geckodriver, firefox)
        results.append(
            {
                "case": "environment",
                "datastar_version": "v1.0.2",
                "datastar_commit": "e24f04d43ca4445d662b4a035e5bfe9ed68de57c",
                "datastar_asset_sha256": ASSET_SHA256,
                "browser_name": driver.capabilities["browserName"],
                "browser_version": driver.capabilities["browserVersion"],
                "browser_user_agent": driver.capabilities["userAgent"],
                "geckodriver": subprocess.check_output(
                    [geckodriver, "--version"], text=True
                ).splitlines()[0],
                "server": str(args.server),
            }
        )
        for coding in ("identity", "br"):
            results.append(
                browser_progressive_case(
                    driver, base, base, f"firefox-direct-{coding}", coding
                )
            )
        results.append(
            browser_cancellation_case(
                driver, base, base, "firefox-direct-cancel-br"
            )
        )
        for coding in ("identity", "br"):
            results.append(h2_progressive_case(base, f"h2-direct-{coding}", coding))
        if args.nginx:
            nginx = executable(args.nginx, "nginx")
            proxy = NginxProxy(nginx, base)
            version = subprocess.run(
                [nginx, "-v"], text=True, capture_output=True, check=True
            )
            results.append(
                {
                    "case": "proxy-environment",
                    "proxy": (version.stderr or version.stdout).strip(),
                    "configuration": "TLS HTTP/2 frontend; proxy_buffering on; upstream HTTP/1.1; backend X-Accel-Buffering: no",
                }
            )
            for coding in ("identity", "br"):
                results.append(
                    browser_progressive_case(
                        driver,
                        proxy.base,
                        base,
                        f"firefox-nginx-{coding}",
                        coding,
                    )
                )
            results.append(
                browser_cancellation_case(
                    driver, proxy.base, base, "firefox-nginx-cancel-br"
                )
            )
    finally:
        if proxy:
            proxy.close()
        if driver:
            driver.close()
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=5)

    lines = "".join(json.dumps(result, sort_keys=True) + "\n" for result in results)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(lines, encoding="utf-8")
    sys.stdout.write(lines)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
