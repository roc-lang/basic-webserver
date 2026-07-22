#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
    python_command=python3
else
    python_command=python
fi
exec "$python_command" "$ROOT_DIR/scripts/build.py" "$@"
