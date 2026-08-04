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
    driver.execute("document.querySelector('#view-transition').click()")
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#view-transition').textContent === 'Swap It!'"
        ),
        "Animations restored view-transition patch",
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


def bulk_update(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/bulk_update")
    wait_until(
        lambda: driver.execute(
            """
            const statuses = [...document.querySelectorAll('#demo td.status')]
                .map(element => element.textContent);
            return JSON.stringify(statuses) === JSON.stringify([
                'Inactive', 'Inactive', 'Active', 'Active'
            ]);
            """
        ),
        "Bulk Update initial statuses",
    )

    driver.execute(
        """
        const rows = [...document.querySelectorAll('#demo tbody tr')];
        rows[0].querySelector('input').click();
        rows[1].querySelector('input').click();
        document.querySelector('[data-action="activate"]').click();
        """
    )
    wait_until(
        lambda: driver.execute(
            """
            const rows = [...document.querySelectorAll('#demo tbody tr')];
            return rows[0].querySelector('.status').textContent === 'Active'
                && rows[1].querySelector('.status').textContent === 'Active'
                && rows.every(row => row.querySelector('.status').textContent === 'Active')
                && rows[0].querySelector('input').checked
                && rows[1].querySelector('input').checked;
            """
        ),
        "Bulk Update activate patch and retained selections",
    )

    driver.execute(
        """document.querySelector('input[aria-label="Select all users"]').click()"""
    )
    wait_until(
        lambda: driver.execute(
            """
            return [...document.querySelectorAll('#demo tbody input[type="checkbox"]')]
                .every(input => input.checked);
            """
        ),
        "Bulk Update select-all binding",
    )
    driver.execute("document.querySelector('[data-action=\"deactivate\"]').click()")
    wait_until(
        lambda: driver.execute(
            """
            return [...document.querySelectorAll('#demo td.status')]
                .every(element => element.textContent === 'Inactive');
            """
        ),
        "Bulk Update deactivate patch",
    )


def click_to_edit(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/click_to_edit")
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('[data-field="first-name"]').textContent === 'John'
                && document.querySelector('[data-field="last-name"]').textContent === 'Doe';
            """
        ),
        "Click To Edit initial contact",
    )

    driver.execute("document.querySelector('[data-action=\"edit\"]').click()")
    wait_until(
        lambda: driver.execute(
            """
            const inputs = [...document.querySelectorAll('#demo input')];
            return inputs.length === 3
                && inputs[0].value === 'John'
                && inputs[1].value === 'Doe'
                && inputs[2].value === 'john@example.com';
            """
        ),
        "Click To Edit signal-bound edit fields",
    )
    driver.execute(
        """
        const firstName = document.querySelectorAll('#demo input')[0];
        firstName.value = 'Discarded';
        firstName.dispatchEvent(new Event('input', {bubbles: true}));
        document.querySelector('[data-action="cancel"]').click();
        """
    )
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('[data-field="first-name"]').textContent === 'John'
                && document.querySelector('#demo input') === null;
            """
        ),
        "Click To Edit cancel restores saved contact",
    )

    driver.execute("document.querySelector('[data-action=\"edit\"]').click()")
    wait_until(
        lambda: driver.execute("return document.querySelectorAll('#demo input').length === 3"),
        "Click To Edit second edit view",
    )
    driver.execute(
        """
        const values = ['Jane', 'Roc', 'jane@example.com'];
        [...document.querySelectorAll('#demo input')].forEach((input, index) => {
            input.value = values[index];
            input.dispatchEvent(new Event('input', {bubbles: true}));
        });
        document.querySelector('[data-action="save"]').click();
        """
    )
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('[data-field="first-name"]').textContent === 'Jane'
                && document.querySelector('[data-field="last-name"]').textContent === 'Roc'
                && document.querySelector('[data-field="email"]').textContent === 'jane@example.com';
            """
        ),
        "Click To Edit saved contact patch",
    )

    driver.execute("document.querySelector('[data-action=\"reset\"]').click()")
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('[data-field="first-name"]').textContent === 'John'
                && document.querySelector('[data-field="email"]').textContent === 'john@example.com';
            """
        ),
        "Click To Edit reset patch",
    )


