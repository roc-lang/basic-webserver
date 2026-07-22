#!/usr/bin/env bash
set -euo pipefail

# cc-rs may append a Rust target triple, which Zig does not understand (for
# example, `x86_64-unknown-linux-musl`). The build script already supplies the
# corresponding Zig triple through ZIG_CC_TARGET.
zig_args=()
for arg in "$@"; do
    case "$arg" in
        --target=*) ;;
        *) zig_args+=("$arg") ;;
    esac
done

exec zig cc -target "$ZIG_CC_TARGET" "${zig_args[@]}"
