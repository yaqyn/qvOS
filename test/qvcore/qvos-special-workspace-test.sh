#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$root/qvcore/desktop/hyprland/qvos-toggle-special-window"
bindings="$root/config/hypr/bindings.conf"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
dispatch_log="$test_root/dispatch"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash

case $1 in
activewindow)
  printf '%s\n' "${QVOS_TEST_ACTIVE_WINDOW:-}"
  ;;
monitors)
  printf '%s\n' "${QVOS_TEST_MONITORS:-[]}"
  ;;
dispatch)
  printf '%s\n' "$*" >>"$QVOS_TEST_DISPATCH_LOG"
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash

exit 0
SCRIPT

run_helper() {
  : >"$dispatch_log"
  QVOS_TEST_ACTIVE_WINDOW="$1" \
    QVOS_TEST_MONITORS="$2" \
    QVOS_TEST_DISPATCH_LOG="$dispatch_log" \
    PATH="$test_bin:/usr/bin" \
    "$helper"
}

assert_dispatches() {
  local expected="$1"

  [[ "$(<"$dispatch_log")" == "$expected" ]] || fail "$2"
}

normal_window='{"address":"0x123","workspace":{"name":"1"}}'
special_window='{"address":"0x123","workspace":{"name":"special:scratchpad"}}'
special_closed='[{"focused":true,"activeWorkspace":{"name":"1"},"specialWorkspace":{"name":""}}]'
special_open='[{"focused":true,"activeWorkspace":{"name":"1"},"specialWorkspace":{"name":"special:scratchpad"}}]'

run_helper "$normal_window" "$special_closed"
assert_dispatches $'dispatch movetoworkspacesilent special:scratchpad,address:0x123\ndispatch togglespecialworkspace scratchpad\ndispatch focuswindow address:0x123' "move in and open special workspace"
pass "moving a window in opens special and restores its focus"

run_helper "$normal_window" "$special_open"
assert_dispatches $'dispatch movetoworkspacesilent special:scratchpad,address:0x123\ndispatch focuswindow address:0x123' "move into visible special workspace"
pass "an already-visible special workspace is not toggled closed"

run_helper "$special_window" "$special_open"
assert_dispatches $'dispatch movetoworkspacesilent 1,address:0x123\ndispatch togglespecialworkspace scratchpad\ndispatch focuswindow address:0x123' "move out and close special workspace"
pass "moving a window out closes special and restores its focus"

if run_helper '{"address":"0x0","workspace":{"name":"1"}}' "$special_closed" >/dev/null 2>&1; then
  fail "missing active window"
fi
[[ ! -s $dispatch_log ]] || fail "dispatch without active window"
pass "a missing active window cannot change workspace state"

grep -Fqx 'bindd = SUPER CTRL, SPACE, Theme background menu, exec, qv-menu background' "$bindings" ||
  fail "native background picker"
grep -Fqx 'bindd = SUPER, S, Toggle scratchpad, togglespecialworkspace, scratchpad' "$bindings" ||
  fail "native special workspace toggle"
grep -Fqx 'bindd = SUPER CTRL, S, Move window in or out of special workspace, exec, ~/.local/lib/qvos/desktop/hyprland/qvos-toggle-special-window' "$bindings" ||
  fail "special window transfer binding"
pass "the native qvOS map owns background and special workspace controls"
