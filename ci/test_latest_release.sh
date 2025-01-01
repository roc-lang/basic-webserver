#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

if [ -z "${EXAMPLES_DIR}" ]; then
  echo "ERROR: The EXAMPLES_DIR environment variable is not set." >&2
  exit 1
fi

# Install jq if it's not already available
if [[ "$OSTYPE" == "darwin"* ]]; then
    command -v jq &>/dev/null || brew install jq
else
    command -v jq &>/dev/null || sudo apt install -y jq
fi

# Get the latest roc nightly
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ $(uname -m) == "arm64" ]]; then
        os_arch="macos_apple_silicon"
    else
        os_arch="macos_x86_64"
    fi
else
    os_arch="linux_x86_64"
fi

curl -fOL "https://github.com/roc-lang/roc/releases/download/nightly/roc_nightly-${os_arch}-latest.tar.gz"

# Rename nightly tar
TAR_NAME=$(ls | grep "roc_nightly.*tar\.gz")
mv "$TAR_NAME" roc_nightly.tar.gz

# Decompress the tar
tar -xzf roc_nightly.tar.gz

# Remove the tar file
rm roc_nightly.tar.gz

# Simplify nightly folder name
NIGHTLY_FOLDER=$(ls -d roc_nightly*/)
mv "$NIGHTLY_FOLDER" roc_nightly

# Print the roc version
./roc_nightly/roc version

# Get the latest basic-webserver release file URL
WS_RELEASES_JSON=$(curl -s https://api.github.com/repos/roc-lang/basic-webserver/releases)
WS_RELEASE_URL=$(echo $WS_RELEASES_JSON | jq -r '.[0].assets | .[] | select(.name | test("\\.tar\\.br$")) | .browser_download_url')

# Use the latest basic-webserver release as the platform for every example
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|../platform/main.roc|$WS_RELEASE_URL|g" $EXAMPLES_DIR/*.roc
else
    sed -i "s|../platform/main.roc|$WS_RELEASE_URL|g" $EXAMPLES_DIR/*.roc
fi

# Install required packages for tests if they're not already available
if [[ "$OSTYPE" == "darwin"* ]]; then
    command -v ncat &>/dev/null || brew install ncat
    command -v expect &>/dev/null || brew install expect
else
    command -v ncat &>/dev/null || sudo apt install -y ncat
    command -v expect &>/dev/null || sudo apt install -y expect
fi

ROC=./roc_nightly/roc ./ci/all_tests.sh