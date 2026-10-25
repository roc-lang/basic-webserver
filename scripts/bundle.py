#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLATFORM_DIR = ROOT / "platform"
LIBRARY_EXTENSIONS = {".a", ".o", ".lib", ".obj"}
MAX_PLATFORM_BYTES = 100 * 1024 * 1024
TARGET_INPUTS = {
    "x64mac": ("libhost.a",),
    "arm64mac": ("libhost.a",),
    "x64musl": ("crt1.o", "libhost.a", "libunwind.a", "libc.a"),
    "arm64musl": ("crt1.o", "libhost.a", "libunwind.a", "libc.a"),
    "x64win": ("host.lib", "ws2_32.lib", "bcrypt.lib", "advapi32.lib"),
}
RUST_TARGETS = {
    "x64mac": "x86_64-apple-darwin",
    "arm64mac": "aarch64-apple-darwin",
    "x64musl": "x86_64-unknown-linux-musl",
    "arm64musl": "aarch64-unknown-linux-musl",
    "x64win": "x86_64-pc-windows-msvc",
}
# Bundle name for Rust's standard library notices.
RUST_LIBRARY_LICENSES = "RUST_LIBRARY_LICENSES.html"
PLATFORM_LINK_SUPPORT = (
    PLATFORM_DIR / "targets" / "macos-sysroot" / "usr" / "lib" / "libSystem.tbd",
)


def write_text(path: Path, text: str, newline: str = "\n") -> None:
    """Write ``text`` to ``path`` with fixed line endings (Path.write_text has no
    ``newline`` argument before Python 3.10)."""
    with path.open("w", encoding="utf-8", newline=newline) as handle:
        handle.write(text)


def relative_platform_path(path: Path) -> str:
    return path.relative_to(PLATFORM_DIR).as_posix()


def validate_target_manifest() -> None:
    source = (PLATFORM_DIR / "main.roc").read_text(encoding="utf-8")
    declared = {
        match.group(1): tuple(re.findall(r'"([^"]+)"', match.group(2)))
        for match in re.finditer(
            r"(?m)^\s*([a-zA-Z0-9_]+):\s*\{\s*inputs:\s*\[(.*?)\]\s*\},?\s*$",
            source,
        )
    }
    if declared != TARGET_INPUTS:
        raise SystemExit(
            "Release target manifest is out of sync with platform/main.roc:\n"
            f"  platform: {declared}\n"
            f"  bundler:  {TARGET_INPUTS}"
        )


def rust_library_licenses() -> Path:
    """Rust's notices for the statically linked standard library and its dependencies."""
    sysroot = Path(subprocess.check_output(["rustc", "--print", "sysroot"], text=True).strip())
    path = sysroot / "share" / "doc" / "rust" / "COPYRIGHT-library.html"
    if not path.is_file():
        raise SystemExit(
            "Rust standard library notices are missing; install them with "
            "`rustup component add rust-docs`"
        )
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description="Bundle the basic-webserver platform")
    parser.add_argument("--output-dir", type=Path, default=ROOT)
    parser.add_argument(
        "--target",
        action="append",
        choices=TARGET_INPUTS,
        dest="targets",
        help=(
            "include only this target (repeatable); defaults to every release target"
        ),
    )
    parser.add_argument(
        "--roc",
        default="roc",
        help="Roc compiler used to create the bundle",
    )
    args, roc_args = parser.parse_known_args()

    output_dir = args.output_dir
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    output_dir = output_dir.resolve()

    validate_target_manifest()
    selected_targets = tuple(args.targets or TARGET_INPUTS)
    roc_files = sorted(PLATFORM_DIR.glob("*.roc"))
    library_files = [
        PLATFORM_DIR / "targets" / target / filename
        for target in selected_targets
        for filename in TARGET_INPUTS[target]
    ]
    link_input_files = [*library_files]
    if any(target.endswith("mac") for target in selected_targets):
        link_input_files.extend(PLATFORM_LINK_SUPPORT)
    missing = [path for path in link_input_files if not path.is_file()]
    if missing:
        formatted = "\n".join(
            f"  {relative_platform_path(path)}" for path in missing
        )
        raise SystemExit(
            "Missing release target inputs; build all Unix targets and the "
            f"Windows host before bundling:\n{formatted}"
        )
    unexpected = [path for path in library_files if path.suffix not in LIBRARY_EXTENSIONS]
    if unexpected:
        raise SystemExit(f"Unexpected target input extension: {unexpected[0]}")

    bundle_files = [
        *(relative_platform_path(path) for path in roc_files),
        *(relative_platform_path(path) for path in link_input_files),
    ]
    license_sources = {
        "LICENSE": ROOT / "LICENSE",
        "THIRD_PARTY_LICENSES.md": ROOT / "THIRD_PARTY_LICENSES.md",
        RUST_LIBRARY_LICENSES: rust_library_licenses(),
    }
    unpacked_size = sum(
        path.stat().st_size
        for path in (*roc_files, *link_input_files, *license_sources.values())
    )
    if unpacked_size > MAX_PLATFORM_BYTES:
        raise SystemExit(
            "Platform inputs exceed Roc's default 100 MiB transitive dependency limit: "
            f"{unpacked_size} bytes. Rebuild Linux hosts with "
            "python scripts/build.py --all "
            "so their archives are stripped."
        )

    print(
        f"Bundling {len(roc_files)} .roc files and "
        f"{len(link_input_files)} link input files...\n"
    )
    print("Files to bundle:")
    for path in bundle_files:
        print(f"  {path}")
    for name in license_sources:
        print(f"  {name}")
    print(f"\nUnpacked platform size: {unpacked_size} bytes\n", flush=True)

    # Copied next to main.roc only for the bundle; restore any local file.
    backups: dict[Path, bytes | None] = {}
    try:
        for name, source in license_sources.items():
            destination = PLATFORM_DIR / name
            backups[destination] = destination.read_bytes() if destination.exists() else None
            shutil.copy2(source, destination)
        subprocess.run(
            [
                args.roc,
                "bundle",
                *bundle_files,
                *license_sources,
                "--output-dir",
                str(output_dir),
                *roc_args,
            ],
            cwd=PLATFORM_DIR,
            check=True,
        )
    finally:
        for destination, contents in backups.items():
            if contents is None:
                destination.unlink(missing_ok=True)
            else:
                destination.write_bytes(contents)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
