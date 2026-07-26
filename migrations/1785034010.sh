echo "Enable guarded automatic suspend and repair idle screensaver behavior"

source "$OMARCHY_PATH/install/config/qvos-scripts.sh" || return
omarchy-refresh-hypridle
