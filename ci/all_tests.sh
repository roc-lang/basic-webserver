#!/usr/bin/env bash
set -euo pipefail

# Test driver for the basic-webserver platform on the new Zig-based Roc compiler.
#
# Assumes:
#   - `roc` is on PATH (new compiler).
#   - The host static lib has been built into platform/targets/<native>/ (run
#     ./build.sh first).
#
# It `roc check`s and `roc build`s every active example and test (files ending in
# `.roc`; deferred modules/examples use the `.todoroc` extension and are skipped),
# then smoke-tests the hello-web server.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROC="${ROC:-roc}"

echo "Using roc: $($ROC version 2>&1 | head -1)"
echo ""

check_and_build() {
    local file=$1
    echo "==> roc check $file"
    "$ROC" check "$file"
    echo "==> roc build $file"
    "$ROC" build "$file"
}

# Build all active examples and tests.
for file in examples/*.roc tests/*.roc; do
    [ -e "$file" ] || continue
    check_and_build "$file"
done

# Roc drops built binaries in the repo root; clean them up.
for file in examples/*.roc tests/*.roc; do
    [ -e "$file" ] || continue
    name="$(basename "${file%.roc}")"
    rm -f "$name"
done

echo ""
echo "=== Smoke test: hello-web ==="
"$ROC" build examples/hello-web.roc
PORT="${SMOKE_PORT:-8080}"
ROC_BASIC_WEBSERVER_PORT="$PORT" ./hello-web &
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; rm -f ./hello-web; }
trap cleanup EXIT

# Wait for the server to come up.
for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

status="$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}/")"
echo "GET / -> HTTP $status"
if [ "$status" != "200" ]; then
    echo "Smoke test FAILED: expected HTTP 200" >&2
    exit 1
fi

echo ""
echo "All checks passed."
