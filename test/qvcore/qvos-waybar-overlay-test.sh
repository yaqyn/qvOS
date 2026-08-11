#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
source_config="$root/qvcore/config/files/waybar/config.jsonc"
source_style="$root/qvcore/config/files/waybar/style.css"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/qv-restart-waybar" <<'STUB'
#!/bin/bash
touch "$HOME/waybar-restarted"
STUB
install -m 0755 /dev/stdin "$test_bin/pgrep" <<'STUB'
#!/bin/bash
[[ ${QVOS_TEST_HYPRIDLE:-0} == "1" ]]
STUB
install -m 0755 /dev/stdin "$test_bin/makoctl" <<'STUB'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_MAKO_MODE:-default}"
STUB

"$root/qvcore/waybar/check" >/dev/null || fail "Waybar owner contract"

PATH="$test_bin:/usr/bin" HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/waybar/refresh"
[[ -f $test_root/waybar-restarted ]] || fail "changed Waybar restart"
live_config="$test_root/.config/waybar/config.jsonc"
live_style="$test_root/.config/waybar/style.css"
cmp -s "$source_config" "$live_config" || fail "complete Waybar config restore"
cmp -s "$source_style" "$live_style" || fail "complete Waybar style restore"

jq -e '
  (."modules-left" + ."modules-center" + ."modules-right"
    | index("custom/qvos") != null) and
  (."modules-left" + ."modules-center" + ."modules-right"
    | index("group/prayer-clock") != null) and
  (."modules-left" + ."modules-center" + ."modules-right"
    | index("ext/workspaces") != null) and
  (."modules-left" + ."modules-center" + ."modules-right"
    | index("hyprland/workspaces") == null) and
  (."modules-left" + ."modules-center" + ."modules-right"
    | index("clock") == null) and
  ."ext/workspaces"."on-click" == "activate" and
  ."ext/workspaces"."sort-by-id" == true and
  (."ext/workspaces" | has("persistent-workspaces") | not) and
  ."custom/qvos".format == "󱅾" and
  ."custom/qvos"."on-click" == "qv-menu" and
  ."custom/update".exec == "qv-update-available" and
  ."custom/update"."on-click" == "qv-launch-update" and
  ."custom/weather".exec == "$QVOS_PATH/qvcore/weather/waybar" and
  ."custom/idle-indicator".exec == "$QVOS_PATH/qvcore/waybar/idle-status" and
  ."custom/notification-silencing-indicator".exec
    == "$QVOS_PATH/qvcore/waybar/notification-status" and
  ."custom/voxtype".exec == "qv-voxtype-status" and
  ."custom/voxtype"."on-click-right" == "qv-voxtype-config" and
  ."custom/voxtype"."on-click" == "qv-voxtype-model" and
  ."network"."on-click-right" == "qv-launch-task dns-configure" and
  ."custom/qv-clock"."on-click-right" == "qv-launch-task timezone" and
  ."group/prayer-clock".modules == ["custom/prayerbar", "custom/qv-clock"]
' "$live_config" >/dev/null || fail "native Waybar module contract"

workspace_style=$(sed -n \
  '/^window#waybar #workspaces button {/,/^}/p' \
  "$root/qvcore/theme/yaqyn/waybar.css")
grep -Fq '  color: @foreground;' <<<"$workspace_style" ||
  fail "normal workspace foreground"
grep -Fq '  opacity: 0.55;' <<<"$workspace_style" ||
  fail "normal workspace opacity"
urgent_style=$(sed -n \
  '/^window#waybar #workspaces button\.urgent,/,/^}/p' \
  "$root/qvcore/theme/yaqyn/waybar.css")
grep -Fq '  color: #ffffff;' <<<"$urgent_style" ||
  fail "urgent workspace color"
grep -Fq '  opacity: 1;' <<<"$urgent_style" ||
  fail "urgent workspace opacity"
grep -Fq '#custom-qvos {' "$root/qvcore/theme/yaqyn/waybar.css" ||
  fail "native qvOS menu style"

idle_json=$(PATH="$test_bin:/usr/bin" QVOS_TEST_HYPRIDLE=0 \
  "$root/qvcore/waybar/idle-status")
jq -e '.class == "active" and .text != ""' <<<"$idle_json" >/dev/null ||
  fail "disabled idle indicator"
idle_json=$(PATH="$test_bin:/usr/bin" QVOS_TEST_HYPRIDLE=1 \
  "$root/qvcore/waybar/idle-status")
jq -e '.text == "" and (has("class") | not)' <<<"$idle_json" >/dev/null ||
  fail "enabled idle indicator"
notification_json=$(PATH="$test_bin:/usr/bin" \
  QVOS_TEST_MAKO_MODE=do-not-disturb \
  "$root/qvcore/waybar/notification-status")
jq -e '.class == "active" and .text != ""' \
  <<<"$notification_json" >/dev/null || fail "silenced notification indicator"
notification_json=$(PATH="$test_bin:/usr/bin" QVOS_TEST_MAKO_MODE=default \
  "$root/qvcore/waybar/notification-status")
jq -e '.text == "" and (has("class") | not)' \
  <<<"$notification_json" >/dev/null || fail "normal notification indicator"

rm -f -- "$test_root/waybar-restarted"
PATH="$test_bin:/usr/bin" HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/waybar/refresh"
[[ ! -e $test_root/waybar-restarted ]] || fail "unchanged Waybar restart"
if compgen -G "$test_root/.config/waybar/*.bak.*" >/dev/null; then
  fail "unchanged Waybar backup"
