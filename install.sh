#!/bin/bash
# shellcheck disable=SC1091

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Define the native source root and inherited compatibility environment.
export QVOS_PATH="${QVOS_PATH:-${OMARCHY_PATH:-$HOME/.local/share/qvos}}"
export OMARCHY_PATH="$QVOS_PATH"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
export PATH="$OMARCHY_PATH/bin:$PATH"

# Install
source "$OMARCHY_PATH/qvcore/install/helpers/run"
source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_PATH/qvcore/install/config/run"
source "$OMARCHY_PATH/qvcore/boot/install"
source "$OMARCHY_PATH/qvcore/install/post-install/run"