def click_to_load(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/click_to_load")
    wait_until(
        lambda: driver.execute(
            "return document.querySelectorAll('#agents tbody tr').length === 10"
        ),
        "Click To Load initial page",
    )

    driver.execute("document.querySelector('#load-more').click()")
    wait_until(
        lambda: driver.execute(
            """
            const rows = [...document.querySelectorAll('#agents tbody tr')];
            const button = document.querySelector('#load-more');
            return rows.length === 20
                && rows[19].dataset.agent === '19'
                && rows[19].children[0].textContent === 'Agent Smith 19'
                && !button.disabled
                && button.textContent === 'Load More';
            """
        ),
        "Click To Load appended second page",
    )

    driver.execute("document.querySelector('#load-more').click()")
    wait_until(
        lambda: driver.execute(
            """
            const rows = [...document.querySelectorAll('#agents tbody tr')];
            const button = document.querySelector('#load-more');
            return rows.length === 30
                && rows[29].dataset.agent === '29'
                && button.tagName === 'P'
                && button.textContent === 'All agents loaded';
            """
        ),
        "Click To Load final page and completion patch",
    )


def custom_event(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/custom_event")

    def current_event() -> str:
        return driver.execute(
            """
            const prefix = 'Last Event Details: ';
            const text = document.querySelector('#custom-event-output')?.textContent ?? '';
            if (!text.startsWith(prefix)) return '';
            try {
                return JSON.parse(text.slice(prefix.length)).eventTime ? text : '';
            } catch (_error) {
                return '';
            }
            """
        )

    first_event = wait_until(current_event, "Custom Event first signal update")
    wait_until(
        lambda: (current_event() or first_event) != first_event,
        "Custom Event repeated signal update",
    )


def custom_plugin(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/custom_plugin")
    wait_until(
        lambda: driver.execute(
            "return document.documentElement.dataset.customPluginReady === 'true'"
        ),
        "Custom Plugin registration",
    )
    driver.execute(
        """
        window.__datastarAlerts = [];
        window.alert = message => window.__datastarAlerts.push(String(message));
        document.querySelector('[data-plugin-kind="action"]').click();
        document.querySelector('[data-plugin-kind="attribute"]').click();
        """
    )
    wait_until(
        lambda: driver.execute(
            """
            return JSON.stringify(window.__datastarAlerts) === JSON.stringify([
                'Hello from an action',
                'Hello from an attribute',
            ]);
            """
        ),
        "Custom Plugin action and attribute callbacks",
    )


def delete_row(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/delete_row")
    wait_until(
        lambda: driver.execute(
            "return document.querySelectorAll('#delete-row-body tr').length === 3"
        ),
        "Delete Row initial rows",
    )
    driver.execute(
        """
        window.confirm = () => true;
        document.querySelector('[data-delete-row="0"]').click();
        """
    )
    wait_until(
        lambda: driver.execute(
            "return document.querySelectorAll('#delete-row-body tr').length === 2"
        ),
        "Delete Row removal patch",
    )
    driver.execute("document.querySelector('[data-action=\"reset-delete-rows\"]').click()")
    wait_until(
        lambda: driver.execute(
            "return document.querySelectorAll('#delete-row-body tr').length === 3"
        ),
        "Delete Row reset patch",
    )


def edit_row(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/edit_row")
    driver.execute("document.querySelector('[data-edit-row=\"0\"]').click()")
    wait_until(
        lambda: driver.execute(
            "return document.querySelectorAll('#edit-row-0 input').length === 2"
        ),
        "Edit Row editor patch",
    )
    driver.execute(
        """
        const values = ['Jane Roc', 'jane@example.com'];
        [...document.querySelectorAll('#edit-row-0 input')].forEach((input, index) => {
            input.value = values[index];
            input.dispatchEvent(new Event('input', {bubbles: true}));
        });
        document.querySelector('[data-action="save-edit-0"]').click();
        """
    )
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('[data-edit-name="0"]').textContent === 'Jane Roc'
                && document.querySelector('[data-edit-email="0"]').textContent === 'jane@example.com';
            """
        ),
        "Edit Row saved patch",
    )
    driver.execute("document.querySelector('[data-action=\"reset-edit-rows\"]').click()")
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('[data-edit-name=\"0\"]').textContent === 'Joe Smith'"
        ),
        "Edit Row reset patch",
    )


def event_bubbling(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/event_bubbling")
    driver.execute(
        "document.querySelector('#event-bubbling-container [data-id=\"FETCH\"]').click()"
    )
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#event-bubbling-key').textContent === 'FETCH'"
        ),
        "Event Bubbling delegated click",
    )


def on_signal_patch(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/on_signal_patch")
    driver.execute("document.querySelector('[data-action=\"signal-message\"]').click()")
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('#signal-patch-message').textContent === 'Updated message'
                && document.querySelector('#all-signal-patches').textContent.includes('message');
            """
        ),
        "On Signal Patch unfiltered observer",
    )
    driver.execute("document.querySelector('[data-action=\"signal-counter\"]').click()")
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('#signal-patch-counter').textContent === '1'
                && document.querySelector('#counter-signal-patches').textContent.includes('counter');
            """
        ),
        "On Signal Patch filtered observer",
    )


def sortable(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/sortable")
    driver.execute("document.querySelector('#sortable-move-first').click()")
    wait_until(
        lambda: driver.execute(
            """
            const items = [...document.querySelectorAll('#sortable-list [data-sort-item]')];
            return items.map(item => item.dataset.sortItem).join(', ') === 'Bravo, Charlie, Alpha'
                && document.querySelector('#sortable-order').textContent === 'Bravo, Charlie, Alpha';
            """
        ),
        "Sortable reordered event",
    )


def web_component(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/web_component")
    wait_until(
        lambda: driver.execute(
            "return document.documentElement.dataset.webComponentReady === 'true'"
        ),
        "Web Component definition",
    )
    driver.execute(
        """
        const input = document.querySelector('#web-component-name');
        input.value = 'Datastar Roc';
        input.dispatchEvent(new Event('input', {bubbles: true}));
        """
    )
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('#reverse-component').textContent === 'coR ratsataD'
                && document.querySelector('#web-component-reversed').textContent === 'coR ratsataD';
            """
        ),
        "Web Component signal and event interop",
    )


def match_media(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/match_media")
    wait_until(
        lambda: driver.execute(
            """
            const expected = matchMedia('(prefers-color-scheme: dark)').matches
                ? 'Dark color scheme'
                : 'Light color scheme';
            return document.documentElement.dataset.matchMediaReady === 'true'
                && document.querySelector('#match-media-result').textContent === expected;
            """
        ),
        "Match Media reactive preference",
    )


def file_upload(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/file_upload")
    driver.execute(
        """
        const transfer = new DataTransfer();
        transfer.items.add(new File(['roc'], 'probe.txt', {type: 'text/plain'}));
        const input = document.querySelector('#file-upload-input');
        input.files = transfer.files;
        input.dispatchEvent(new Event('change', {bubbles: true}));
        """
    )
    wait_until(
        lambda: driver.execute(
            "return !document.querySelector('[data-action=\"upload-files\"]').disabled"
        ),
        "File Upload file binding",
    )
    driver.execute("document.querySelector('[data-action=\"upload-files\"]').click()")
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#file-upload').textContent.includes('Received 1 file(s): probe.txt.')"
        ),
        "File Upload file-signal response patch",
    )


def form_data(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/form_data")
    driver.execute(
        """
        document.querySelector('input[value="bar"]').click();
        document.querySelector('[data-action="form-get"]').click();
        """
    )
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#form-data-result').textContent === 'Received checkbox value: bar'"
        ),
        "Form Data GET form response",
    )


