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
  reload_count=$(grep -c '^reload$' "$QVOS_MONITOR_TEST_LOG" || true)
  if [[ ${QVOS_MONITOR_TEST_FAIL_RELOAD_AT:-0} == "$reload_count" ]]; then
    exit 1
  fi
  ;;
"configerrors")
  error_count=$(grep -c '^configerrors$' "$QVOS_MONITOR_TEST_LOG" || true)
  if [[ ${QVOS_MONITOR_TEST_FAIL_ERRORS_AT:-0} == "$error_count" ]]; then
    exit 1
  fi
  if [[ -z ${QVOS_MONITOR_TEST_ERRORS_AT:-} ||
    ${QVOS_MONITOR_TEST_ERRORS_AT:-0} == "$error_count" ]]; then
    printf '%s' "${QVOS_MONITOR_TEST_ERRORS:-}"
  fi
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
  QVOS_MONITOR_TEST_ERRORS="${QVOS_MONITOR_TEST_ERRORS:-}" \
  QVOS_MONITOR_TEST_ERRORS_AT="${QVOS_MONITOR_TEST_ERRORS_AT:-}" \
  QVOS_MONITOR_TEST_FAIL_RELOAD_AT="${QVOS_MONITOR_TEST_FAIL_RELOAD_AT:-0}" \
  QVOS_MONITOR_TEST_FAIL_ERRORS_AT="${QVOS_MONITOR_TEST_FAIL_ERRORS_AT:-0}" \
    "$root/qvcore/config/monitor-autodetect"
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
printf '%s\n' 'monitor=DP-2,disable' >>"$monitor_config"
cp "$monitor_config" "$test_root/mixed-before.conf"
: >"$hyprctl_log"
output=$(run_detector)
cmp -s "$test_root/mixed-before.conf" "$monitor_config" ||
  fail "mixed custom display layout was modified"
[[ $output == "Display configuration: Preserved custom layout" ]] ||
  fail "mixed custom layout preservation summary"
[[ ! -s $hyprctl_log ]] ||
  fail "mixed custom layout unnecessarily queried Hyprland"

install -m 0644 "$root/config/hypr/monitors.conf" "$monitor_config"
cp "$monitor_config" "$test_root/error-before.conf"
: >"$hyprctl_log"
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

install -m 0644 "$root/config/hypr/monitors.conf" "$monitor_config"
cp "$monitor_config" "$test_root/reload-before.conf"
: >"$hyprctl_log"
if output=$(
  QVOS_MONITOR_TEST_FAIL_RELOAD_AT=2 run_detector 2>&1
); then
  fail "failed detected-scale reload was accepted"
fi
cmp -s "$test_root/reload-before.conf" "$monitor_config" ||
  fail "failed detected-scale reload did not restore the monitor config"
[[ $(grep -c '^reload$' "$hyprctl_log") == 3 ]] ||
  fail "failed detected-scale reload did not reload the restored config"
grep -Fq \
  'Hyprland could not reload the detected display scale' \
  <<<"$output" ||
  fail "detected-scale reload failure diagnostic"

install -m 0644 "$root/config/hypr/monitors.conf" "$monitor_config"
cp "$monitor_config" "$test_root/validation-before.conf"
: >"$hyprctl_log"
if output=$(
  QVOS_MONITOR_TEST_ERRORS="invalid detected scale" \
  QVOS_MONITOR_TEST_ERRORS_AT=2 \
    run_detector 2>&1
); then
  fail "invalid detected scale was accepted"
fi
cmp -s "$test_root/validation-before.conf" "$monitor_config" ||
  fail "invalid detected scale did not restore the monitor config"
[[ $(grep -c '^configerrors$' "$hyprctl_log") == 3 ]] ||
  fail "restored monitor config was not revalidated"
grep -Fq \
  'Hyprland rejected the detected display scale: invalid detected scale' \
  <<<"$output" ||
  fail "detected-scale validation failure diagnostic"

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
QVOS_PATH="$root" \
OMARCHY_PATH="$root" \
PATH="$test_bin:/usr/bin" \
QVOS_MONITOR_TEST_JSON="$monitor_json" \
QVOS_MONITOR_TEST_LOG="$hyprctl_log" \
  "$root/bin/qv-refresh-hyprland" >/dev/null
grep -Fqx 'env = GDK_SCALE,1' "$monitor_config" ||
  fail "complete Hyprland restore did not detect the current display"
grep -Fqx 'monitor=,preferred,auto,auto' "$monitor_config" ||
  fail "complete Hyprland restore lost adaptive monitor selection"
cmp -s \
  "$root/qvcore/config/files/hypr/qv.conf" \
  "$test_home/.config/hypr/qv.conf" ||
  fail "complete Hyprland restore lost the qvOS config layer"

install -m 0644 "$root/config/hypr/monitors.conf" "$monitor_config"
: >"$hyprctl_log"
if output=$(
  HOME="$test_home" \
  QVOS_PATH="$root" \
  OMARCHY_PATH="$root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_MONITOR_TEST_JSON="$monitor_json" \
  QVOS_MONITOR_TEST_LOG="$hyprctl_log" \
  QVOS_MONITOR_TEST_FAIL_RELOAD_AT=1 \
    "$root/bin/qv-refresh-hyprland" 2>&1
); then
  fail "complete Hyprland restore hid display detection failure"
fi
grep -Fq \
  'Hyprland could not reload the restored configuration' \
  <<<"$output" ||
  fail "complete restore failure diagnostic"

external_monitor_config="$test_root/external-monitors.conf"
install -m 0644 "$root/config/hypr/monitors.conf" "$external_monitor_config"
cp "$external_monitor_config" "$test_root/external-before.conf"
rm "$monitor_config"
ln -s "$external_monitor_config" "$monitor_config"
: >"$hyprctl_log"
if output=$(
  HOME="$test_home" \
  QVOS_PATH="$root" \
  OMARCHY_PATH="$root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_MONITOR_TEST_JSON="$monitor_json" \
  QVOS_MONITOR_TEST_LOG="$hyprctl_log" \
    "$root/bin/qv-refresh-hyprland" 2>&1
); then
  fail "complete Hyprland restore followed a symbolic-link monitor config"
fi
cmp -s "$test_root/external-before.conf" "$external_monitor_config" ||
  fail "symbolic-link restore preflight modified the external monitor config"
[[ ! -s $hyprctl_log ]] ||
  fail "symbolic-link restore preflight reached Hyprland"
grep -Fq \
  'refusing to restore through a symbolic-link monitor config' \
  <<<"$output" ||
  fail "symbolic-link restore preflight diagnostic"

grep -Fqx "\"\$QVOS_PATH/qvcore/config/monitor-autodetect\"" \
  "$root/qvcore/install/first-run/run" ||
  fail "fresh first login display detection"
grep -Fqx "\"\$QVOS_PATH/qvcore/config/monitor-autodetect\"" \
  "$root/qvcore/config/refresh-hyprland" ||
  fail "Hyprland restore display detection"
grep -Fq \
  "monitor_owner=\"\$QVOS_PATH/qvcore/config/monitor-autodetect\"" \
  "$root/qvcore/install/configure" ||
  fail "fresh install display owner preflight"

printf 'ok - fresh login and explicit restore detect scale without rewriting custom layouts\n'
