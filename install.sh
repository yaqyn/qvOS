#!/bin/bash
# shellcheck disable=SC1091

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Define the native source and installer roots.
export QVOS_PATH="${QVOS_PATH:-$HOME/.local/share/qvos}"
export QVOS_INSTALL="$QVOS_PATH/qvcore/install"
export QVOS_INSTALL_LOG_FILE="${QVOS_INSTALL_LOG_FILE:-/var/log/qvos-install.log}"
export PATH="$QVOS_PATH/bin:$PATH"

# Install
source "$QVOS_PATH/qvcore/install/helpers/run"
source "$QVOS_INSTALL/preflight/all.sh"
source "$QVOS_INSTALL/packaging/all.sh"
source "$QVOS_PATH/qvcore/install/config/run"
source "$QVOS_PATH/qvcore/boot/install"
source "$QVOS_PATH/qvcore/install/post-install/run"
