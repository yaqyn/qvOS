echo "Converge long-running desktop processes to qvOS units"

QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}

if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -n ${XDG_RUNTIME_DIR:-} ]]; then
  "$QVOS_PATH/qvcore/desktop/restart/monitor-watch"
  if pgrep -x waybar >/dev/null; then
    "$QVOS_PATH/qvcore/desktop/restart/waybar"
  fi
  "$QVOS_PATH/qvcore/theme/background-restore"
fi
