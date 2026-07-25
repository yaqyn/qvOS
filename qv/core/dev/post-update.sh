#!/bin/bash
set -u

state_file="$HOME/.local/state/qvos/qvcore/dev"
omarchy_path=${OMARCHY_PATH:-$HOME/.local/share/omarchy}
dev_script="$omarchy_path/qv/core/dev.sh"

[[ -f $state_file ]] || exit 0
[[ -x $dev_script ]] || exit 0
"$dev_script" --update
