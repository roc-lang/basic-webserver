#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
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


def generate_rust_dependency_licenses(
    output: Path, selected_targets: tuple[str, ...]
) -> None:
    packages_by_id: dict[str, dict[str, object]] = {}
    for target in selected_targets:
        metadata = json.loads(
            subprocess.check_output(
                [
                    "cargo",
                    "metadata",
                    "--locked",
                    "--format-version",
                    "1",
                    "--filter-platform",
                    RUST_TARGETS[target],
                ],
                cwd=ROOT,
                text=True,
            )
        )
        reachable = {node["id"] for node in metadata["resolve"]["nodes"]}
        packages_by_id.update(
            (package["id"], package)
            for package in metadata["packages"]
            if package["id"] in reachable
            and str(package.get("source", "")).startswith("registry+")
        )
    packages = sorted(
        packages_by_id.values(),
        key=lambda package: (package["name"], package["version"]),
    )

    license_paths_by_id: dict[str, list[Path]] = {}
    for package in packages:
        package_root = Path(package["manifest_path"]).parent
        candidates: list[Path] = []
        license_file = package.get("license_file")
        if license_file:
            candidates.append(package_root / license_file)
        candidates.extend(
            sorted(
                path
                for path in package_root.iterdir()
                if path.name.lower().startswith(
                    ("license", "copying", "notice", "unlicense")
                )
            )
        )
        seen: set[Path] = set()
        license_paths_by_id[package["id"]] = []
        for candidate in candidates:
            candidate = candidate.resolve()
            if candidate.is_file() and candidate not in seen:
                seen.add(candidate)
                license_paths_by_id[package["id"]].append(candidate)

    lines = [
        "# Rust Dependency Licenses",
        "",
        "This file is generated from the exact dependencies in `Cargo.lock`.",
        "",
    ]
    for package in packages:
        license_paths = license_paths_by_id[package["id"]]
        license_source = package
        if not license_paths:
            repository = package.get("repository")
            license_expression = package.get("license")
            matching_upstream = next(
                (
                    candidate
                    for candidate in packages
                    if candidate["id"] != package["id"]
                    and repository
                    and candidate.get("repository") == repository
                    and license_expression
                    and candidate.get("license") == license_expression
                    and license_paths_by_id[candidate["id"]]
                ),
                None,
            )
            if matching_upstream is not None:
                license_source = matching_upstream
                license_paths = license_paths_by_id[matching_upstream["id"]]
        if not license_paths:
            raise SystemExit(
                f"No license text found for Rust dependency "
                f"{package['name']} {package['version']}"
            )

        lines.extend(
            [
                f"## {package['name']} {package['version']}",
                "",
                f"SPDX expression: `{package.get('license') or 'see included license'}`",
                "",
            ]
        )
        repository = package.get("repository")
        if repository:
            lines.extend([f"Source: {repository}", ""])
        if license_source["id"] != package["id"]:
            lines.extend(
                [
                    "License text supplied by "
                    f"`{license_source['name']} {license_source['version']}` "
                    "from the same upstream repository and SPDX license.",
                    "",
                ]
            )
        for license_path in license_paths:
            lines.extend(
                [
                    f"### {license_path.name}",
                    "",
                    "```text",
                    license_path.read_text(encoding="utf-8", errors="replace").rstrip(),
                    "```",
                    "",
                ]
            )

    write_text(output, "\n".join(lines))


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
    license_source = ROOT / "THIRD_PARTY_LICENSES.md"
    rust_licenses_target = PLATFORM_DIR / "RUST_DEPENDENCY_LICENSES.md"
    generate_rust_dependency_licenses(rust_licenses_target, selected_targets)
    unpacked_size = sum(path.stat().st_size for path in (*roc_files, *link_input_files))
    unpacked_size += license_source.stat().st_size + rust_licenses_target.stat().st_size
    if unpacked_size > MAX_PLATFORM_BYTES:
        rust_licenses_target.unlink(missing_ok=True)
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
    print("  THIRD_PARTY_LICENSES.md")
    print("  RUST_DEPENDENCY_LICENSES.md\n", flush=True)
    print(f"Unpacked platform size: {unpacked_size} bytes\n")

    license_target = PLATFORM_DIR / "THIRD_PARTY_LICENSES.md"
    shutil.copy2(license_source, license_target)
    try:
        subprocess.run(
            [
                args.roc,
                "bundle",
                *bundle_files,
                "THIRD_PARTY_LICENSES.md",
                "RUST_DEPENDENCY_LICENSES.md",
                "--output-dir",
                str(output_dir),
                *roc_args,
            ],
            cwd=PLATFORM_DIR,
            check=True,
        )
    finally:
        license_target.unlink(missing_ok=True)
        rust_licenses_target.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
