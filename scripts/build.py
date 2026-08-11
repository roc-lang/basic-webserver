#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    "x64mac": "x86_64-apple-darwin",
    "arm64mac": "aarch64-apple-darwin",
    "x64musl": "x86_64-unknown-linux-musl",
    "arm64musl": "aarch64-unknown-linux-musl",
}
ALL_TARGETS = tuple(TARGETS)
ROC_TARGETS = (*ALL_TARGETS, "x64win")
WINDOWS_TARGET = "x86_64-pc-windows-msvc"


def display_path(path: Path) -> Path:
    try:
        return path.relative_to(ROOT)
    except ValueError:
        return path
WINDOWS_SYSTEM_LIBRARIES = ("advapi32.lib", "bcrypt.lib", "ws2_32.lib")


def run(*args: str, env: dict[str, str] | None = None, check: bool = True) -> None:
    subprocess.run(args, cwd=ROOT, env=env, check=check)


def rust_host_target() -> str:
    output = subprocess.check_output(["rustc", "-vV"], text=True)
    for line in output.splitlines():
        if line.startswith("host: "):
            return line.removeprefix("host: ")
    raise SystemExit("Could not determine the Rust host target")


def find_llvm_strip() -> Path:
    executable = shutil.which("llvm-strip")
    if executable:
        return Path(executable)

    sysroot = Path(
        subprocess.check_output(["rustc", "--print", "sysroot"], text=True).strip()
    )
    executable = (
        sysroot / "lib" / "rustlib" / rust_host_target() / "bin" / "llvm-strip"
    )
    if executable.is_file():
        return executable

    raise SystemExit(
        "llvm-strip was not found; install it with "
        "`rustup component add llvm-tools-preview`"
    )


def strip_linux_host(target_name: str, platform_root: Path = ROOT / "platform") -> None:
    if not target_name.endswith("musl"):
        return

    path = platform_root / "targets" / target_name / "libhost.a"
    before = path.stat().st_size
    # Retain every symbol referenced by a relocation while dropping debug data
    # and unused archive symbols. This keeps the release below Roc's package
    # dependency size limit without changing link behavior.
    run(str(find_llvm_strip()), "--strip-unneeded", str(path))
    after = path.stat().st_size
    print(f"Stripped {target_name} libhost.a: {before} -> {after} bytes")


def detect_native_target() -> str:
    system = platform.system()
    machine = platform.machine().lower()

    if system == "Windows" and machine in {"amd64", "x86_64"}:
        return "x64win"
    if system == "Darwin":
        if machine in {"arm64", "aarch64"}:
            return "arm64mac"
        if machine in {"x86_64", "amd64"}:
            return "x64mac"
    if system == "Linux":
        if machine in {"aarch64", "arm64"}:
            return "arm64musl"
        if machine in {"x86_64", "amd64"}:
            return "x64musl"

    raise SystemExit(f"Unsupported native platform: {system} {machine}")


def all_targets_for_host() -> tuple[str, ...]:
    system = platform.system()
    if system == "Darwin":
        return ALL_TARGETS
    if system == "Linux":
        return tuple(target for target in ALL_TARGETS if target.endswith("musl"))
    raise SystemExit("--all requires a macOS or Linux host")


def musl_build_env(rust_target: str) -> dict[str, str]:
    env = os.environ.copy()
    zig_targets = {
        "x86_64-unknown-linux-musl": "x86_64-linux-musl",
        "aarch64-unknown-linux-musl": "aarch64-linux-musl",
    }
    zig_target = zig_targets.get(rust_target)
    if zig_target is None:
        return env
    if shutil.which("zig") is None:
        # Cargo then needs a musl cross compiler such as x86_64-linux-musl-gcc,
        # which most machines do not have; say so before the C build fails.
        print(f"  (zig was not found; {rust_target} needs a musl C cross compiler)")
        return env

    key = rust_target.replace("-", "_")
    env["ZIG_CC_TARGET"] = zig_target
    env[f"CC_{key}"] = str(ROOT / "scripts" / "zig_cc.py")
    env[f"AR_{key}"] = "zig ar"
    env[f"CFLAGS_{key}"] = "-Wno-error"
    print(f"  (using zig cc for {rust_target})")
    return env


def install_rust_target(rust_target: str, *, required: bool = False) -> None:
    run("rustup", "target", "add", rust_target, check=required)


def cargo_feature_args(features: tuple[str, ...]) -> list[str]:
    if not features:
        return []
    return ["--features", ",".join(features)]


def copy_unix_host(
    target_name: str,
    rust_target: str,
    *,
    native: bool,
    platform_root: Path = ROOT / "platform",
    features: tuple[str, ...] = (),
) -> None:
    output_dir = platform_root / "targets" / target_name
    output_dir.mkdir(parents=True, exist_ok=True)

    if native and target_name in {"x64mac", "arm64mac"}:
        run(
            "cargo",
            "build",
            "--locked",
            "--release",
            "--lib",
            *cargo_feature_args(features),
        )
        source = ROOT / "target" / "release" / "libhost.a"
    else:
        run(
            "cargo",
            "build",
            "--locked",
            "--release",
            "--lib",
            "--target",
            rust_target,
            *cargo_feature_args(features),
            env=musl_build_env(rust_target),
        )
        source = ROOT / "target" / rust_target / "release" / "libhost.a"

    destination = output_dir / "libhost.a"
    shutil.copy2(source, destination)
    print(f"  -> {display_path(destination)}")


