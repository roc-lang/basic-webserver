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
    $roc build $roc_file
done

# test building website
$roc docs platform/main.roc
