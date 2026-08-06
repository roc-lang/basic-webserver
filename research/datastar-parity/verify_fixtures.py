#!/usr/bin/env python3
"""Validate the pinned Datastar and generic SSE byte fixtures."""

from __future__ import annotations

import pathlib
import re


ROOT = pathlib.Path(__file__).resolve().parent / "fixtures"
LINE_END = re.compile(br"\r\n|\r|\n")


def parse_events(raw: bytes) -> list[dict[str, object]]:
    if not (raw.endswith(b"\n\n") or raw.endswith(b"\r\r") or raw.endswith(b"\r\n\r\n")):
        raise AssertionError("fixture does not end with a blank line")

    events: list[dict[str, object]] = []
    event = ""
    data: list[str] = []
    event_id: str | None = None
    retry: int | None = None

    for encoded in LINE_END.split(raw):
        line = encoded.decode("utf-8")
        if line == "":
            if data:
                events.append({
                    "event": event or "message",
                    "data": "\n".join(data),
                    "id": event_id,
                    "retry": retry,
                })
            event, data, event_id, retry = "", [], None, None
            continue
        if line.startswith(":"):
            continue
        field, separator, value = line.partition(":")
        if not separator:
            value = ""
        elif value.startswith(" "):
            value = value[1:]
        if field == "event":
            event = value
        elif field == "data":
            data.append(value)
        elif field == "id" and "\x00" not in value:
            event_id = value
        elif field == "retry" and value.isascii() and value.isdigit():
            retry = int(value)

    return events


def main() -> None:
    fixtures = sorted(ROOT.glob("*/*.sse"))
    assert fixtures, "no fixtures found"
    count = 0
    for fixture in fixtures:
        events = parse_events(fixture.read_bytes())
        assert events, f"{fixture}: no dispatchable events"
        for event in events:
            assert str(event["event"]).startswith("datastar-"), fixture
        count += len(events)

    id_case = parse_events((ROOT / "generic/id-clear-and-comment.sse").read_bytes())
    assert id_case[0]["id"] == "cursor-42"
    assert id_case[0]["retry"] == 1500
    assert id_case[1]["id"] == ""
    assert id_case[1]["data"] == '\nsignals {"ready":true}'
    print(f"validated {len(fixtures)} fixtures containing {count} events")


if __name__ == "__main__":
    main()
