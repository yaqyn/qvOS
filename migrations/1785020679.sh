echo "Install organized qvOS payloads and secure browser and install-log permissions"

migration_status=0
system_root="${QVOS_SYSTEM_ROOT:-}"

source "$OMARCHY_PATH/install/config/qvos-scripts.sh" ||
  migration_status=1
omarchy-refresh-config hypr/qv/bindings.conf ||
  migration_status=1
hyprctl reload &>/dev/null || true

if omarchy-cmd-present localsend; then
  "$OMARCHY_PATH/qv/core/share.sh" --adopt ||
    migration_status=1
fi

if omarchy-cmd-present codex; then
  "$OMARCHY_PATH/qv/core/codex.sh" --adopt ||
    migration_status=1
fi

if omarchy-cmd-present proton-drive &&
  proton-drive filesystem info -j /my-files >/dev/null 2>&1; then
  "$OMARCHY_PATH/qv/core/proton.sh" --adopt ||
    migration_status=1
fi

policy_group=$(id -gn)
policy_count=0
for policy_dir in \
  "$system_root/etc/chromium/policies/managed" \
  "$system_root/etc/opt/chrome/policies/managed" \
  "$system_root/etc/opt/edge/policies/managed" \
  "$system_root/etc/brave/policies/managed"; do
  [[ -d $policy_dir ]] || continue

  policy_count=$((policy_count + 1))
  sudo chown root:root "$policy_dir" ||
    migration_status=1
  sudo chmod 0755 "$policy_dir" ||
    migration_status=1
  if [[ -e $policy_dir/color.json ]]; then
    sudo chown "$USER:$policy_group" "$policy_dir/color.json" ||
      migration_status=1
    sudo chmod 0644 "$policy_dir/color.json" ||
      migration_status=1
  else
    sudo install -o "$USER" -g "$policy_group" -m 0644 \
      /dev/null "$policy_dir/color.json" ||
      migration_status=1
  fi
done
if ((policy_count > 0)); then
  omarchy-theme-set-browser ||
    migration_status=1
fi

install_log="$system_root/var/log/omarchy-install.log"
if [[ -e $install_log ]]; then
  sudo chown "$USER:$policy_group" "$install_log" ||
    migration_status=1
  sudo chmod 0640 "$install_log" ||
    migration_status=1
fi

if ((migration_status != 0)); then
  echo "The qvOS foundation migration is incomplete; it will retry on the next update." >&2
fi

((migration_status == 0))
