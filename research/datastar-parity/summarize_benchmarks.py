#!/usr/bin/env python3
"""Print median and range for committed Go benchmark output."""

from __future__ import annotations

import pathlib
import re
import statistics


RESULTS = pathlib.Path(__file__).resolve().parent / "results/go-microbench.txt"
LINE = re.compile(
    r"^(Benchmark\S+)-\d+\s+\d+\s+([0-9.]+) ns/op\s+"
    r"[0-9.]+ MB/s(?:\s+([0-9.]+) wire-B/(?:event|response))?\s+"
    r"([0-9]+) B/op\s+([0-9]+) allocs/op$"
)


def main() -> None:
    groups: dict[str, list[tuple[float, float | None, int, int]]] = {}
    for line in RESULTS.read_text().splitlines():
        match = LINE.match(line)
        if match:
            name, nanos, wire, allocated, allocations = match.groups()
            groups.setdefault(name, []).append(
                (float(nanos), float(wire) if wire else None, int(allocated), int(allocations))
            )

    print("| Benchmark | n | ns/op median [min, max] | B/op median | allocs/op median | wire bytes |")
    print("| --- | ---: | ---: | ---: | ---: | ---: |")
    for name, samples in groups.items():
        nanos = [sample[0] for sample in samples]
        allocated = [sample[2] for sample in samples]
        allocations = [sample[3] for sample in samples]
        wire = [sample[1] for sample in samples if sample[1] is not None]
        wire_value = f"{statistics.median(wire):.2f}" if wire else "—"
        print(
            f"| `{name.removeprefix('BenchmarkOfficialSDK')}` | {len(samples)} | "
            f"{statistics.median(nanos):.1f} [{min(nanos):.1f}, {max(nanos):.1f}] | "
            f"{statistics.median(allocated):.0f} | {statistics.median(allocations):.0f} | "
            f"{wire_value} |"
        )


if __name__ == "__main__":
    main()