fi
PATH="$test_bin:/usr/bin" HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/waybar/refresh" --status || fail "exact Waybar status"

custom_home="$test_root/custom-home"
custom_config="$custom_home/.config/waybar/config.jsonc"
install -D -m 0644 "$source_config" "$custom_config"
jq '."personal-setting" = true' "$custom_config" >"$custom_config.next"
mv -- "$custom_config.next" "$custom_config"
if PATH="$test_bin:/usr/bin" HOME="$custom_home" QVOS_PATH="$root" \
  "$root/qvcore/waybar/refresh" --status; then
  fail "custom Waybar config reported exact"
fi
jq -e '."personal-setting" == true' "$custom_config" >/dev/null ||
  fail "read-only Waybar status"
PATH="$test_bin:/usr/bin" HOME="$custom_home" QVOS_PATH="$root" \
  "$root/qvcore/waybar/refresh"
cmp -s "$source_config" "$custom_config" || fail "custom Waybar reset"
custom_backup=$(find "$custom_home/.config/waybar" -maxdepth 1 \
  -name 'config.jsonc.bak.*' -print -quit)
[[ -n $custom_backup ]] || fail "custom Waybar backup"
jq -e '."personal-setting" == true' "$custom_backup" >/dev/null ||
  fail "custom Waybar backup content"

invalid_root="$test_root/invalid-source"
invalid_home="$test_root/invalid-home"
invalid_live="$invalid_home/.config/waybar/config.jsonc"
install -D -m 0755 "$root/qvcore/config/refresh" \
  "$invalid_root/qvcore/config/refresh"
install -D -m 0644 "$source_style" \
  "$invalid_root/qvcore/config/files/waybar/style.css"
install -D -m 0644 "$source_config" "$invalid_live"
install -D -m 0644 /dev/stdin \
  "$invalid_root/qvcore/config/files/waybar/config.jsonc" <<'JSON'
[]
JSON
if PATH="$test_bin:/usr/bin" HOME="$invalid_home" QVOS_PATH="$invalid_root" \
  "$root/qvcore/waybar/refresh" >/dev/null 2>&1; then
  fail "invalid Waybar source accepted"
fi
cmp -s "$source_config" "$invalid_live" ||
  fail "invalid Waybar source preservation"
[[ ! -e $invalid_home/waybar-restarted ]] ||
  fail "invalid Waybar source restart"

fresh_home="$test_root/fresh-home"
PATH="$test_bin:/usr/bin" HOME="$fresh_home" QVOS_PATH="$root" \
  bash "$root/qvcore/install/config/config.sh"
PATH="$test_bin:/usr/bin" HOME="$fresh_home" QVOS_PATH="$root" \
  QVOS_WAYBAR_SKIP_RESTART=1 "$root/qvcore/waybar/refresh"
cmp -s "$source_config" "$fresh_home/.config/waybar/config.jsonc" ||
  fail "fresh Waybar configuration"
cmp -s "$source_style" "$fresh_home/.config/waybar/style.css" ||
  fail "fresh Waybar style"

install -m 0755 /dev/stdin "$test_bin/qv-refresh-waybar" <<'STUB'
#!/bin/bash
touch "$HOME/waybar-refreshed"
STUB
PATH="$test_bin:/usr/bin" HOME="$test_root" \
  bash "$root/qvcore/waybar/post-update-hook"
[[ -f $test_root/waybar-refreshed ]] || fail "post-update Waybar refresh"

runtime_home="$test_root/runtime-home"
install -d "$runtime_home/.local/lib/qvos/waybar"
touch "$runtime_home/.local/lib/qvos/waybar/stale-owner"
HOME="$runtime_home" QVOS_PATH="$root" "$root/qvcore/waybar/install"
runtime_inventory=$(find "$runtime_home/.local/lib/qvos/waybar" \
  -type f -printf '%P\n' | sort)
[[ $runtime_inventory == $'clock.sh\nprayer-data.sh\nprayerbar.sh' ]] ||
  fail "minimal Waybar runtime inventory"

unsafe_home="$test_root/unsafe-runtime-home"
foreign_runtime="$test_root/foreign-waybar-runtime"
install -d "$unsafe_home/.local/lib/qvos" "$foreign_runtime"
touch "$foreign_runtime/preserve"
ln -s "$foreign_runtime" "$unsafe_home/.local/lib/qvos/waybar"
if HOME="$unsafe_home" QVOS_PATH="$root" \
  "$root/qvcore/waybar/install" >/dev/null 2>&1; then
  fail "symbolic-link Waybar runtime accepted"
fi
[[ -e $foreign_runtime/preserve && ! -e $foreign_runtime/clock.sh ]] ||
  fail "symbolic-link Waybar runtime preservation"

for adapter in qv-refresh-waybar omarchy-refresh-waybar; do
  HOME="$test_root" QVOS_PATH="$root" PATH="$test_bin:/usr/bin" \
    "$root/bin/$adapter" --status || fail "$adapter owner delegation"
done
rg -q '^# qv:summary=' "$root/bin/qv-refresh-waybar" ||
  fail "native Waybar adapter metadata"
! rg -q '^# (qv|omarchy):' "$root/bin/omarchy-refresh-waybar" ||
  fail "compatibility Waybar adapter metadata"

printf 'ok - qvOS restores one complete native Waybar configuration\n'
