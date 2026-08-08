#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
source_fixture="$test_root/source"
hyprctl_log="$test_root/hyprctl.log"
notification_log="$test_root/notification.log"
config_log="$test_root/config.log"
socket_log="$test_root/socket.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_log() {
  grep -Fqx -- "$1" "$2" || fail "$3"
}

install -d \
  "$test_bin" \
  "$test_home/.config/hypr" \
  "$source_fixture/qvcore/config" \
  "$source_fixture/qvcore/desktop/hyprland"

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >>"$QVOS_TEST_HYPRCTL_LOG"
case ${1:-} in
monitors)
  [[ ${2:-} == "-j" ]]
  cat -- "$QVOS_TEST_MONITOR_JSON"
  ;;
activewindow)
  [[ ${2:-} == "-j" ]]
  cat -- "$QVOS_TEST_WINDOW_JSON"
  ;;
activeworkspace)
  [[ ${2:-} == "-j" ]]
  cat -- "$QVOS_TEST_WORKSPACE_JSON"
  ;;
keyword)
  [[ ${QVOS_TEST_KEYWORD_FAIL:-false} != "true" ]]
  ;;
dispatch | -q) ;;
*) exit 64 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_NOTIFICATION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/socat" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_SOCKET_LOG"
cat -- "$QVOS_TEST_EVENTS"
SCRIPT

for owner in \
  monitor-watch \
  window-gaps-toggle \
  window-single-square-aspect-toggle; do
  install -m 0755 "$root/qvcore/desktop/hyprland/$owner" \
    "$source_fixture/qvcore/desktop/hyprland/$owner"
done
for owner in hyprland-toggle monitor-internal monitor-internal-mirror; do
  install -m 0755 /dev/stdin "$source_fixture/qvcore/config/$owner" <<'SCRIPT'
#!/bin/bash
printf '%s:%s\n' "${0##*/}" "$*" >>"$QVOS_TEST_CONFIG_LOG"
SCRIPT
done

monitor_json="$test_root/monitor.json"
window_json="$test_root/window.json"
workspace_json="$test_root/workspace.json"
events="$test_root/events"
export PATH="$test_bin:/usr/bin"
export HOME="$test_home"
export QVOS_TEST_HYPRCTL_LOG="$hyprctl_log"
export QVOS_TEST_NOTIFICATION_LOG="$notification_log"
export QVOS_TEST_CONFIG_LOG="$config_log"
export QVOS_TEST_SOCKET_LOG="$socket_log"
export QVOS_TEST_MONITOR_JSON="$monitor_json"
export QVOS_TEST_WINDOW_JSON="$window_json"
export QVOS_TEST_WORKSPACE_JSON="$workspace_json"
export QVOS_TEST_EVENTS="$events"

install -m 0644 /dev/stdin "$monitor_json" <<'JSON'
[{"name":"DP-1","width":1920,"height":1080,"refreshRate":60,"x":-1920,"y":0,"scale":1.25,"focused":true,"disabled":false}]
JSON
install -m 0644 /dev/stdin "$test_home/.config/hypr/monitors.conf" <<'CONFIG'
# Preserve this comment.
monitor = , preferred, auto, auto # adaptive
CONFIG
"$root/qvcore/desktop/hyprland/monitor-scaling-cycle"
assert_log 'monitors -j' "$hyprctl_log" "focused monitor query"
assert_log 'keyword monitor DP-1,1920x1080@60,-1920x0,1.6' \
  "$hyprctl_log" "scale change preserves exact placement"
grep -Fqx 'monitor = , preferred, auto, 1.6 # adaptive' \
  "$test_home/.config/hypr/monitors.conf" ||
  fail "adaptive scale persistence"
grep -Fqx '# Preserve this comment.' "$test_home/.config/hypr/monitors.conf" ||
  fail "monitor comment preservation"
[[ $(find "$test_home/.config/hypr" -maxdepth 1 -name 'monitors.conf.bak.*' | wc -l) == "1" ]] ||
  fail "singular monitor-config backup"
assert_log '-u low 󰍹    Display scaling set to 1.6x' \
  "$notification_log" "scale notification"

install -m 0644 /dev/stdin "$test_home/.config/hypr/monitors.conf" <<'CONFIG'
monitor=DP-1,1920x1080@60,-1920x0,1.25
CONFIG
backup_count=$(find "$test_home/.config/hypr" -maxdepth 1 -name 'monitors.conf.bak.*' | wc -l)
"$root/qvcore/desktop/hyprland/monitor-scaling-cycle" --reverse
assert_log 'keyword monitor DP-1,1920x1080@60,-1920x0,1' \
  "$hyprctl_log" "reverse scale change"
grep -Fqx 'monitor=DP-1,1920x1080@60,-1920x0,1.25' \
  "$test_home/.config/hypr/monitors.conf" ||
  fail "custom monitor layout preservation"
[[ $(find "$test_home/.config/hypr" -maxdepth 1 -name 'monitors.conf.bak.*' | wc -l) == "$backup_count" ]] ||
  fail "custom layout produced no backup"

install -m 0644 /dev/stdin "$monitor_json" <<'JSON'
[{"name":"DP-1","width":999999999999999999999999,"height":1080,"refreshRate":60,"x":0,"y":0,"scale":1,"focused":true,"disabled":false}]
JSON
: >"$hyprctl_log"
if "$root/qvcore/desktop/hyprland/monitor-scaling-cycle" 2>/dev/null; then
  fail "unbounded monitor geometry rejection"
fi
if grep -q '^keyword ' "$hyprctl_log"; then
  fail "invalid monitor geometry mutated Hyprland"
fi

