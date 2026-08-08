#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
systemctl_log="$test_root/systemctl.log"
owner="$root/qvcore/config/migrate-runtime-root"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$test_home/.config/Thunar" \
  "$test_home/.config/fastfetch" \
  "$test_home/.config/hypr" \
  "$test_home/.config/uwsm" \
  "$test_home/.config/waybar"
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
SCRIPT

install -m 0644 /dev/stdin "$test_home/.config/hypr/bindings.conf" <<'CONFIG'
exec = ~/.local/share/qvos/desktop/context/tool
exec = ~/.local/share/qvos/thunar/launch
exec = ~/.local/share/qvos/tmux/qvos-tmux
source = ~/.local/share/qvos/default/hypr/input.conf
bindeld = , XF86AudioMicMute, Mute microphone, exec, omarchy-audio-input-mute
bindeld = , XF86MonBrightnessUp, Brightness up, exec, omarchy-brightness-display +5%
bindeld = , XF86KbdBrightnessUp, Keyboard brightness up, exec, omarchy-brightness-keyboard up
bindeld = , XF86AudioRaiseVolume, Volume up, exec, omarchy-swayosd-client --output-volume raise
bindld = SUPER, XF86AudioMute, Switch audio output, exec, omarchy-audio-output-switch
bindd = SUPER CTRL ALT, B, Show battery remaining, exec, notify-send "$(omarchy-battery-status)"
bindd = SUPER CTRL, Delete, Toggle laptop display, exec, omarchy-hyprland-monitor-internal toggle
bindd = SUPER CTRL ALT, Delete, Mirror laptop display, exec, omarchy-hyprland-monitor-internal-mirror toggle
bindl = , switch:on:Lid Switch, exec, omarchy-hw-external-monitors && omarchy-hyprland-monitor-internal off
bindld = , XF86TouchpadToggle, Toggle touchpad, exec, omarchy-toggle-touchpad
bindld = , XF86TouchscreenToggle, Toggle touchscreen, exec, omarchy-toggle-touchscreen
bindd = SUPER CTRL ALT, R, Clear reminders, exec, omarchy-reminder clear
bindd = SUPER SHIFT CTRL ALT, R, Show reminders, exec, omarchy-reminder show
bindd = SUPER CTRL, V, Clipboard manager, exec, omarchy-launch-walker -m clipboard
bindd = SUPER, B, Browser, exec, omarchy-launch-browser
bindd = SUPER SHIFT, E, Editor, exec, omarchy-launch-editor
bindd = SUPER, Q, Web app, exec, omarchy-launch-webapp https://example.com
bindd = SUPER CTRL, T, Terminal app, exec, omarchy-launch-tui btop
bindd = SUPER CTRL, W, Wi-Fi, exec, omarchy-launch-wifi
bindd = SUPER, K, Show key bindings, exec, omarchy-menu-keybindings
bindd = CTRL ALT, DELETE, Close all windows, exec, omarchy-hyprland-window-close-all
bindd = SUPER SHIFT CTRL, F, Pop window, exec, omarchy-hyprland-window-pop
bindd = SUPER, L, Layout, exec, omarchy-hyprland-workspace-layout-toggle
bindd = SUPER, code:61, Scale, exec, omarchy-hyprland-monitor-scaling-cycle --reverse
bindd = SUPER, BACKSPACE, Transparency, exec, omarchy-hyprland-window-transparency-toggle
bindd = SUPER SHIFT, BACKSPACE, Gaps, exec, omarchy-hyprland-window-gaps-toggle
bindd = SUPER CTRL, BACKSPACE, Aspect, exec, omarchy-hyprland-window-single-square-aspect-toggle
bindd = SUPER CTRL, L, Lock system, exec, omarchy-system-lock
bindd = , PRINT, Screenshot, exec, omarchy-capture-screenshot
bindd = SUPER CTRL, PRINT, Extract text, exec, omarchy-capture-text-extraction
bindd = SUPER CTRL, PERIOD, Transcode, exec, omarchy-transcode
CONFIG
install -m 0644 /dev/stdin "$test_home/.config/hypr/hypridle.conf" <<'CONFIG'
lock_cmd = omarchy-system-lock
before_sleep_cmd = OMARCHY_LOCK_ONLY=true omarchy-system-lock
after_sleep_cmd = sleep 1 && omarchy-system-wake
exec = ~/.local/share/qvos/bin/omarchy-launch-screensaver
exec = ~/.local/share/qvos/bin/omarchy-system-suspend-if-safe --watch
CONFIG
install -m 0644 /dev/stdin "$test_home/.config/waybar/config.jsonc" <<'CONFIG'
{"audio":"omarchy-launch-audio","battery":"$(omarchy-battery-status)","bluetooth":"omarchy-launch-bluetooth","capture":"omarchy-capture-screenrecording","indicator":"$OMARCHY_PATH/default/waybar/indicators/screen-recording.sh","presentation":"omarchy-launch-floating-terminal-with-presentation qv-tz-select","tui":"omarchy-launch-or-focus-tui btop","weather":"$(omarchy-weather-status)","weather_icon":"omarchy-weather-icon","wifi":"omarchy-launch-wifi","timezone":"omarchy-tz-select"}
CONFIG
install -m 0644 /dev/stdin "$test_home/.config/fastfetch/config.jsonc" <<'CONFIG'
{"logo":{"type":"file-raw","source":"~/.config/omarchy/branding/about-fastfetch.ansi"},"modules":[{"text":"$(omarchy-version)"},{"text":"$(omarchy-theme-current)"},{"text":"$(omarchy-version-pkgs)"}]}
CONFIG
install -m 0600 /dev/stdin "$test_home/.config/Thunar/uca.xml" <<'CONFIG'
<command>$HOME/.local/share/qvos/thunar/open-here</command>
CONFIG
install -m 0644 /dev/stdin "$test_home/.config/uwsm/env" <<'CONFIG'
export OMARCHY_PATH=$HOME/.local/share/omarchy
export PATH=$OMARCHY_PATH/bin:$PATH:$HOME/.local/bin
export USER_SETTING=preserved

