#!/usr/bin/env python3
"""Regenerate Rust ABI bindings for the basic-webserver Roc platform."""

from __future__ import annotations

import argparse
import difflib
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


# Glue provenance: the committed Rust glue is generated with the compiler and
# RustGlue.roc shipped together in nightly-2026-July-29-fe0ab22. Compiler and
# glue-spec revisions must match.
ROOT = Path(__file__).resolve().parents[1]
KNOWN_GOOD_REVISION = "fe0ab22cf0a764249330342fa36363624fc8157d"


def rooted_path(value: str) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else ROOT / path


def roc_executable(value: str) -> str:
    resolved = shutil.which(value)
    if resolved is None:
        candidate = rooted_path(value)
        if candidate.is_file():
            return str(candidate)
        raise SystemExit(
            f"Could not find roc executable {value!r}. Set ROC=/path/to/roc."
        )
    return resolved


def require_known_roc(roc: str) -> None:
    result = subprocess.run(
        [roc, "version"],
        check=True,
        capture_output=True,
        text=True,
    )
    version = f"{result.stdout}\n{result.stderr}"
    if KNOWN_GOOD_REVISION[:7] not in version:
        raise SystemExit(
            "Rust glue must be generated with the pinned Roc compiler "
            f"{KNOWN_GOOD_REVISION[:7]}, but `roc version` reported:\n"
            f"{version.strip()}"
        )


def find_glue_spec(roc: str) -> Path:
    explicit = os.environ.get("ROC_GLUE_SPEC") or os.environ.get("ROC_RUST_GLUE")
    if explicit:
        path = rooted_path(explicit)
        if not path.is_file():
            raise SystemExit(f"Rust glue spec not found: {path}")
        return path

    candidates: list[Path] = []
    roc_source = os.environ.get("ROC_SRC")
    if roc_source:
        candidates.append(rooted_path(roc_source) / "src/glue/src/RustGlue.roc")

    roc_path = Path(roc).resolve()
    roc_bin_dir = roc_path.parent
    candidates.append(roc_bin_dir.parent / "src/glue/src/RustGlue.roc")
    if roc_bin_dir.name == "bin" and roc_bin_dir.parent.name == "zig-out":
        candidates.append(
            roc_bin_dir.parent.parent / "src/glue/src/RustGlue.roc"
        )

    candidates.extend(
        (
            ROOT.parent / "roc/src/glue/src/RustGlue.roc",
            ROOT.parent.parent / "roc/src/glue/src/RustGlue.roc",
        )
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()

    raise SystemExit(
        "Could not find RustGlue.roc.\n"
        "Set ROC_SRC=/path/to/roc or "
        "ROC_GLUE_SPEC=/path/to/RustGlue.roc."
    )


def run_glue(roc: str, glue_spec: Path, platform_file: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [
            roc,
            "glue",
            "--no-cache",
            str(glue_spec),
            str(out_dir),
            str(platform_file),
        ],
        cwd=ROOT,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            "Glue generation failed.\n"
            "Use matching Roc and RustGlue.roc revisions; "
            f"{KNOWN_GOOD_REVISION} is the known-good pair."
        )


def check_generated(committed: Path, generated: Path) -> None:
    if not committed.is_file():
        raise SystemExit(f"Missing generated glue file: {committed}")
    if committed.read_bytes() == generated.read_bytes():
        print(f"Rust glue is up to date: {committed.relative_to(ROOT)}")
        return

    before = committed.read_text(encoding="utf-8").splitlines(keepends=True)
    after = generated.read_text(encoding="utf-8").splitlines(keepends=True)
    print(
        "".join(
            difflib.unified_diff(
                before,
                after,
                fromfile=str(committed),
                tofile=str(generated),
            )
        ),
        end="",
    )
    raise SystemExit(
        "Generated Rust glue is stale. Run scripts/regenerate_glue.py "
        "and commit the result."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="generate into a temporary directory and compare with committed glue",
    )
    args = parser.parse_args()

    roc = roc_executable(os.environ.get("ROC", "roc"))
    require_known_roc(roc)
    glue_spec = find_glue_spec(roc)
    platform_file = rooted_path(os.environ.get("PLATFORM_FILE", "platform/main.roc"))
    out_dir = rooted_path(os.environ.get("GLUE_OUT_DIR", "src"))

    if not platform_file.is_file():
        raise SystemExit(f"Platform file not found: {platform_file}")

    if args.check:
        with tempfile.TemporaryDirectory(prefix="basic-webserver-glue-") as raw_temp:
            temporary = Path(raw_temp)
            run_glue(roc, glue_spec, platform_file, temporary)
            check_generated(
                out_dir / "roc_platform_abi.rs",
                temporary / "roc_platform_abi.rs",
            )
        return

    print(f"Using roc: {roc}")
    print(f"Using glue spec: {glue_spec}")
    print(f"Platform: {platform_file}")
    print(f"Output dir: {out_dir}")
    run_glue(roc, glue_spec, platform_file, out_dir)
    print(f"Generated: {out_dir / 'roc_platform_abi.rs'}")


if __name__ == "__main__":
    main()
