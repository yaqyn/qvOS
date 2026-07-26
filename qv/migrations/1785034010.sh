# shellcheck source=qv/install/desktop
source "$OMARCHY_PATH/qv/install/desktop" || return
"$OMARCHY_PATH/qv/config/refresh" hypr/hypridle.conf
omarchy-restart-hypridle
