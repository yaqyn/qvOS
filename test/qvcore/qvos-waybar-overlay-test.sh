#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"

"$root/qvcore/waybar/check" >/dev/null || fail "Waybar owner contract"

cat >"$test_bin/qv-restart-waybar" <<'STUB'
#!/bin/bash
touch "$HOME/waybar-restarted"
STUB

chmod 0755 "$test_bin/qv-restart-waybar"

PATH="$test_bin:$PATH" HOME="$test_root" QVOS_PATH="$root" \
  bash "$root/qvcore/waybar/refresh"
[[ -f $test_root/waybar-restarted ]] || fail "Waybar restart"

source_config="$root/config/waybar/config.jsonc"
live_config="$test_root/.config/waybar/config.jsonc"

cmp -s "$root/config/waybar/style.css" "$test_root/.config/waybar/style.css" || fail "upstream Waybar style"
workspace_style=$(sed -n '/^window#waybar #workspaces button {/,/^}/p' "$root/qvcore/theme/yaqyn/waybar.css")
grep -Fq '  color: @foreground;' <<<"$workspace_style" || fail "normal workspace foreground"
grep -Fq '  opacity: 0.55;' <<<"$workspace_style" || fail "normal workspace opacity"
empty_workspace_style=$(sed -n '/^window#waybar #workspaces button\.empty {/,/^}/p' "$root/qvcore/theme/yaqyn/waybar.css")
grep -Fq '  color: @muted;' <<<"$empty_workspace_style" || fail "empty workspace muted color"
grep -Fq '  opacity: 0.3;' <<<"$empty_workspace_style" || fail "empty workspace opacity"
active_workspace_style=$(sed -n '/^window#waybar #workspaces button\.active {/,/^}/p' "$root/qvcore/theme/yaqyn/waybar.css")
grep -Fq '  color: @bright;' <<<"$active_workspace_style" || fail "active workspace bright color"
grep -Fq '  opacity: 0.75;' <<<"$active_workspace_style" || fail "active workspace opacity"
grep -Fq 'window#waybar #workspaces button.urgent label {' "$root/qvcore/theme/yaqyn/waybar.css" || fail "urgent workspace label color"
urgent_workspace_style=$(sed -n '/^window#waybar #workspaces button\.urgent,/,/^}/p' "$root/qvcore/theme/yaqyn/waybar.css")
grep -Fq '  color: #ffffff;' <<<"$urgent_workspace_style" || fail "urgent workspace pure-white style"
grep -Fq '  opacity: 1;' <<<"$urgent_workspace_style" || fail "urgent workspace full opacity"
if grep -Fq '@define-color attention ' "$root/qvcore/theme/yaqyn/waybar.css"; then
  fail "separate urgent workspace attention color"
fi

jq -e --slurpfile source "$source_config" '
  (."modules-left" + ."modules-center" + ."modules-right" | index("clock") == null) and
  (."modules-left" + ."modules-center" + ."modules-right" | index("group/prayer-clock") != null) and
  (."custom/omarchy".format == "󱅾") and
  (."custom/omarchy"."on-click" == "omarchy-menu") and
  (."custom/update".exec == "qv-update-available") and
  (."custom/update"."on-click" == "qv-launch-update") and
  (."custom/voxtype".exec == "qv-voxtype-status") and
  (."custom/voxtype"."on-click-right" == "qv-voxtype-config") and
  (."custom/voxtype"."on-click" == "qv-voxtype-model") and
  (."network"."on-click-right" == "qv-launch-task dns-configure") and
  (."hyprland/workspaces"."format-icons" == $source[0]."hyprland/workspaces"."format-icons") and
  (."group/prayer-clock".modules == ["custom/prayerbar", "custom/qv-clock"]) and
  (."custom/prayerbar".exec == "~/.local/lib/qvos/waybar/prayerbar.sh") and
  (."custom/qv-clock".exec == "~/.local/lib/qvos/waybar/clock.sh") and
  (."custom/qv-clock"."on-click-right" == "qv-launch-task timezone")
' "$live_config" >/dev/null || fail "prayer clock overlay"

PATH="$test_bin:$PATH" HOME="$test_root" QVOS_PATH="$root" \
  bash "$root/qvcore/waybar/refresh"
if compgen -G "$test_root/.config/waybar/config.jsonc.bak.*" >/dev/null; then
  fail "unchanged refresh backup cleanup"
fi

