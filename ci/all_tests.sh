#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -exo pipefail


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

if [ "$NO_BUILD" != "1" ]; then
    if [ "$JUMP_START" == "1" ]; then
    echo "building platform..."

    # we can't use a release of basic-cli because we are making a breaking change
    # let's build the platform using bash instead
    bash jump-start.sh

    else
        # run build script for the platform which uses basic-cli
        $ROC ./build.roc -- --roc $ROC
    fi
fi

echo "roc check"
for roc_file in $EXAMPLES_DIR*.roc; do
    $ROC check $roc_file
done

# roc build
architecture=$(uname -m)

for roc_file in $EXAMPLES_DIR*.roc; do
    # --linker=legacy as workaround for https://github.com/roc-lang/roc/issues/3609
    $ROC build --linker=legacy $roc_file
done

# `roc test` every roc file if it contains a test, skip roc_nightly folder
find . -type d -name "roc_nightly" -prune -o -type f -name "*.roc" -print | while read file; do
    if grep -qE '^\s*expect(\s+|$)' "$file"; then

        # don't exit script if test_command fails
        set +e
        test_command=$($ROC test --linker=legacy "$file")
        test_exit_code=$?
        set -e

        if [[ $test_exit_code -ne 0 && $test_exit_code -ne 2 ]]; then
            exit $test_exit_code
        fi
    fi
done

for script in ci/expect_scripts/*.exp; do

    # skip file-upload-form.exp
    # + expect ci/expect_scripts/file-upload-form.exp
    # spawn examples/file-upload-form
    # Listening on <http://127.0.0.1:8000>
    # WARNING: The convert command is deprecated in IMv7, use "magick" instead of "convert" or "magick convert"

    #     while executing
    # "exec convert -size 100x100 xc:red red_test_image.png"
    #     invoked from within
    # "expect "Listening on <http://127.0.0.1:8000>\r\n" {

    #     exec convert -size 100x100 xc:red red_test_image.png

    #     set script_dir [file dirname [info ..."
    #     (file "ci/expect_scripts/file-upload-form.exp" line 10)
    if [ $script == "ci/expect_scripts/file-upload-form.exp" ]; then
        continue
    fi

    expect "$script"
done

# test building website
$ROC docs platform/main.roc
