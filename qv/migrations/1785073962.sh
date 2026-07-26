hook_dir="$HOME/.config/omarchy/hooks/post-update.d"
install -d "$hook_dir"
install -m 0644 \
  "$OMARCHY_PATH/qv/core/post-update-hook" \
  "$hook_dir/qvos-qvcore"
rm -f \
  "$hook_dir/qvos-qvcore-share" \
  "$hook_dir/qvos-qvcore-dev" \
  "$hook_dir/qvos-qvcore-codex" \
  "$hook_dir/qvos-qvcore-proton"
