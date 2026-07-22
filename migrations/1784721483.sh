echo "Keep qvOS Waybar overrides layered over Omarchy updates"

install -d "$HOME/.config/omarchy/hooks/post-update.d"
install -m 0644 \
  "$OMARCHY_PATH/config/omarchy/hooks/post-update.d/qvos-waybar-overrides" \
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-waybar-overrides"
rm -f "$HOME/.config/omarchy/hooks/post-update.d/qvos-prayer-clock"
