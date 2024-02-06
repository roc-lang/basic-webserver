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

examples_dir='./examples/'

# roc check
for roc_file in $examples_dir*.roc; do
    $ROC check $roc_file
done

# roc build
architecture=$(uname -m)

for roc_file in $examples_dir*.roc; do
    # --linker=legacy as workaround for https://github.com/roc-lang/roc/issues/3609
    $ROC build $roc_file --linker=legacy
done

$ROC test platform/Url.roc

$ROC test platform/InternalDateTime.roc

# test building website
$ROC docs platform/main.roc