cmp -s \
  <(jq -S . "$source_config") \
  <(jq -S --slurpfile source "$source_config" '
    del(."custom/prayerbar", ."custom/qv-clock", ."group/prayer-clock")
    | ."custom/omarchy".format = $source[0]."custom/omarchy".format
    | ."custom/omarchy"."on-click" = $source[0]."custom/omarchy"."on-click"
    | ."custom/omarchy"."tooltip-format" = $source[0]."custom/omarchy"."tooltip-format"
    | ."custom/update".exec = $source[0]."custom/update".exec
    | ."custom/update"."on-click" = $source[0]."custom/update"."on-click"
    | ."custom/update"."tooltip-format" = $source[0]."custom/update"."tooltip-format"
    | ."custom/voxtype".exec = $source[0]."custom/voxtype".exec
    | ."custom/voxtype"."on-click-right" = $source[0]."custom/voxtype"."on-click-right"
    | ."custom/voxtype"."on-click" = $source[0]."custom/voxtype"."on-click"
    | if ($source[0].network | has("on-click-right")) then
        ."network"."on-click-right" = $source[0]."network"."on-click-right"
      else
        del(."network"."on-click-right")
      end
    | ."hyprland/workspaces"."format-icons" = $source[0]."hyprland/workspaces"."format-icons"
    | .["modules-left"] |= map(if . == "group/prayer-clock" then "clock" else . end)
    | .["modules-center"] |= map(if . == "group/prayer-clock" then "clock" else . end)
    | .["modules-right"] |= map(if . == "group/prayer-clock" then "clock" else . end)
  ' "$live_config") || fail "narrow qvOS Waybar overlay"

no_clock_root="$test_root/omarchy-without-clock"
no_clock_config="$no_clock_root/config/waybar/config.jsonc"
no_clock_home="$test_root/no-clock-home"
install -D -m 0644 "$root/config/waybar/style.css" "$no_clock_root/config/waybar/style.css"
install -D -m 0644 "$root/qvcore/waybar/overrides.jsonc" \
  "$no_clock_root/qvcore/waybar/overrides.jsonc"
install -D -m 0755 "$root/qvcore/config/refresh" \
  "$no_clock_root/qvcore/config/refresh"
jq '
  .["modules-left"] |= map(select(. != "clock"))
  | .["modules-center"] |= map(select(. != "clock"))
  | .["modules-right"] |= map(select(. != "clock"))
' "$source_config" >"$no_clock_config"

PATH="$test_bin:$PATH" HOME="$no_clock_home" QVOS_PATH="$no_clock_root" \
  bash "$root/qvcore/waybar/refresh"
no_clock_live="$no_clock_home/.config/waybar/config.jsonc"

jq -e '
  .["modules-center"][0] == "group/prayer-clock" and
  any(.["modules-left", "modules-center", "modules-right"][]; . == "group/prayer-clock")
' "$no_clock_live" >/dev/null || fail "prayer clock fallback without an Omarchy clock"

cmp -s \
  <(jq -S . "$no_clock_config") \
  <(jq -S --slurpfile source "$no_clock_config" '
    del(."custom/prayerbar", ."custom/qv-clock", ."group/prayer-clock")
    | ."custom/omarchy".format = $source[0]."custom/omarchy".format
    | ."custom/omarchy"."on-click" = $source[0]."custom/omarchy"."on-click"
    | ."custom/omarchy"."tooltip-format" = $source[0]."custom/omarchy"."tooltip-format"
    | ."custom/update".exec = $source[0]."custom/update".exec
    | ."custom/update"."on-click" = $source[0]."custom/update"."on-click"
    | ."custom/update"."tooltip-format" = $source[0]."custom/update"."tooltip-format"
    | ."custom/voxtype".exec = $source[0]."custom/voxtype".exec
    | ."custom/voxtype"."on-click-right" = $source[0]."custom/voxtype"."on-click-right"
    | ."custom/voxtype"."on-click" = $source[0]."custom/voxtype"."on-click"
    | if ($source[0].network | has("on-click-right")) then
        ."network"."on-click-right" = $source[0]."network"."on-click-right"
      else
        del(."network"."on-click-right")
      end
    | ."hyprland/workspaces"."format-icons" = $source[0]."hyprland/workspaces"."format-icons"
    | .["modules-center"] |= map(select(. != "group/prayer-clock"))
  ' "$no_clock_live") || fail "narrow fallback changes"

sparse_root="$test_root/omarchy-sparse-layout"
sparse_config="$sparse_root/config/waybar/config.jsonc"
sparse_home="$test_root/sparse-home"
install -D -m 0644 "$root/config/waybar/style.css" "$sparse_root/config/waybar/style.css"
install -D -m 0644 "$root/qvcore/waybar/overrides.jsonc" \
  "$sparse_root/qvcore/waybar/overrides.jsonc"
install -D -m 0755 "$root/qvcore/config/refresh" \
  "$sparse_root/qvcore/config/refresh"
jq '
  del(.["modules-left"], .["modules-center"])
  | .["modules-right"] |= map(select(. != "clock"))
  | ."future-omarchy-setting" = true
' "$source_config" >"$sparse_config"

PATH="$test_bin:$PATH" HOME="$sparse_home" QVOS_PATH="$sparse_root" \
  bash "$root/qvcore/waybar/refresh"
sparse_live="$sparse_home/.config/waybar/config.jsonc"

jq -e '
  (has("modules-left") | not) and
  .["modules-center"] == ["group/prayer-clock"] and
  ."custom/voxtype".exec == "qv-voxtype-status" and
  ."custom/voxtype"."on-click-right" == "qv-voxtype-config" and
  ."custom/voxtype"."on-click" == "qv-voxtype-model" and
  ."future-omarchy-setting" == true
' "$sparse_live" >/dev/null || fail "future sparse Omarchy layout"

custom_home="$test_root/custom-home"
custom_config="$custom_home/.config/waybar/config.jsonc"
install -D -m 0644 "$source_config" "$custom_config"
jq '."personal-setting" = true' "$custom_config" >"$custom_config.tmp"
mv "$custom_config.tmp" "$custom_config"
PATH="$test_bin:$PATH" HOME="$custom_home" QVOS_PATH="$root" \
  bash "$root/qvcore/waybar/refresh" >/dev/null
custom_backup="$(find "$custom_home/.config/waybar" -maxdepth 1 -name 'config.jsonc.bak.*' -print -quit)"
[[ -n $custom_backup ]] || fail "changed Waybar config backup"
jq -e '."personal-setting" == true' "$custom_backup" >/dev/null || fail "Waybar backup contents"

invalid_root="$test_root/omarchy-invalid-config"
invalid_home="$test_root/invalid-home"
invalid_live="$invalid_home/.config/waybar/config.jsonc"
install -D -m 0644 "$root/config/waybar/style.css" "$invalid_root/config/waybar/style.css"
install -D -m 0644 "$root/qvcore/waybar/overrides.jsonc" \
  "$invalid_root/qvcore/waybar/overrides.jsonc"
install -D -m 0755 "$root/qvcore/config/refresh" \
  "$invalid_root/qvcore/config/refresh"
install -D -m 0644 "$source_config" "$invalid_live"
printf '[]\n' >"$invalid_root/config/waybar/config.jsonc"
if PATH="$test_bin:$PATH" HOME="$invalid_home" QVOS_PATH="$invalid_root" \
  bash "$root/qvcore/waybar/refresh" >/dev/null 2>&1; then
  fail "invalid Waybar config rejection"
fi
cmp -s "$source_config" "$invalid_live" || fail "invalid Waybar config preservation"
[[ ! -e $invalid_home/waybar-restarted ]] || fail "invalid Waybar config restart"

fresh_home="$test_root/fresh-home"
install -d "$fresh_home/.local/share"
ln -s "$root" "$fresh_home/.local/share/omarchy"
PATH="$test_bin:$PATH" HOME="$fresh_home" QVOS_PATH="$root" \
  bash "$root/qvcore/install/config/config.sh"
PATH="$test_bin:$PATH" HOME="$fresh_home" QVOS_PATH="$root" \
  QVOS_WAYBAR_SKIP_RESTART=1 bash "$root/qvcore/waybar/refresh"

jq -e --slurpfile source "$source_config" '
  (.["modules-left"] + .["modules-center"] + .["modules-right"] | index("group/prayer-clock") != null) and
  (."custom/omarchy".format == "󱅾") and
  (."custom/omarchy"."on-click" == "omarchy-menu") and
  (."custom/update".exec == "qv-update-available") and
  (."custom/update"."on-click" == "qv-launch-update") and
  (."custom/voxtype".exec == "qv-voxtype-status") and
  (."custom/voxtype"."on-click-right" == "qv-voxtype-config") and
  (."custom/voxtype"."on-click" == "qv-voxtype-model") and
  (."network"."on-click-right" == "qv-launch-task dns-configure") and
  (."custom/qv-clock"."on-click-right" == "qv-launch-task timezone") and
  (."hyprland/workspaces"."format-icons" == $source[0]."hyprland/workspaces"."format-icons")
' "$fresh_home/.config/waybar/config.jsonc" >/dev/null || fail "fresh install Waybar overlay"
if compgen -G "$fresh_home/.config/waybar/config.jsonc.bak.*" >/dev/null; then
  fail "fresh install Waybar backup"
fi
[[ ! -e $fresh_home/waybar-restarted ]] || fail "fresh install Waybar restart"

cat >"$test_bin/qv-refresh-waybar" <<'STUB'
#!/bin/bash
touch "$HOME/waybar-refreshed"
STUB
chmod 0755 "$test_bin/qv-refresh-waybar"

PATH="$test_bin:$PATH" HOME="$test_root" \
  bash "$root/qvcore/waybar/post-update-hook"
[[ -f $test_root/waybar-refreshed ]] || fail "post-update prayer clock refresh"

runtime_home="$test_root/runtime-home"
install -d "$runtime_home/.local/lib/qvos/waybar"
touch "$runtime_home/.local/lib/qvos/waybar/stale-owner"
HOME="$runtime_home" QVOS_PATH="$root" "$root/qvcore/waybar/install"
runtime_inventory=$(find "$runtime_home/.local/lib/qvos/waybar" \
  -type f -printf '%P\n' | sort)
[[ $runtime_inventory == $'clock.sh\nprayer-data.sh\nprayerbar.sh' ]] ||
  fail "minimal Waybar runtime inventory"
for runtime_path in clock.sh prayer-data.sh prayerbar.sh; do
  cmp -s \
    "$root/qvcore/waybar/$runtime_path" \
    "$runtime_home/.local/lib/qvos/waybar/$runtime_path" ||
    fail "Waybar runtime source: $runtime_path"
done

unsafe_home="$test_root/unsafe-runtime-home"
foreign_runtime="$test_root/foreign-waybar-runtime"
install -d "$unsafe_home/.local/lib/qvos" "$foreign_runtime"
touch "$foreign_runtime/preserve"
ln -s "$foreign_runtime" "$unsafe_home/.local/lib/qvos/waybar"
if HOME="$unsafe_home" QVOS_PATH="$root" \
  "$root/qvcore/waybar/install" >/dev/null 2>&1; then
  fail "symbolic-link Waybar runtime rejection"
fi
[[ -e $foreign_runtime/preserve && ! -e $foreign_runtime/clock.sh ]] ||
  fail "symbolic-link Waybar runtime preservation"

incomplete_home="$test_root/incomplete-runtime-home"
incomplete_source="$test_root/incomplete-source"
install -d \
  "$incomplete_home/.local/lib/qvos/waybar" \
  "$incomplete_source/qvcore/waybar"
touch "$incomplete_home/.local/lib/qvos/waybar/preserve"
printf 'missing.sh\n' >"$incomplete_source/qvcore/waybar/runtime-paths"
if HOME="$incomplete_home" QVOS_PATH="$incomplete_source" \
  "$root/qvcore/waybar/install" >/dev/null 2>&1; then
  fail "incomplete Waybar runtime source rejection"
fi
[[ -e $incomplete_home/.local/lib/qvos/waybar/preserve ]] ||
  fail "incomplete Waybar runtime preservation"

for adapter in qv-refresh-waybar omarchy-refresh-waybar; do
  HOME="$test_root" QVOS_PATH="$root" PATH="$test_bin:$PATH" \
    QVOS_WAYBAR_SKIP_RESTART=1 "$root/bin/$adapter" --status ||
    fail "$adapter owner delegation"
done
rg -q '^# qv:summary=' "$root/bin/qv-refresh-waybar" ||
  fail "native Waybar adapter metadata"
! rg -q '^# (qv|omarchy):' "$root/bin/omarchy-refresh-waybar" ||
  fail "compatibility Waybar adapter metadata"
[[ ! -e $root/bin/omarchy-qvos-refresh-waybar ]] ||
  fail "retired qvOS-in-Omarchy Waybar route"
[[ ! -e $root/bin/omarchy-launch-qvos-task ]] ||
  fail "retired qvOS-in-Omarchy task route"

printf 'ok - qvOS applies only its narrow Waybar overrides\n'
