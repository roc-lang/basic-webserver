#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

roc='./roc_nightly/roc'

examples_dir='./examples/'

# roc check
for roc_file in $examples_dir*.roc; do
    $roc check $roc_file
done

# roc build
architecture=$(uname -m)

for roc_file in $examples_dir*.roc; do
    # --linker=legacy as workaround for https://github.com/roc-lang/roc/issues/3609
    $roc build $roc_file --linker=legacy
done

$roc test platform/Url.roc

# test building website
$roc docs platform/main.roc