install -m 0644 /dev/stdin "$monitor_json" <<'JSON'
[{"name":"DP-1","width":1920,"height":1080,"refreshRate":60,"x":0,"y":0,"scale":1,"focused":true,"disabled":false}]
JSON
install -m 0644 /dev/stdin "$test_home/.config/hypr/monitors.conf" <<'CONFIG'
monitor=,preferred,auto,auto
CONFIG
config_before=$(<"$test_home/.config/hypr/monitors.conf")
export QVOS_TEST_KEYWORD_FAIL=true
if "$root/qvcore/desktop/hyprland/monitor-scaling-cycle" 2>/dev/null; then
  fail "failed live scaling propagated as success"
fi
unset QVOS_TEST_KEYWORD_FAIL
[[ $(<"$test_home/.config/hypr/monitors.conf") == "$config_before" ]] ||
  fail "failed live scaling changed persisted config"

install -m 0644 /dev/stdin "$window_json" <<'JSON'
{"address":"0x1a2B","pinned":false}
JSON
: >"$hyprctl_log"
"$root/qvcore/desktop/hyprland/window-pop" 1110 700 -20 30
for command in \
  'dispatch togglefloating address:0x1a2B' \
  'dispatch resizeactive exact 1110 700 address:0x1a2B' \
  'dispatch moveactive -20 30 address:0x1a2B' \
  '-q --batch dispatch pin address:0x1a2B; dispatch alterzorder top address:0x1a2B; dispatch tagwindow +pop address:0x1a2B'; do
  assert_log "$command" "$hyprctl_log" "validated pop-out mutation: $command"
done

: >"$hyprctl_log"
if "$root/qvcore/desktop/hyprland/window-pop" 999999999999999999 700 2>/dev/null; then
  fail "unbounded pop-out geometry rejection"
fi
[[ ! -s $hyprctl_log ]] || fail "invalid pop-out geometry queried or mutated Hyprland"

install -m 0644 /dev/stdin "$window_json" <<'JSON'
{"address":"not-an-address","pinned":false}
JSON
: >"$hyprctl_log"
if "$root/qvcore/desktop/hyprland/window-transparency-toggle" 2>/dev/null; then
  fail "invalid focused-window address rejection"
fi
if grep -q '^dispatch ' "$hyprctl_log"; then
  fail "invalid focused-window address mutated Hyprland"
fi

install -m 0644 /dev/stdin "$window_json" <<'JSON'
{"address":"0x55","pinned":false}
JSON
: >"$hyprctl_log"
"$root/qvcore/desktop/hyprland/window-transparency-toggle"
assert_log 'dispatch setprop address:0x55 opaque toggle' \
  "$hyprctl_log" "validated transparency mutation"

install -m 0644 /dev/stdin "$workspace_json" <<'JSON'
{"id":7,"tiledLayout":"dwindle"}
JSON
: >"$hyprctl_log"
"$root/qvcore/desktop/hyprland/workspace-layout-toggle"
assert_log 'keyword workspace 7, layout:scrolling' \
  "$hyprctl_log" "validated workspace-layout mutation"

install -m 0644 /dev/stdin "$workspace_json" <<'JSON'
{"id":999999999999999999999999,"tiledLayout":"dwindle"}
JSON
: >"$hyprctl_log"
if "$root/qvcore/desktop/hyprland/workspace-layout-toggle" 2>/dev/null; then
  fail "unbounded workspace identifier rejection"
fi
if grep -q '^keyword ' "$hyprctl_log"; then
  fail "invalid workspace identifier mutated Hyprland"
fi

: >"$config_log"
"$source_fixture/qvcore/desktop/hyprland/window-gaps-toggle"
"$source_fixture/qvcore/desktop/hyprland/window-single-square-aspect-toggle"
assert_log 'hyprland-toggle:window-no-gaps' "$config_log" \
  "window-gap owner delegation"
assert_log 'hyprland-toggle:--enabled-notification       Enable single-window square aspect ratio --disabled-notification       Disable single-window square aspect ratio single-window-aspect-ratio' \
  "$config_log" "single-window-aspect owner delegation"

runtime_root="$test_root/runtime"
instance=qvos-test
install -d "$runtime_root/hypr/$instance"
install -m 0644 /dev/stdin "$events" <<'EVENTS'
workspace>>2
monitorremoved>>DP-1
monitorremovedv2>>1,DP-2,description
EVENTS
: >"$config_log"
XDG_RUNTIME_DIR="$runtime_root" \
  HYPRLAND_INSTANCE_SIGNATURE="$instance" \
  "$source_fixture/qvcore/desktop/hyprland/monitor-watch"
[[ $(grep -Fxc 'monitor-internal:recover' "$config_log") == "2" ]] ||
  fail "internal-monitor recovery count"
[[ $(grep -Fxc 'monitor-internal-mirror:recover' "$config_log") == "2" ]] ||
  fail "monitor-mirror recovery count"
assert_log "-U - UNIX-CONNECT:$runtime_root/hypr/$instance/.socket2.sock" \
  "$socket_log" "validated monitor-event socket"

for helper in \
  monitor-scaling-cycle \
  monitor-watch \
  window-gaps-toggle \
  window-pop \
  window-single-square-aspect-toggle \
  window-transparency-toggle \
  workspace-layout-toggle; do
  route_text=${helper//-/ }
  read -r -a route <<<"$route_text"
  "$root/bin/qv" hyprland "${route[@]}" --help 2>/dev/null |
    grep -F "qv-hyprland-$helper" >/dev/null ||
    fail "native CLI help route: $helper"
done

printf 'qvOS Hyprland controls tests passed.\n'