def inline_validation(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/inline_validation")
    driver.execute(
        """
        const values = {
            '#validation-email': 'test@test.com',
            '#validation-first-name': 'Jane',
            '#validation-last-name': 'Roc',
        };
        for (const [selector, value] of Object.entries(values)) {
            const input = document.querySelector(selector);
            input.value = value;
            input.dispatchEvent(new Event('input', {bubbles: true}));
        }
        """
    )
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('[data-validation-result="valid"]')?.textContent === 'All fields are valid.'
                && document.querySelector('#validation-submit').getAttribute('aria-disabled') === 'false';
            """
        ),
        "Inline Validation valid status patch",
    )


def dbmon(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/dbmon")
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#dbmon-render').textContent === 'Render frame 6'"
        ),
        "DBmon retained updates",
    )
    driver.execute(
        """
        const mutation = document.querySelector('#dbmon-mutation');
        mutation.value = '35';
        mutation.dispatchEvent(new Event('input', {bubbles: true}));
        mutation.dispatchEvent(new Event('change', {bubbles: true}));
        const fps = document.querySelector('#dbmon-fps');
        fps.value = '72';
        fps.dispatchEvent(new Event('input', {bubbles: true}));
        fps.dispatchEvent(new Event('change', {bubbles: true}));
        """
    )
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#dbmon-settings').textContent === 'Mutation 35%, 72 FPS'"
        ),
        "DBmon settings patch",
    )


def infinite_scroll(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/infinite_scroll")
    driver.execute("document.querySelector('#infinite-scroll-sentinel').scrollIntoView()")
    wait_until(
        lambda: driver.execute(
            "return document.querySelectorAll('#infinite-agents tr').length >= 20"
        ),
        "Infinite Scroll intersection append",
    )


def lazy_load(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/lazy_load")
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#lazy-graph') !== null && document.querySelector('#lazy-load').textContent.includes('Graph loaded.')"
        ),
        "Lazy Load graph patch",
    )


def lazy_tabs(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/lazy_tabs")
    driver.execute("document.querySelector('[data-lazy-tab=\"3\"]').click()")
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#lazy-tab-panel').textContent === 'Content loaded for tab 3.'"
        ),
        "Lazy Tabs selected content patch",
    )


def progress_bar(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/progress_bar")
    wait_until(
        lambda: driver.execute(
            """
            const root = document.querySelector('#progress-bar');
            return root.querySelector('progress').value === 100
                && root.querySelector('span').textContent === '100%';
            """
        ),
        "Progress Bar completed stream",
    )


def progressive_load(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/progressive_load")
    driver.execute("document.querySelector('#load-button').click()")
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('#progressive-header').textContent.includes('Loaded header')
                && document.querySelector('#progressive-article').textContent.includes('Loaded article')
                && document.querySelector('#progressive-comments').textContent.includes('Loaded comments')
                && document.querySelector('#progressive-footer').textContent.includes('Loaded footer')
                && document.querySelector('#load-button').textContent === 'Load again'
                && !document.querySelector('#load-button').disabled;
            """
        ),
        "Progressive Load completed regions",
    )