# qvOS PATH begin
export PATH="$HOME/.local/share/qvos/bin:$PATH"
# qvOS PATH end
CONFIG
install -m 0644 /dev/stdin "$test_home/.config/uwsm/default" <<'CONFIG'
# Keep this user comment.
export OMARCHY_SCREENSHOT_DIR="$HOME/Pictures/Private"
export OMARCHY_SCREENRECORD_DIR="$HOME/Videos/Private"
CONFIG
HOME="$test_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  "$owner" >/dev/null

grep -Fq '.local/lib/qvos/desktop/' "$test_home/.config/hypr/bindings.conf" ||
  fail "desktop runtime migration"
grep -Fq '.local/lib/qvos/thunar/' "$test_home/.config/hypr/bindings.conf" ||
  fail "Thunar runtime migration"
grep -Fq '.local/lib/qvos/tmux/' "$test_home/.config/hypr/bindings.conf" ||
  fail "tmux runtime migration"
grep -Fq '.local/share/qvos/default/' "$test_home/.config/hypr/bindings.conf" ||
  fail "source-root path preservation"
for command in \
  qv-audio-input-mute \
  qv-audio-output-switch \
  qv-battery-status \
  qv-brightness-display \
  qv-brightness-keyboard \
  qv-hw-external-monitors \
  qv-hyprland-monitor-internal \
  qv-hyprland-monitor-internal-mirror \
  qv-swayosd-client; do
  grep -Fq "$command" "$test_home/.config/hypr/bindings.conf" ||
    fail "promoted desktop control was not migrated: $command"
done
for command in qv-toggle-touchpad qv-toggle-touchscreen; do
  grep -Fq "$command" "$test_home/.config/hypr/bindings.conf" ||
    fail "promoted session config was not migrated: $command"
