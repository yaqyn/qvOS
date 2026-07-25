# shellcheck shell=bash

# Install qvOS-owned desktop helpers.
mkdir -p "$HOME/.local/share/qvos"

# Remove payloads from retired standalone qvOS installers and desktop apps.
rm -rf -- \
  "$HOME/.local/share/qvos/domains" \
  "$HOME/.local/share/qvos/source" \
  "$HOME/.local/share/qvos/tui"
rm -f -- \
  "$HOME/.local/share/qvos/README.md" \
  "$HOME/.local/share/qvos/VERSION" \
  "$HOME/.local/share/qvos/bin/omarchy-qvos-doctor" \
  "$HOME/.local/share/qvos/bin/omarchy-qvos-reconcile" \
  "$HOME/.local/share/qvos/bin/omarchy-qvos-update" \
  "$HOME/.local/share/qvos/bin/qvos-show-logo" \
  "$HOME/.local/share/qvos/home-dev" \
  "$HOME/.local/share/qvos/defaults/qvos-launch-thunar"

if [[ -d $OMARCHY_PATH/qv/scripts ]]; then
  # Replace binding helpers so removed commands cannot survive an update.
  rm -rf -- "$HOME/.local/share/qvos/hyprland"
  find "$OMARCHY_PATH/qv/scripts" -mindepth 1 -maxdepth 1 ! -name "screensaver" ! -name "tui" -exec cp -a {} "$HOME/.local/share/qvos/" \;
fi

thunar_source="$OMARCHY_PATH/qv/thunar"
if [[ -d $thunar_source ]]; then
  rm -rf -- "$HOME/.local/share/qvos/thunar"
  cp -a "$thunar_source" "$HOME/.local/share/qvos/thunar"
fi

screensaver_source="$OMARCHY_PATH/qv/scripts/screensaver"
if [[ -d $screensaver_source ]]; then
  qvos_bin="$HOME/.local/share/qvos/bin"
  qvos_screensaver="$HOME/.local/share/qvos/screensaver"
  local_bin="$HOME/.local/bin"

  rm -rf -- "$qvos_screensaver"
  install -d "$qvos_bin" "$qvos_screensaver" "$local_bin"
  install -m 0644 "$screensaver_source/alacritty.toml" "$qvos_screensaver/alacritty.toml"
  for command_name in omarchy-launch-screensaver qvos-launch-screensaver qvos-screensaver; do
    install -m 0755 "$screensaver_source/$command_name" "$qvos_bin/$command_name"
    ln -sfn "$qvos_bin/$command_name" "$local_bin/$command_name"
  done
fi
