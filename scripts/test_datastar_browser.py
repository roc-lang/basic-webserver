#!/usr/bin/env python3
"""Exercise the Datastar showcase through a real Firefox DOM.

The runner uses only Python's standard library and geckodriver's W3C HTTP API.
It is intentionally separate from the cross-target listener suite: one native
browser run validates client behavior, while scripts/test.py validates every
independently built target artifact.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
from typing import Any, Callable
from urllib.error import HTTPError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise RuntimeError(message)


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
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        fail(f"WebDriver request failed with HTTP {error.code}: {detail}")


def wait_until(
    predicate: Callable[[], Any],
    description: str,
    timeout: float = 10.0,
) -> Any:
    deadline = time.monotonic() + timeout
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            result = predicate()
            if result:
                return result
        except (HTTPError, OSError, RuntimeError) as error:
            last_error = error
        time.sleep(0.02)
    detail = f"; last error: {last_error}" if last_error else ""
    fail(f"timed out waiting for {description}{detail}")


class Firefox:
    def __init__(self, geckodriver: str, firefox: str | None) -> None:
        self.port = free_port()
        self.log = tempfile.NamedTemporaryFile(
            prefix="basic-webserver-geckodriver-", suffix=".log", delete=False
        )
        self.log.close()
        with open(self.log.name, "wb") as output:
            self.process = subprocess.Popen(
                [geckodriver, "--port", str(self.port)],
                stdout=output,
                stderr=output,
            )
        wait_until(self.is_listening, "geckodriver startup")

        options: dict[str, Any] = {"args": ["-headless"]}
        if firefox:
            options["binary"] = firefox
        try:
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
        except BaseException:
            self.close()
            raise
        self.session_id = created["sessionId"]
        self.capabilities = created["capabilities"]

    def is_listening(self) -> bool:
        if self.process.poll() is not None:
            fail(f"geckodriver exited; see {self.log.name}")
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
        if hasattr(self, "process"):
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)


def start_server(binary: Path) -> tuple[subprocess.Popen[str], str]:
    process = subprocess.Popen(
        [str(binary)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert process.stdout is not None
    line = process.stdout.readline()
    if not line.startswith("Listening on <http://") or not line.rstrip().endswith(">"):
        stderr = process.stderr.read() if process.stderr else ""
        process.terminate()
        fail(f"showcase failed before startup: {line}{stderr}")
    return process, line.strip()[len("Listening on <") : -1]


def set_bound_input(driver: Firefox, value: str) -> None:
    driver.execute(
        """
        const input = [...document.querySelectorAll('input')]
            .find(element => element.hasAttribute('data-bind:active-search'));
        input.value = %s;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        """
        % json.dumps(value)
    )


def active_search(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/active_search")
    wait_until(
        lambda: driver.execute(
            "return document.querySelectorAll('#demo tbody tr').length === 15"
        ),
        "Active Search initial rows",
    )

    set_bound_input(driver, "bry")
    wait_until(
        lambda: driver.execute(
            """
            const rows = [...document.querySelectorAll('#demo tbody tr')];
            return rows.length === 1
                && rows[0].children[0].textContent === 'Bryana'
                && rows[0].children[1].textContent === 'Bernier';
            """
        ),
        "Active Search filtered DOM patch",
    )

    set_bound_input(driver, "no-match")
    wait_until(
        lambda: driver.execute(
            "return document.querySelectorAll('#demo tbody tr').length === 0"
        ),
        "Active Search empty DOM patch",
    )


def animations(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/animations")
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#throb').textContent !== 'brown on orange'"
        ),
        "Animations timer-driven throb patch",
    )

    driver.execute("document.querySelector('#view-transition').click()")
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#view-transition').textContent === 'Restore It!'"
        ),
        "Animations view-transition patch",
    )

    driver.execute("document.querySelector('#fade-out-swap').click()")
    wait_until(
        lambda: driver.execute(
            """
            const element = document.querySelector('#fade-out-swap');
            return element.tagName === 'BUTTON'
                && element.disabled
                && element.style.opacity === '0';
            """
        ),
        "Animations fade-out first patch",
    )
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#fade-out-swap').tagName === 'DIV'"
        ),
        "Animations fade-out removal patch",
    )
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#fade-out-swap').tagName === 'BUTTON'"
        ),
        "Animations fade-out restoration patch",
    )

    driver.execute("document.querySelector('#fade-me-in').click()")
    wait_until(
        lambda: driver.execute(
            """
            const element = document.querySelector('#fade-me-in');
            return element.disabled && element.style.opacity === '0';
            """
        ),
        "Animations fade-in first patch",
    )
    wait_until(
        lambda: driver.execute(
            """
            const element = document.querySelector('#fade-me-in');
            return !element.disabled && element.style.opacity !== '0';
            """
        ),
        "Animations fade-in final patch",
    )


def bad_apple(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/bad_apple")
    wait_until(
        lambda: driver.execute(
            """
            const value = Number(document.querySelector('#bad-apple input').value);
            return value > 0 && value < 100;
            """
        ),
        "Bad Apple intermediate signal patch",
    )
    wait_until(
        lambda: driver.execute(
            """
            const root = document.querySelector('#bad-apple');
            return Number(root.querySelector('input').value) === 100
                && root.querySelector('pre').textContent.includes('████');
            """
        ),
        "Bad Apple final signal patch",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--binary", type=Path)
    source.add_argument("--base-url")
    parser.add_argument("--geckodriver", default=shutil.which("geckodriver"))
    # Let geckodriver resolve Firefox unless an actual browser binary is
    # supplied. On snap-based Linux systems `which firefox` is a launcher
    # script and is not accepted by moz:firefoxOptions.binary.
    parser.add_argument("--firefox")
    parser.add_argument("--repeat", type=int, default=1)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.geckodriver:
        fail("geckodriver was not found on PATH")
    if args.repeat < 1:
        fail("--repeat must be at least 1")

    server: subprocess.Popen[str] | None = None
    if args.binary is not None:
        binary = args.binary.resolve()
        if not binary.is_file():
            fail(f"showcase binary does not exist: {binary}")
        server, base = start_server(binary)
    else:
        base = str(args.base_url).rstrip("/")
    driver: Firefox | None = None
    try:
        driver = Firefox(args.geckodriver, args.firefox)
        for _ in range(args.repeat):
            active_search(driver, base)
            animations(driver, base)
            bad_apple(driver, base)
        print(
            "PASS Active Search, Animations, Bad Apple "
            f"({driver.capabilities['browserName']} "
            f"{driver.capabilities['browserVersion']})"
        )
    finally:
        if driver is not None:
            driver.close()
        if server is not None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
