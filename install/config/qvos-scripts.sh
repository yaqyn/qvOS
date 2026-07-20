# shellcheck shell=bash

# Install qvOS-owned desktop helpers.
mkdir -p "$HOME/.local/share/qvos"

# Keep the custom TUI as ISO/build tooling instead of installing a second
# desktop control surface. qvPLAY owns its own development wiring.
rm -rf -- "$HOME/.local/share/qvos/tui"
rm -f -- "$HOME/.local/share/qvos/home-dev"

if [[ -d $OMARCHY_PATH/qv/scripts ]]; then
  # Replace binding helpers so removed commands cannot survive an update.
  rm -rf -- "$HOME/.local/share/qvos/hyprland"
  find "$OMARCHY_PATH/qv/scripts" -mindepth 1 -maxdepth 1 ! -name "screensaver" ! -name "tui" -exec cp -a {} "$HOME/.local/share/qvos/" \;
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
