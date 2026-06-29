#!/usr/bin/env bash
set -euo pipefail

ROC_SRC="${ROC_SRC:-/home/lbw/Documents/Github/roc}"

echo "==> roc check repro_app/main.roc"
roc check repro_app/main.roc

mkdir -p out

echo
echo "==> roc glue ${ROC_SRC}/src/glue/src/RustGlue.roc out platform/main.roc"
roc glue "${ROC_SRC}/src/glue/src/RustGlue.roc" out platform/main.roc
