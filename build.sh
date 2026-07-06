#!/bin/bash
set -eo pipefail

# Build script for the basic-webserver platform host.
# Usage:
#   ./build.sh                  - Build libhost for the native target only
#   ./build.sh --target TARGET  - Build libhost for a specific target
#   ./build.sh --all            - Build every target this host can build
#
# The compiler does the final per-target link using the inputs committed under
# platform/targets/<target>/ (see the `targets:` block in platform/main.roc).
# This script only rebuilds the host static lib (libhost.a / host.lib).

# Get rust triple for a target name
get_rust_triple() {
    case "$1" in
        x64mac)    echo "x86_64-apple-darwin" ;;
        arm64mac)  echo "aarch64-apple-darwin" ;;
        x64musl)   echo "x86_64-unknown-linux-musl" ;;
        arm64musl) echo "aarch64-unknown-linux-musl" ;;
        x64win)    echo "x86_64-pc-windows-msvc" ;;
        arm64win)  echo "aarch64-pc-windows-msvc" ;;
        *) echo "Unknown target: $1" >&2; exit 1 ;;
    esac
}

# Host static lib filename per target (Windows uses host.lib)
get_lib_name() {
    case "$1" in
        *win) echo "host.lib" ;;
        *)    echo "libhost.a" ;;
    esac
}

get_zig_target() {
    case "$1" in
        x64mac)    echo "x86_64-macos" ;;
        arm64mac)  echo "aarch64-macos" ;;
        x64musl)   echo "x86_64-linux-musl" ;;
        arm64musl) echo "aarch64-linux-musl" ;;
        *) echo "Unknown Zig target for: $1" >&2; exit 1 ;;
    esac
}

get_zig_cflags() {
    local target_name=$1

    case "$target_name" in
        *mac) echo "-O3 -DNDEBUG -fPIC -ffunction-sections -fdata-sections -fno-sanitize=all -mmacosx-version-min=11.0" ;;
        *)    echo "-O3 -DNDEBUG -fPIC -ffunction-sections -fdata-sections -fno-sanitize=all" ;;
    esac
}

detect_host_os() {
    local os=$(uname -s)

    case "$os" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

should_use_zig_c_toolchain() {
    local target_name=$1
    local native_target=$2

    command -v zig >/dev/null 2>&1 || return 1
    [[ "$target_name" == *"win"* ]] && return 1
    [[ "$target_name" == *"musl"* ]] && return 0
    [[ -n "$native_target" && "$target_name" != "$native_target" ]] && return 0

    return 1
}

cargo_build_release_lib_for_target() {
    local target_name=$1
    local rust_triple=$2
    local native_target=${3:-}
    local host_os=$(detect_host_os)

    if [[ "$target_name" == *"win"* && "$host_os" != "windows" ]]; then
        echo "Windows MSVC targets require a Windows host." >&2
        echo "Run this on a Windows runner or build a non-Windows target here." >&2
        exit 1
    fi

    if should_use_zig_c_toolchain "$target_name" "$native_target"; then
        local env_key=${rust_triple//-/_}
        local zig_target=$(get_zig_target "$target_name")
        local zig_cflags=$(get_zig_cflags "$target_name")

        echo "Using Zig C toolchain for $rust_triple C dependencies..."
        if [[ "$target_name" == *"mac"* ]]; then
            env \
                MACOSX_DEPLOYMENT_TARGET=11.0 \
                CRATE_CC_NO_DEFAULTS=1 \
                "CC_${env_key}=zig cc -target ${zig_target}" \
                "AR_${env_key}=zig ar" \
                "CFLAGS_${env_key}=${zig_cflags}" \
                cargo build --release --lib --target "$rust_triple"
        else
            env \
                CRATE_CC_NO_DEFAULTS=1 \
                "CC_${env_key}=zig cc -target ${zig_target}" \
                "AR_${env_key}=zig ar" \
                "CFLAGS_${env_key}=${zig_cflags}" \
                cargo build --release --lib --target "$rust_triple"
        fi
    else
        cargo build --release --lib --target "$rust_triple"
    fi
}

get_targets_for_host() {
    case "$(detect_host_os)" in
        linux)   echo "x64mac arm64mac x64musl arm64musl" ;;
        macos)   echo "x64mac arm64mac" ;;
        windows) echo "x64win arm64win" ;;
        *) echo "Unsupported host OS" >&2; exit 1 ;;
    esac
}

