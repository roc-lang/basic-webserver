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
RUN_EXPECT_TESTS="${RUN_EXPECT_TESTS:-1}"
IS_MUSL="${IS_MUSL:-0}"
EXE_SUFFIX=""
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) EXE_SUFFIX=".exe" ;;
esac

EXPECT_ROOT="$ROOT_DIR/target/expect"
EXPECT_EXAMPLES_DIR="$EXPECT_ROOT/examples"
EXPECT_TESTS_DIR="$EXPECT_ROOT/tests"
EXPECT_BIN_DIR="$EXPECT_ROOT/bin"
EXPECT_SHIM_ROOT="$EXPECT_ROOT/shims"
CREATED_BASIC_CLI_SHIM=0

cleanup_expect_shims() {
    if [ "$CREATED_BASIC_CLI_SHIM" = "1" ]; then
        rm -f "$ROOT_DIR/basic-cli"
    fi
    rm -f "$ROOT_DIR/curl_file_output.txt" "$ROOT_DIR/curl_form_output.txt"
}

trap cleanup_expect_shims EXIT

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
    local name output_dir output
    name="$(basename "${file%.roc}")"
    case "$file" in
        examples/*) output_dir="$EXPECT_EXAMPLES_DIR" ;;
        tests/*) output_dir="$EXPECT_TESTS_DIR" ;;
        *) output_dir="$EXPECT_ROOT/bin" ;;
    esac
    output="$output_dir/$name$EXE_SUFFIX"

    echo "==> roc check $file"
    "$ROC" check "$file"
    echo "==> roc test $file"
    "$ROC" test "$file"
    echo "==> roc build $file"
    mkdir -p "$output_dir"
    "$ROC" build --output="$output" "$file"
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

prepare_expect_dirs() {
    rm -rf "$EXPECT_ROOT"
    mkdir -p "$EXPECT_EXAMPLES_DIR" "$EXPECT_TESTS_DIR" "$EXPECT_BIN_DIR" "$EXPECT_SHIM_ROOT"

    find examples -maxdepth 1 -type f ! -name '*.roc' ! -name '*.todoroc' -exec cp {} "$EXPECT_EXAMPLES_DIR/" \;
    find tests -maxdepth 1 -type f ! -name '*.roc' ! -name '*.todoroc' -exec cp {} "$EXPECT_TESTS_DIR/" \;
}

write_ncat_shim_if_needed() {
    if command -v ncat >/dev/null 2>&1; then
        return
    fi

    command -v python3 >/dev/null 2>&1 || {
        echo "expect tests require ncat or python3 for the TCP echo-server shim" >&2
        exit 1
    }

    cat > "$EXPECT_BIN_DIR/ncat" <<'PY'
#!/usr/bin/env python3
import socket
import sys

port = 8085
args = sys.argv[1:]
if "-l" in args:
    index = args.index("-l")
    if index + 1 < len(args):
        port = int(args[index + 1])

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(1)
    conn, _ = server.accept()
    with conn:
        while True:
            data = conn.recv(4096)
            if not data:
                break
            conn.sendall(data)
PY
    chmod +x "$EXPECT_BIN_DIR/ncat"
    export PATH="$EXPECT_BIN_DIR:$PATH"
}

prepare_http_test_server() {
    if [ -e "$ROOT_DIR/basic-cli" ]; then
        return
    fi

    command -v python3 >/dev/null 2>&1 || {
        echo "expect tests require python3 for the outbound HTTP test server shim" >&2
        exit 1
    }

    local server_dir="$EXPECT_SHIM_ROOT/basic-cli/ci/rust_http_server/target/release"
    mkdir -p "$server_dir"
    cat > "$server_dir/rust_http_server" <<'PY'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/utf8test":
            body = b"Hello utf8"
            content_type = "text/plain"
        elif self.path == "/":
            body = b'{"foo":"Hello Json!"}'
            content_type = "application/json"
        else:
            body = b"<html>\n</html>\n"
            content_type = "text/html"

        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


HTTPServer(("127.0.0.1", 9000), Handler).serve_forever()
PY
    chmod +x "$server_dir/rust_http_server"
    ln -s "$EXPECT_SHIM_ROOT/basic-cli" "$ROOT_DIR/basic-cli"
    CREATED_BASIC_CLI_SHIM=1
}

run_expect_scripts() {
    case "$RUN_EXPECT_TESTS" in
        0|false|False|FALSE|no|No|NO)
            echo "==> skipping expect e2e tests (RUN_EXPECT_TESTS=$RUN_EXPECT_TESTS)"
            return
            ;;
    esac

    command -v expect >/dev/null 2>&1 || {
        echo "expect e2e tests require the 'expect' command" >&2
        exit 1
    }
    command -v curl >/dev/null 2>&1 || {
        echo "expect e2e tests require the 'curl' command" >&2
        exit 1
    }

    write_ncat_shim_if_needed
    prepare_http_test_server

    export EXAMPLES_DIR="$EXPECT_EXAMPLES_DIR/"
    export TESTS_DIR="$EXPECT_TESTS_DIR/"

    for script in ci/expect_scripts/*.exp; do
        if [ "$IS_MUSL" = "1" ] && grep -q "file-accessed-modified-created" "$script"; then
            continue
        fi
        echo "==> expect $script"
        expect "$script"
    done
}

check_no_deferred_roc
prepare_expect_dirs

# Build all active examples and tests.
for file in examples/*.roc tests/*.roc; do
    [ -e "$file" ] || continue
    check_test_and_build "$file"
done

check_readme_example
run_expect_scripts

echo ""
echo "=== Smoke test: hello-web ==="
"$ROC" build examples/hello-web.roc
PORT="${SMOKE_PORT:-8080}"
ROC_BASIC_WEBSERVER_PORT="$PORT" "./hello-web${EXE_SUFFIX}" &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
    rm -f ./hello-web ./hello-web.exe
    cleanup_expect_shims
}
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
