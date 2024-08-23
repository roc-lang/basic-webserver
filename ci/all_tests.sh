#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail


if [ -z "${ROC}" ]; then
  echo "ERROR: The ROC environment variable is not set.
    Set it to something like:
        /home/username/Downloads/roc_nightly-linux_x86_64-2023-10-30-cb00cfb/roc
        or
        /home/username/gitrepos/roc/target/build/release/roc
        or
        roc" >&2

  exit 1
fi


if [ -z "${EXAMPLES_DIR}" ]; then
  echo "ERROR: The EXAMPLES_DIR environment variable is not set." >&2

  exit 1
fi

echo "build the platform"
$ROC ./build.roc --prebuilt-platform -- --roc $ROC

echo "roc check"
for roc_file in $EXAMPLES_DIR*.roc; do
    $ROC check $roc_file
done

# roc build
architecture=$(uname -m)

for roc_file in $EXAMPLES_DIR*.roc; do
    # --linker=legacy as workaround for https://github.com/roc-lang/roc/issues/3609
    $ROC build --prebuilt-platform --linker=legacy $roc_file
done

# `roc test` every roc file if it contains a test, skip roc_nightly folder
find . -type d -name "roc_nightly" -prune -o -type f -name "*.roc" -print | while read file; do
    if grep -qE '^\s*expect(\s+|$)' "$file"; then

        # don't exit script if test_command fails
        set +e
        test_command=$($ROC test --prebuilt-platform --linker=legacy "$file")
        test_exit_code=$?
        set -e

        if [[ $test_exit_code -ne 0 && $test_exit_code -ne 2 ]]; then
            exit $test_exit_code
        fi
    fi
done

for script in ci/expect_scripts/*.exp; do
    expect "$script"
done

# test building website
$ROC docs platform/main.roc
