# shellcheck shell=bash

# Install qvOS-owned desktop helpers.
mkdir -p "$HOME/.local/share/qvos"

for feature in desktop screensaver thunar tmux waybar; do
  feature_source="$OMARCHY_PATH/qv/$feature"
  if [[ ! -d $feature_source ]]; then
    echo "Missing qvOS desktop feature source: $feature_source" >&2
    return 1
  fi
done

required_sources=(
  bin/omarchy-system-inhibit-sleep
  bin/omarchy-system-suspend-if-safe
  qv/desktop/context/qvos-active-location
  qv/desktop/context/qvos-launch-editor-here
  qv/desktop/context/qvos-launch-terminal-here
  qv/desktop/hyprland/qvos-toggle-special-window
  qv/desktop/web/qvos-localhost-open
  qv/desktop/web/qvos-website-open
  qv/screensaver/alacritty.toml
  qv/screensaver/omarchy-launch-screensaver
  qv/screensaver/qvos-launch-screensaver
  qv/screensaver/qvos-screensaver
  qv/thunar/actions.sh
  qv/thunar/launch
  qv/thunar/open-here
  qv/thunar/reconcile-default-actions
  qv/thunar/set-background
  qv/thunar/transcode
  qv/tmux/qvos-tmux
  qv/waybar/clock.sh
  qv/waybar/prayer-data.sh
  qv/waybar/prayerbar.sh
)
for source_path in "${required_sources[@]}"; do
  if [[ ! -f $OMARCHY_PATH/$source_path ]]; then
    echo "Missing qvOS desktop feature file: $OMARCHY_PATH/$source_path" >&2
    return 1
  fi
done

# Remove payloads from retired standalone qvOS installers and desktop apps.
rm -rf -- \
  "$HOME/.local/share/qvos/branding" \
  "$HOME/.local/share/qvos/domains" \
  "$HOME/.local/share/qvos/hyprland" \
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

for feature in desktop tmux waybar; do
  feature_source="$OMARCHY_PATH/qv/$feature"
  feature_runtime="$HOME/.local/share/qvos/$feature"

  rm -rf -- "$feature_runtime"
  cp -a "$feature_source" "$feature_runtime"
done

thunar_source="$OMARCHY_PATH/qv/thunar"
thunar_runtime="$HOME/.local/share/qvos/thunar"
rm -rf -- "$thunar_runtime"
install -d "$thunar_runtime"
for feature in \
  actions.sh \
  launch \
  open-here \
  reconcile-default-actions \
  set-background \
  transcode; do
  cp -a "$thunar_source/$feature" "$thunar_runtime/$feature"
done

if ! "$HOME/.local/share/qvos/thunar/reconcile-default-actions"; then
  echo "qvOS preserved the current Thunar actions because they could not be reconciled." >&2
fi

screensaver_source="$OMARCHY_PATH/qv/screensaver"
qvos_bin="$HOME/.local/share/qvos/bin"
qvos_screensaver="$HOME/.local/share/qvos/screensaver"
local_bin="$HOME/.local/bin"

rm -rf -- "$qvos_screensaver"
install -d "$qvos_bin" "$qvos_screensaver" "$local_bin"
for command_name in omarchy-system-inhibit-sleep omarchy-system-suspend-if-safe; do
  install -m 0755 "$OMARCHY_PATH/bin/$command_name" "$qvos_bin/$command_name"
done
install -m 0644 "$screensaver_source/alacritty.toml" "$qvos_screensaver/alacritty.toml"
for command_name in omarchy-launch-screensaver qvos-launch-screensaver qvos-screensaver; do
  install -m 0755 "$screensaver_source/$command_name" "$qvos_bin/$command_name"
  ln -sfn "$qvos_bin/$command_name" "$local_bin/$command_name"
done