def build_unix_target(
    target_name: str,
    *,
    native: bool = False,
    platform_root: Path = ROOT / "platform",
    features: tuple[str, ...] = (),
) -> None:
    rust_target = TARGETS[target_name]
    qualifier = "native" if native else rust_target
    print(f"Building for {target_name} ({qualifier})...")
    copy_unix_host(
        target_name,
        rust_target,
        native=native,
        platform_root=platform_root,
        features=features,
    )
    strip_linux_host(target_name, platform_root)


def find_windows_sdk_lib_dir() -> Path:
    program_files = os.environ.get("ProgramFiles(x86)")
    if not program_files:
        raise SystemExit("ProgramFiles(x86) is not set; cannot locate the Windows SDK")

    sdk_root = Path(program_files) / "Windows Kits" / "10" / "Lib"
    if not sdk_root.is_dir():
        raise SystemExit(f"Could not find Windows SDK library directory: {sdk_root}")
    candidates = sorted(
        (
            directory / "um" / "x64"
            for directory in sdk_root.iterdir()
            if directory.is_dir()
            and (directory / "um" / "x64" / "ws2_32.lib").is_file()
        ),
        reverse=True,
    )
    if not candidates:
        raise SystemExit(f"Could not find x64 Windows SDK libraries under {sdk_root}")
    return candidates[0]


def build_windows(
    *,
    platform_root: Path = ROOT / "platform",
    features: tuple[str, ...] = (),
) -> None:
    print(f"Building for x64win ({WINDOWS_TARGET})...")
    install_rust_target(WINDOWS_TARGET, required=True)
    run(
        "cargo",
        "build",
        "--locked",
        "--release",
        "--lib",
        "--target",
        WINDOWS_TARGET,
        *cargo_feature_args(features),
    )

    output_dir = platform_root / "targets" / "x64win"
    output_dir.mkdir(parents=True, exist_ok=True)
    host_destination = output_dir / "host.lib"
    shutil.copy2(
        ROOT / "target" / WINDOWS_TARGET / "release" / "host.lib",
        host_destination,
    )
    print(f"  -> {display_path(host_destination)}")

    sdk_lib_dir = find_windows_sdk_lib_dir()
    for name in WINDOWS_SYSTEM_LIBRARIES:
        source = sdk_lib_dir / name
        if not source.is_file():
            raise SystemExit(f"Could not find required Windows SDK library: {source}")
        destination = output_dir / name
        shutil.copy2(source, destination)
        print(f"  -> {display_path(destination)}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build the basic-webserver platform host"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="cross-compile every target buildable on this host OS",
    )
    parser.add_argument(
        "--target",
        choices=ROC_TARGETS,
        help="build host inputs for one Roc platform target",
    )
    parser.add_argument(
        "--features",
        default="",
        help="comma-separated Cargo features for a non-production host build",
    )
    parser.add_argument(
        "--output-platform",
        type=Path,
        help="copy the platform and place host outputs in this isolated directory",
    )
    args = parser.parse_args()

    features = tuple(filter(None, (item.strip() for item in args.features.split(","))))
    platform_root = (
        args.output_platform.resolve() if args.output_platform else ROOT / "platform"
    )
    if args.output_platform:
        if platform_root == (ROOT / "platform").resolve():
            parser.error("--output-platform must not resolve to the production platform directory")
        shutil.copytree(ROOT / "platform", platform_root, dirs_exist_ok=True)

    if args.all and args.target:
        parser.error("--all and --target are mutually exclusive")

    if args.target:
        if args.target == "x64win":
            if platform.system() != "Windows":
                parser.error("x64win host inputs must be built on Windows")
            build_windows(platform_root=platform_root, features=features)
        else:
            install_rust_target(TARGETS[args.target], required=True)
            build_unix_target(
                args.target,
                native=args.target == detect_native_target(),
                platform_root=platform_root,
                features=features,
            )
        print("\nBuild complete!")
        return

    if args.all:
        try:
            targets = all_targets_for_host()
        except SystemExit as error:
            parser.error(str(error))
        print(f"Building for targets supported by this host: {', '.join(targets)}\n")
        for target_name in targets:
            install_rust_target(TARGETS[target_name])
        print()
        for target_name in targets:
            build_unix_target(
                target_name, platform_root=platform_root, features=features
            )
            print()
        print("All targets built successfully!")
        return

    target_name = detect_native_target()
    print(f"Building for native target: {target_name}\n")
    if target_name == "x64win":
        build_windows(platform_root=platform_root, features=features)
    else:
        if target_name in {"x64musl", "arm64musl"}:
            install_rust_target(TARGETS[target_name])
        build_unix_target(
            target_name,
            native=True,
            platform_root=platform_root,
            features=features,
        )
    print("\nBuild complete!")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
