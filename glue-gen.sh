#!/usr/bin/env bash

## This script is used to re-generate the glue files for the platform,
## specifically roc_app and roc_std.

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# Remove old glue flies
rm -rf crates/roc_app
rm -rf crates/roc_std

# Generate manual glue - NOTE this is a workaround until glue generates for all types
roc glue ../roc/crates/glue/src/RustGlue.roc crates/ platform/main-glue.roc
