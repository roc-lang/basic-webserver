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

TESTS_DIR="${EXAMPLES_DIR/\/examples\//\/tests\/}"
export TESTS_DIR



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

echo "roc check + matching .exp file"
for roc_file in $TESTS_DIR*.roc; do
    $ROC check $roc_file
done
for roc_file in $EXAMPLES_DIR*.roc; do
    $ROC check $roc_file

    ## Check if every example has matching expect script

    # Extract the base filename without extension
    base_name=$(basename "$roc_file" .roc)
    
    if [ ! -f "ci/expect_scripts/${base_name}.exp" ]; then
        echo "ERROR: No matching expect script found for $base_name" >&2
        exit 1
    fi
done

# roc build
architecture=$(uname -m)

for roc_file in $TESTS_DIR*.roc; do
    # --linker=legacy as workaround for https://github.com/roc-lang/roc/issues/3609
    $ROC build --linker=legacy $roc_file
done
for roc_file in $EXAMPLES_DIR*.roc; do
    # --linker=legacy as workaround for https://github.com/roc-lang/roc/issues/3609
    $ROC build --linker=legacy $roc_file
done

# `roc test` every roc file if it contains a test, but skip roc_nightly folder
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
    expect "$script"
done

# test building website
$ROC docs platform/main.roc