done
for command in 'qv-reminder clear' 'qv-reminder show'; do
  grep -Fq "$command" "$test_home/.config/hypr/bindings.conf" ||
    fail "promoted reminder route was not migrated: $command"
done
for command in \
  qv-capture-screenshot \
  qv-capture-text-extraction \
  qv-launch-browser \
  qv-launch-editor \
  qv-launch-tui \
  qv-launch-webapp \
  qv-launch-wifi \
  qv-launch-walker \
  qv-menu-keybindings \
  qv-transcode; do
  grep -Fq "$command" "$test_home/.config/hypr/bindings.conf" ||
    fail "promoted menu route was not migrated: $command"
done
for command in \
  qv-hyprland-monitor-scaling-cycle \
  qv-hyprland-window-close-all \
  qv-hyprland-window-gaps-toggle \
  qv-hyprland-window-pop \
  qv-hyprland-window-single-square-aspect-toggle \
  qv-hyprland-window-transparency-toggle \
  qv-hyprland-workspace-layout-toggle \
  qv-system-lock; do
  grep -Fq "$command" "$test_home/.config/hypr/bindings.conf" ||
    fail "promoted desktop session route was not migrated: $command"
done
if rg -q 'omarchy-(audio|brightness|capture-(screenshot|text-extraction)|hw-external-monitors|hyprland-(monitor-internal|monitor-scaling-cycle|window-(close-all|gaps-toggle|pop|single-square-aspect-toggle|transparency-toggle)|workspace-layout-toggle)|launch-(browser|editor|tui|webapp|wifi|walker)|menu-keybindings|reminder|swayosd|system-lock|toggle-touchpad|toggle-touchscreen|transcode)' \
  "$test_home/.config/hypr/bindings.conf"; then
  fail "desktop compatibility route remains after migration"
fi
grep -Fq '.local/lib/qvos/bin/qvos-launch-screensaver' \
  "$test_home/.config/hypr/hypridle.conf" ||
  fail "screensaver runtime migration"
grep -Fq '.local/lib/qvos/bin/qv-system-suspend-if-safe' \
  "$test_home/.config/hypr/hypridle.conf" ||
  fail "suspend runtime migration"
grep -Fq 'QVOS_LOCK_ONLY=true qv-system-lock' \
  "$test_home/.config/hypr/hypridle.conf" ||
  fail "lock-only session policy migration"
grep -Fq 'qv-system-wake' "$test_home/.config/hypr/hypridle.conf" ||
  fail "wake route migration"
if rg -q 'OMARCHY_LOCK_ONLY|omarchy-system-(lock|wake)' \
  "$test_home/.config/hypr/hypridle.conf"; then
  fail "desktop session compatibility policy remains after migration"
fi
grep -Fq 'qv-battery-status' "$test_home/.config/waybar/config.jsonc" ||
  fail "Waybar battery telemetry migration"
grep -Fq 'qv-tz-select' "$test_home/.config/waybar/config.jsonc" ||
  fail "Waybar timezone route migration"
grep -Fq 'qv-launch-floating-terminal-with-presentation' \
  "$test_home/.config/waybar/config.jsonc" ||
  fail "Waybar presentation route migration"
for command in \
  qv-launch-audio \
  qv-launch-bluetooth \
  qv-launch-or-focus-tui \
  qv-launch-wifi; do
  grep -Fq "$command" "$test_home/.config/waybar/config.jsonc" ||
    fail "Waybar launch route migration: $command"
done
grep -Fq 'qv-weather-icon' "$test_home/.config/waybar/config.jsonc" ||
  fail "Waybar weather icon migration"
grep -Fq 'qv-weather-status' "$test_home/.config/waybar/config.jsonc" ||
  fail "Waybar weather status migration"
grep -Fq 'qv-capture-screenrecording' "$test_home/.config/waybar/config.jsonc" ||
  fail "Waybar Capture route migration"
