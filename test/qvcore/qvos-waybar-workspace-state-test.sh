#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
test_home="$test_root/home"
workspaces="$test_root/workspaces.json"
clients="$test_root/clients.json"
monitors="$test_root/monitors.json"
style="$test_home/.config/waybar/workspace-state.css"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$test_home"
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'STUB'
#!/bin/bash
case $* in
"-j workspaces") cat "$QVOS_TEST_WORKSPACES" ;;
"-j clients") cat "$QVOS_TEST_CLIENTS" ;;
"-j monitors") cat "$QVOS_TEST_MONITORS" ;;
*) exit 2 ;;
esac
STUB

cat >"$workspaces" <<'JSON'
[
  {"id": 10, "name": "10", "monitor": "eDP-1", "windows": 1},
  {"id": 3, "name": "3", "monitor": "eDP-1", "windows": 1},
  {"id": 1, "name": "1", "monitor": "eDP-1", "windows": 1},
  {"id": 4, "name": "4", "monitor": "DP-1", "windows": 1},
  {"id": -1338, "name": "G", "monitor": "eDP-1", "windows": 1},
  {"id": 2, "name": "2", "monitor": "eDP-1", "windows": 0}
]
JSON
cat >"$clients" <<'JSON'
[
  {"address": "0xaaa", "workspace": {"id": 1}},
  {"address": "0xbbb", "workspace": {"id": 3}},
  {"address": "0xccc", "workspace": {"id": 10}},
  {"address": "0xddd", "workspace": {"id": -1338}},
  {"address": "0xeee", "workspace": {"id": 4}}
]
JSON
cat >"$monitors" <<'JSON'
[
  {
    "name": "eDP-1",
    "activeWorkspace": {"id": 1},
    "specialWorkspace": {"id": 0}
  },
  {
    "name": "DP-1",
    "activeWorkspace": {"id": 4},
    "specialWorkspace": {"id": 0}
  }
]
JSON

run_state() {
  HOME="$test_home" PATH="$test_bin:/usr/bin" \
    QVOS_TEST_WORKSPACES="$workspaces" \
    QVOS_TEST_CLIENTS="$clients" \
    QVOS_TEST_MONITORS="$monitors" \
    "$root/qvcore/waybar/workspace-state" "$@"
}

run_state --once
grep -Fqx \
  'window#waybar.eDP-1 #workspaces button:nth-child(3):not(.active) { color: @foreground; opacity: 0.6; }' \
  "$style" || fail "occupied workspace brightness"
grep -Fqx \
  'window#waybar.eDP-1 #workspaces button:nth-child(4):not(.active) { color: @foreground; opacity: 0.6; }' \
  "$style" || fail "two-digit workspace coordinate order"
grep -Fqx \
  'window#waybar.eDP-1 #workspaces button:nth-child(5):not(.active) { color: @foreground; opacity: 0.6; }' \
  "$style" || fail "named workspace follows numeric coordinates"
grep -Fqx \
  'window#waybar.DP-1 #workspaces button:nth-child(1):not(.active) { color: @foreground; opacity: 0.6; }' \
  "$style" || fail "multi-monitor workspace selector"

for event in \
  'urgent>>bbb' \
  'bell>>bbb' \
  'windowtitlev2>>bbb,New title' \
  'openwindow>>bbb,3,app,New window' \
  'movewindowv2>>bbb,3,3'; do
  printf '%s\n' "$event" | run_state --events
  grep -Fqx \
    'window#waybar.eDP-1 #workspaces button:nth-child(3):not(.active) { color: @bright; opacity: 0.9; }' \
    "$style" || fail "attention event: ${event%%>>*}"
done

printf '%s\n' 'urgent>>bbb' 'workspacev2>>3,3' | run_state --events
grep -Fqx \
  'window#waybar.eDP-1 #workspaces button:nth-child(3):not(.active) { color: @foreground; opacity: 0.6; }' \
  "$style" || fail "visited workspace clears attention"

printf 'not-json\n' >"$workspaces"
before=$(sha256sum "$style")
if run_state --once >/dev/null 2>&1; then
  fail "malformed Hyprland state accepted"
fi
[[ $(sha256sum "$style") == "$before" ]] ||
  fail "malformed state changed the last valid style"

session_root="$test_root/session-runtime"
session_log="$test_root/session.log"
tracker_pid_file="$test_root/tracker.pid"
install -D -m 0755 "$root/qvcore/waybar/session" "$session_root/session"
install -m 0755 /dev/stdin "$session_root/workspace-state" <<'STUB'
#!/bin/bash
printf '%s\n' "$1" >>"$QVOS_TEST_SESSION_LOG"
if [[ $1 == "--watch" ]]; then
  printf '%s\n' "$$" >"$QVOS_TEST_TRACKER_PID_FILE"
  sleep 30
fi
STUB
install -m 0755 /dev/stdin "$test_bin/waybar" <<'STUB'
#!/bin/bash
printf 'waybar\n' >>"$QVOS_TEST_SESSION_LOG"
exit 7
STUB
set +e
QVOS_TEST_SESSION_LOG="$session_log" \
QVOS_TEST_TRACKER_PID_FILE="$tracker_pid_file" \
PATH="$test_bin:/usr/bin" "$session_root/session"
session_status=$?
set -e
((session_status == 7)) || fail "Waybar session exit propagation"
mapfile -t session_events <"$session_log"
((${#session_events[@]} == 3)) || fail "Waybar session event count"
[[ ${session_events[0]} == "--once" ]] || fail "Waybar state initialization order"
[[ $(printf '%s\n' "${session_events[@]:1}" | sort) == $'--watch\nwaybar' ]] ||
  fail "Waybar session child inventory"
tracker_pid=$(<"$tracker_pid_file")
if kill -0 "$tracker_pid" 2>/dev/null; then
  fail "Waybar session left its workspace listener running"
fi

printf 'ok - qvOS workspace state distinguishes empty, occupied, and attention states\n'