def svg_morphing(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/svg_morphing")
    driver.execute("document.querySelector('[data-action=\"morph-circle\"]').click()")
    wait_until(
        lambda: driver.execute(
            "return document.querySelector('#morph-circle').getAttribute('fill') === 'blue'"
        ),
        "SVG Morphing namespaced patch",
    )


def templ_counter(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/templ_counter")
    driver.execute(
        """
        document.querySelector('#global-counter').click();
        document.querySelector('#user-counter').click();
        """
    )
    wait_until(
        lambda: driver.execute(
            """
            return document.querySelector('#global-counter').textContent === 'Increment Global: 5225'
                && document.querySelector('#user-counter').textContent === 'Increment User: 1';
            """
        ),
        "Templ Counter independent patches",
    )


def title_update(driver: Firefox, base: str) -> None:
    driver.navigate(f"{base}/examples/title_update")
    wait_until(
        lambda: driver.execute("return document.title === 'Title Update frame 3'"),
        "Title Update completed stream",
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
            bulk_update(driver, base)
            click_to_edit(driver, base)
            click_to_load(driver, base)
            custom_event(driver, base)
            custom_plugin(driver, base)
            delete_row(driver, base)
            edit_row(driver, base)
            event_bubbling(driver, base)
            on_signal_patch(driver, base)
            sortable(driver, base)
            web_component(driver, base)
            match_media(driver, base)
            file_upload(driver, base)
            form_data(driver, base)
            inline_validation(driver, base)
            dbmon(driver, base)
            infinite_scroll(driver, base)
            lazy_load(driver, base)
            lazy_tabs(driver, base)
            progress_bar(driver, base)
            progressive_load(driver, base)
            svg_morphing(driver, base)
            templ_counter(driver, base)
            title_update(driver, base)
        print(
            "PASS Active Search, Animations, Bad Apple, Bulk Update, "
            "Click To Edit, Click To Load, Custom Event, Custom Plugin, "
            "Delete Row, Edit Row, Event Bubbling, On Signal Patch, Sortable, "
            "Web Component, Match Media, File Upload, Form Data, "
            "Inline Validation, DBmon, Infinite Scroll, Lazy Load, Lazy Tabs, "
            "Progress Bar, Progressive Load, SVG Morphing, Templ Counter, "
            "Title Update "
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