grep -Fq '$QVOS_PATH/qvcore/capture/status' \
  "$test_home/.config/waybar/config.jsonc" ||
  fail "Waybar Capture indicator migration"
if rg -q 'omarchy-(capture-screenrecording|launch-(audio|bluetooth|floating-terminal-with-presentation|or-focus-tui|wifi)|weather-(icon|status))' \
  "$test_home/.config/waybar/config.jsonc"; then
  fail "Waybar weather compatibility route remains"
fi
# These are literal config values, not shell paths.
# shellcheck disable=SC2088
grep -Fq '~/.config/qvos/branding/about.txt' \
  "$test_home/.config/fastfetch/config.jsonc" ||
  fail "Fastfetch branding-state migration"
# shellcheck disable=SC2088
if grep -Fq '~/.config/omarchy/branding/' \
  "$test_home/.config/fastfetch/config.jsonc"; then
  fail "Fastfetch legacy branding state remains"
fi
for command in qv-theme-current qv-version qv-version-pkgs; do
  grep -Fq "$command" "$test_home/.config/fastfetch/config.jsonc" ||
    fail "Fastfetch native command migration: $command"
done
if rg -q 'omarchy-(theme-current|version)' \
  "$test_home/.config/fastfetch/config.jsonc"; then
  fail "Fastfetch compatibility command remains"
fi
grep -Fq '.local/lib/qvos/thunar/open-here' \
  "$test_home/.config/Thunar/uca.xml" ||
  fail "Thunar action runtime migration"
grep -Fqx 'export QVOS_PATH=$HOME/.local/share/qvos' \
  "$test_home/.config/uwsm/env" ||
  fail "native source environment"
grep -Fqx 'export PATH=$QVOS_PATH/bin:$PATH:$HOME/.local/bin' \
  "$test_home/.config/uwsm/env" ||
  fail "native source path environment"
grep -Fqx 'export USER_SETTING=preserved' "$test_home/.config/uwsm/env" ||
  fail "custom environment preservation"
if grep -Fq '# qvOS PATH begin' "$test_home/.config/uwsm/env"; then
  fail "duplicate source path block cleanup"
fi
grep -Fqx 'export QVOS_SCREENSHOT_DIR="$HOME/Pictures/Private"' \
  "$test_home/.config/uwsm/default" || fail "screenshot environment migration"
grep -Fqx 'export QVOS_SCREENRECORD_DIR="$HOME/Videos/Private"' \
  "$test_home/.config/uwsm/default" || fail "recording environment migration"
grep -Fqx '# Keep this user comment.' "$test_home/.config/uwsm/default" ||
  fail "Capture environment custom content preservation"
[[ $(find "$test_home/.config" -type f -name '*.bak.*' | wc -l) == "7" ]] ||
  fail "changed config backup count"
[[ $(<"$systemctl_log") == "--user daemon-reload" ]] ||
  fail "user service reload"

state_before=$(find "$test_home/.config" -type f -printf '%P|%m|%i|%T@\n' | sort)
HOME="$test_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  "$owner" >/dev/null
[[ $(find "$test_home/.config" -type f -printf '%P|%m|%i|%T@\n' | sort) == \
  "$state_before" ]] ||
  fail "idempotent config migration"
[[ $(wc -l <"$systemctl_log") == "1" ]] ||
  fail "idempotent service reload"

unsafe_home="$test_root/unsafe-home"
external_config="$test_root/external-bindings"
install -d "$unsafe_home/.config/hypr"
printf 'foreign\n' >"$external_config"
ln -s "$external_config" "$unsafe_home/.config/hypr/bindings.conf"
if HOME="$unsafe_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  "$owner" >/dev/null 2>&1; then
  fail "symbolic-link config accepted"
fi
[[ $(<"$external_config") == "foreign" ]] ||
  fail "symbolic-link config preservation"

printf 'ok - source and runtime config roots migrate once without losing user state\n'
