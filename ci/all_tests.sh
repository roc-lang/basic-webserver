#!/usr/bin/env bash
set -euo pipefail

# Test driver for the basic-webserver platform on the new Zig-based Roc compiler.
#
# Assumes:
#   - `roc` is on PATH (new compiler).
#   - The host static lib has been built into platform/targets/<native>/ (run
#     ./build.sh first).
#
# It `roc check`s, `roc test`s, and `roc build`s every active example and test
# (files ending in `.roc`; deferred modules/examples use the `.todoroc`
# extension and are skipped), then smoke-tests the hello-web server.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROC="${ROC:-roc}"
EXE_SUFFIX=""
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) EXE_SUFFIX=".exe" ;;
esac

echo "Using roc: $($ROC version 2>&1 | head -1)"
echo ""

check_no_deferred_roc() {
    local files
    files="$(find examples tests platform -name '*.todoroc' -print)"
    if [ -n "$files" ]; then
        echo "Deferred Roc files found; rename or remove them before release:" >&2
        echo "$files" >&2
        exit 1
    fi
}

check_test_and_build() {
    local file=$1
    echo "==> roc check $file"
    "$ROC" check "$file"
    echo "==> roc test $file"
    "$ROC" test "$file"
    echo "==> roc build $file"
    "$ROC" build "$file"
}

check_readme_example() {
    local dir="target/readme-example"
    local file="$dir/readme.roc"
    local output="$dir/readme-example${EXE_SUFFIX}"

    mkdir -p "$dir"
    awk '
        BEGIN { in_block = 0; seen = 0 }
        /^```roc$/ && seen == 0 { in_block = 1; seen = 1; next }
        /^```$/ && in_block == 1 { in_block = 0; exit }
        in_block == 1 {
            if ($0 ~ /^[[:space:]]*pf: platform "https:\/\/github.com\/roc-lang\/basic-webserver\/releases\/download\//) {
                print "    pf: platform \"../../platform/main.roc\","
            } else {
                print
            }
        }
    ' README.md > "$file"

    if [ ! -s "$file" ]; then
        echo "README example check FAILED: no roc code block found" >&2
        exit 1
    fi

    echo "==> roc check README example"
    "$ROC" check "$file"
    echo "==> roc test README example"
    "$ROC" test "$file"
    echo "==> roc build README example"
    "$ROC" build --output="$output" "$file"
    rm -f "$output" "$output.exe"
}

check_no_deferred_roc

# Build all active examples and tests.
for file in examples/*.roc tests/*.roc; do
    [ -e "$file" ] || continue
    check_test_and_build "$file"
done

check_readme_example

# Roc drops built binaries in the repo root; clean them up.
for file in examples/*.roc tests/*.roc; do
    [ -e "$file" ] || continue
    name="$(basename "${file%.roc}")"
    rm -f "$name" "$name.exe"
done

echo ""
echo "=== Smoke test: hello-web ==="
"$ROC" build examples/hello-web.roc
PORT="${SMOKE_PORT:-8080}"
ROC_BASIC_WEBSERVER_PORT="$PORT" "./hello-web${EXE_SUFFIX}" &
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; rm -f ./hello-web ./hello-web.exe; }
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
