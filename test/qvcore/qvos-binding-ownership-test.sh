#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
bindings="$root/qvcore/config/files/hypr/bindings.lua"
# shellcheck source=test/qvcore/hyprland-bindings.sh
source "$root/test/qvcore/hyprland-bindings.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

"$root/qvcore/config/check"

for binding in \
  'bindd = SUPER, C, Universal copy, sendshortcut, CTRL, Insert, activewindow' \
  'bindd = SUPER, F, Full screen, fullscreen, 0' \
  'bindd = SUPER, S, Toggle scratchpad, togglespecialworkspace, scratchpad' \
  'bindd = SUPER, code:10, Switch to workspace 1, workspace, 1' \
  'bindeld = , XF86AudioRaiseVolume, Volume up, exec, qv-swayosd-client --output-volume raise'; do
  qvos_assert_lua_binding "$bindings" "$binding" ||
    fail "retained native capability: $binding"
done

if rg -q 'Omarchy|upstream-owned|Omarchy-owned' "$bindings"; then
  fail "native binding source still describes an inherited owner"
fi

printf 'ok - qvOS owns one complete binding source with retained desktop capabilities\n'
