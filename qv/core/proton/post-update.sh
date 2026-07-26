#!/bin/bash
set -euo pipefail

state_file="$HOME/.local/state/qvos/qvcore/proton"
[[ -f $state_file ]] || exit 0

OMARCHY_PATH=${OMARCHY_PATH:-$HOME/.local/share/omarchy}
component="$OMARCHY_PATH/qv/core/proton.sh"
[[ -x $component ]] || exit 0
grep -Fqx '# qvcore:lifecycle=1' "$component" || exit 0
"$component" --repair
