install -d "$HOME/.config/omarchy/hooks/post-update.d"
install -m 0644 \
  "$OMARCHY_PATH/qv/waybar/post-update-hook" \
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-waybar-overrides"
rm -f "$HOME/.config/omarchy/hooks/post-update.d/qvos-prayer-clock"