# Detect native target based on current platform
detect_native_target() {
    local arch=$(uname -m)
    local os=$(detect_host_os)

    if [ "$os" = "macos" ]; then
        if [[ "$arch" == "arm64" || "$arch" == "aarch64" ]]; then
            echo "arm64mac"
        else
            echo "x64mac"
        fi
    elif [ "$os" = "linux" ]; then
        if [[ "$arch" == "arm64" || "$arch" == "aarch64" ]]; then
            echo "arm64musl"
        else
            echo "x64musl"
        fi
    elif [ "$os" = "windows" ]; then
        if [[ "$arch" == "arm64" || "$arch" == "aarch64" ]]; then
            echo "arm64win"
        else
            echo "x64win"
        fi
    else
        echo "Unsupported OS: $os" >&2
        exit 1
    fi
}

# Build for a specific target (cross-compile)
build_target_cross() {
    local target_name=$1
    local rust_triple=$(get_rust_triple "$target_name")
    local lib_name=$(get_lib_name "$target_name")

    echo "Building for $target_name ($rust_triple)..."
    rustup target add "$rust_triple" 2>/dev/null || true
    cargo_build_release_lib_for_target "$target_name" "$rust_triple" "$(detect_native_target)"

    mkdir -p "platform/targets/$target_name"
    cp "target/$rust_triple/release/$lib_name" "platform/targets/$target_name/"
    echo "  -> platform/targets/$target_name/$lib_name"
}

# Build for native target
# On macOS: no --target needed (native is fine)
# On Linux: must use --target for musl, since default is glibc
build_target_native() {
    local target_name=$1
    local rust_triple=$(get_rust_triple "$target_name")
    local lib_name=$(get_lib_name "$target_name")

    echo "Building for $target_name (native)..."

    if [[ "$target_name" == *"musl"* ]]; then
        # Linux: need explicit musl target (default is glibc)
        rustup target add "$rust_triple" 2>/dev/null || true
        cargo_build_release_lib_for_target "$target_name" "$rust_triple" "$target_name"
        mkdir -p "platform/targets/$target_name"
        cp "target/$rust_triple/release/$lib_name" "platform/targets/$target_name/"
    elif [[ "$target_name" == *"mac"* || "$target_name" == *"win"* ]]; then
        cargo build --release --lib
        mkdir -p "platform/targets/$target_name"
        cp "target/release/$lib_name" "platform/targets/$target_name/"
    else
        echo "Unsupported native target: $target_name" >&2
        exit 1
    fi

    echo "  -> platform/targets/$target_name/$lib_name"
}

usage() {
    echo "Usage:"
    echo "  ./build.sh"
    echo "  ./build.sh --target TARGET"
    echo "  ./build.sh --all"
}

# Main logic
if [ "${1:-}" = "--all" ]; then
    BUILD_TARGETS=$(get_targets_for_host)
    echo "Building for host-supported targets: $BUILD_TARGETS"
    echo ""

    echo "Installing Rust targets..."
    for target_name in $BUILD_TARGETS; do
        rust_triple=$(get_rust_triple "$target_name")
        rustup target add "$rust_triple" 2>/dev/null || true
    done
    echo ""

    for target_name in $BUILD_TARGETS; do
        build_target_cross "$target_name"
        echo ""
    done

    echo "Host-supported targets built successfully!"
elif [ "${1:-}" = "--target" ]; then
    if [ -z "${2:-}" ]; then
        usage >&2
        exit 1
    fi

    build_target_cross "$2"
elif [ -n "${1:-}" ]; then
    usage >&2
    exit 1
else
    TARGET=$(detect_native_target)
    echo "Building for native target: $TARGET"
    echo ""

    build_target_native "$TARGET"

    echo ""
    echo "Build complete!"
fi
