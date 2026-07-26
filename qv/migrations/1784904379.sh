"$OMARCHY_PATH/qv/config/refresh" hypr/qv/bindings.conf

uwsm_defaults="$HOME/.config/uwsm/default"
if [[ -f $uwsm_defaults ]] && grep -qx 'export EDITOR=code' "$uwsm_defaults"; then
  omarchy-default-editor nvim
fi
