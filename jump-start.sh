#!/usr/bin/env bash

## This script is only needed in the event of a breaking change in the
## Roc compiler that prevents build.roc from running.
## This script builds a local prebuilt binary for the native target,
## so that the build.roc script can be run.
##
## To use this, change the build.roc script to use the platform locally..

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -exo pipefail

if [ -z "${ROC}" ]; then
  echo "Warning: ROC environment variable is not set... I'll try with just 'roc'."

  ROC="roc"
fi

# if [ -z "${USE_LOCAL_CLI}" ]; then
#     # need to get basic-cli modified for builtin Task
#     pushd . # save current dir
#     cd ..
#     git clone https://github.com/smores56/basic-cli.git
#     cd basic-cli
#     git checkout builtin-task
#     popd # back to original dir
# else
#     # we are using a local version therefore no need to clone
#     # the basic-cli repo
#     echo "using local path for basic-cli"
# fi

$ROC build --lib ./platform/libapp.roc

# NOTE GLUE NEEDS TO BE MANUALLY UPDATED, IT GENERATES BROKEN RUST
# SO WE DO NOT INCLUDE THE BELOW STEP
# $ROC glue ./platform/main-glue.roc crates ./platform/main.roc

cargo build --release

if [ -n "$CARGO_BUILD_TARGET" ]; then
    cp target/$CARGO_BUILD_TARGET/release/libhost.a ./platform/libhost.a
else
    cp target/release/libhost.a ./platform/libhost.a
fi
