#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
monitor_config="$test_home/.config/hypr/monitors.conf"
monitor_json="$test_root/monitors.json"
hyprctl_log="$test_root/hyprctl.log"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_home/.config/hypr" "$test_bin"
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'HYPRCTL'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_MONITOR_TEST_LOG"
case $* in
"reload")
  ;;
"configerrors")
  printf '%s' "${QVOS_MONITOR_TEST_ERRORS:-}"
  ;;
"monitors -j")
  cat "$QVOS_MONITOR_TEST_JSON"
  ;;
*)
  exit 2
  ;;
esac
HYPRCTL

run_detector() {
  HOME="$test_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_MONITOR_TEST_JSON="$monitor_json" \
  QVOS_MONITOR_TEST_LOG="$hyprctl_log" \
    "$root/qv/config/monitor-autodetect"
}

install -m 0644 "$root/config/hypr/monitors.conf" "$monitor_config"
install -m 0644 /dev/stdin "$monitor_json" <<'MONITORS'
[
  {
    "name": "HDMI-A-1",
    "width": 3840,
    "height": 2160,
    "scale": 2,
    "focused": true,
    "disabled": false
  },
  {
    "name": "eDP-1",
    "width": 1920,
    "height": 1080,
    "scale": 1,
    "focused": false,
    "disabled": false
  }
]
MONITORS
output=$(run_detector)
grep -Fqx 'env = GDK_SCALE,1' "$monitor_config" ||
  fail "internal display scale did not replace the generic toolkit scale"
grep -Fqx 'monitor=,preferred,auto,auto' "$monitor_config" ||
  fail "adaptive monitor selection was not preserved"
[[ $output == $'Display: eDP-1 - 1920x1080\nScale: 1x' ]] ||
  fail "detected display summary"
[[ $(grep -c '^reload$' "$hyprctl_log") == 2 ]] ||
  fail "display detection did not validate both reloads"

install -m 0644 "$root/config/hypr/monitors.conf" "$monitor_config"
install -m 0644 /dev/stdin "$monitor_json" <<'MONITORS'
[
  {
    "name": "DP-1",
    "width": 3840,
    "height": 2160,
    "scale": 1.6,
    "focused": true,
    "disabled": false
  }
]
MONITORS
run_detector >/dev/null
grep -Fqx 'env = GDK_SCALE,1.6' "$monitor_config" ||
  fail "focused external display scale fallback"

install -m 0644 "$root/config/hypr/monitors.conf" "$monitor_config"
sed -i \
  -e 's/^env = GDK_SCALE,2$/env = GDK_SCALE,1/' \
  -e 's/^monitor=,preferred,auto,auto$/monitor=DP-1,2560x1440@144,0x0,1/' \
  "$monitor_config"
cp "$monitor_config" "$test_root/custom-before.conf"
: >"$hyprctl_log"
output=$(run_detector)
cmp -s "$test_root/custom-before.conf" "$monitor_config" ||
  fail "custom display layout was modified"
[[ $output == "Display configuration: Preserved custom layout" ]] ||
  fail "custom layout preservation summary"
[[ ! -s $hyprctl_log ]] ||
  fail "custom layout unnecessarily queried Hyprland"

install -m 0644 "$root/config/hypr/monitors.conf" "$monitor_config"
cp "$monitor_config" "$test_root/error-before.conf"
if output=$(
  QVOS_MONITOR_TEST_ERRORS="invalid monitor config" run_detector 2>&1
); then
  fail "invalid restored configuration was accepted"
fi
cmp -s "$test_root/error-before.conf" "$monitor_config" ||
  fail "failed detection changed the monitor config"
grep -Fq \
  'Hyprland rejected the restored configuration: invalid monitor config' \
  <<<"$output" ||
  fail "invalid restored configuration diagnostic"

install -m 0755 /dev/stdin "$test_bin/omarchy-refresh-config" <<'REFRESH'
#!/bin/bash
source_file="$OMARCHY_PATH/config/$1"
target_file="$HOME/.config/$1"
install -D -m 0644 "$source_file" "$target_file"
REFRESH
install -m 0644 /dev/stdin "$monitor_json" <<'MONITORS'
[
  {
    "name": "eDP-1",
    "width": 1920,
    "height": 1080,
    "scale": 1,
    "focused": true,
    "disabled": false
  }
]
MONITORS
: >"$hyprctl_log"
HOME="$test_home" \
OMARCHY_PATH="$root" \
PATH="$test_bin:/usr/bin" \
QVOS_MONITOR_TEST_JSON="$monitor_json" \
QVOS_MONITOR_TEST_LOG="$hyprctl_log" \
  "$root/bin/omarchy-refresh-hyprland" >/dev/null
grep -Fqx 'env = GDK_SCALE,1' "$monitor_config" ||
  fail "complete Hyprland restore did not detect the current display"
grep -Fqx 'monitor=,preferred,auto,auto' "$monitor_config" ||
  fail "complete Hyprland restore lost adaptive monitor selection"
cmp -s \
  "$root/qv/config/files/hypr/qv.conf" \
  "$test_home/.config/hypr/qv.conf" ||
  fail "complete Hyprland restore lost the qvOS config layer"

grep -Fqx "\"\$OMARCHY_PATH/qv/config/monitor-autodetect\"" \
  "$root/qv/install/first-run/apply" ||
  fail "fresh first login display detection"
grep -Fqx "\"\$OMARCHY_PATH/qv/config/monitor-autodetect\"" \
  "$root/qv/config/refresh-hyprland" ||
  fail "Hyprland restore display detection"
grep -Fq \
  "monitor_owner=\"\$OMARCHY_PATH/qv/config/monitor-autodetect\"" \
  "$root/qv/install/configure" ||
  fail "fresh install display owner preflight"

printf 'ok - fresh login and explicit restore detect scale without rewriting custom layouts\n'
