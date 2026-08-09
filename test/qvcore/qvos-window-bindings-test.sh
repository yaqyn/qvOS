#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
bindings="$root/qvcore/config/files/hypr/bindings.conf"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_binding() {
  grep -Fqx "$1" "$bindings" || fail "$2"
}

"$root/qvcore/config/check"

assert_binding 'bindd = SUPER ALT, A, Focus left, movefocus, l' "focus left binding"
assert_binding 'bindd = SUPER ALT, W, Focus up, movefocus, u' "focus up binding"
assert_binding 'bindd = SUPER ALT, D, Focus right, movefocus, r' "focus right binding"
assert_binding 'bindd = SUPER ALT, S, Focus down, movefocus, d' "focus down binding"
pass "Super+Alt+WASD moves focus"

assert_binding 'bindd = SUPER CTRL ALT, A, Resize window left, resizeactive, -100 0' "resize left binding"
assert_binding 'bindd = SUPER CTRL ALT, W, Resize window up, resizeactive, 0 -100' "resize up binding"
assert_binding 'bindd = SUPER CTRL ALT, D, Resize window right, resizeactive, 100 0' "resize right binding"
assert_binding 'bindd = SUPER CTRL ALT, S, Resize window down, resizeactive, 0 100' "resize down binding"
pass "Super+Ctrl+Alt+WASD resizes windows"

assert_binding 'bindd = SUPER SHIFT ALT, A, Swap window left, swapwindow, l' "swap left binding"
assert_binding 'bindd = SUPER SHIFT ALT, W, Swap window up, swapwindow, u' "swap up binding"
assert_binding 'bindd = SUPER SHIFT ALT, D, Swap window right, swapwindow, r' "swap right binding"
assert_binding 'bindd = SUPER SHIFT ALT, S, Swap window down, swapwindow, d' "swap down binding"
pass "Super+Shift+Alt+WASD swaps windows"

assert_binding 'bindd = SUPER SHIFT CTRL ALT, A, Move workspace to left monitor, movecurrentworkspacetomonitor, l' "move workspace left binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, W, Move workspace to up monitor, movecurrentworkspacetomonitor, u' "move workspace up binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, D, Move workspace to right monitor, movecurrentworkspacetomonitor, r' "move workspace right binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, S, Move workspace to down monitor, movecurrentworkspacetomonitor, d' "move workspace down binding"
pass "Super+Shift+Ctrl+Alt+WASD moves workspaces between monitors"

assert_binding 'bindd = SUPER, F, Full screen, fullscreen, 0' "full screen binding"
assert_binding 'bindd = SUPER SHIFT, F, Tiled full screen, fullscreenstate, 0 2' "tiled full screen binding"
assert_binding 'bindd = SUPER CTRL, F, Toggle window floating/tiling, togglefloating,' "toggle floating binding"
assert_binding 'bindd = SUPER SHIFT CTRL, F, Pop window out (float & pin), exec, qv-hyprland-window-pop' "pop window binding"
assert_binding 'bindd = SUPER ALT, F, Full width, fullscreen, 1' "full-width binding"
if grep -Eq '^bind[a-z]* = SUPER, (T|O),' "$bindings"; then
  fail "redundant legacy window-state alias"
fi
pass "the F family singularly owns every retained window state"

for line in \
  'bindd = SUPER, L, Toggle workspace layout, exec, qv-hyprland-workspace-layout-toggle' \
  'bindd = SUPER, code:61, Cycle monitor scaling, exec, qv-hyprland-monitor-scaling-cycle' \
  'bindd = SUPER ALT, code:61, Cycle monitor scaling backwards, exec, qv-hyprland-monitor-scaling-cycle --reverse' \
  'bindd = SUPER, BACKSPACE, Toggle window transparency, exec, qv-hyprland-window-transparency-toggle' \
  'bindd = SUPER SHIFT, BACKSPACE, Toggle window gaps, exec, qv-hyprland-window-gaps-toggle' \
  'bindd = SUPER CTRL, BACKSPACE, Toggle single-window square aspect, exec, qv-hyprland-window-single-square-aspect-toggle'; do
  assert_binding "$line" "native Hyprland control binding: $line"
done
pass "native qvOS routes own interactive Hyprland controls"

if grep -Eq '^bind[a-z]* = SUPER (ALT|SHIFT ALT), (A|W|D|S), .*resizeactive' "$bindings"; then
  fail "resize binding outside Super+Ctrl+Alt+WASD"
fi
pass "the resize layer uses only Super+Ctrl+Alt+WASD"

for line in \
  'bindd = SUPER, LEFT, Focus on left window, movefocus, l' \
  'bindd = SUPER SHIFT, LEFT, Swap window to the left, swapwindow, l' \
  'bindd = SUPER CTRL, LEFT, Resize window left, resizeactive, -100 0' \
  'bindd = SUPER SHIFT CTRL, LEFT, Move workspace to left monitor, movecurrentworkspacetomonitor, l' \
  'bindd = SUPER ALT, LEFT, Move window to group on left, moveintogroup, l' \
  'bindd = SUPER SHIFT ALT, LEFT, Move workspace to left monitor, movecurrentworkspacetomonitor, l' \
  'bindd = SUPER, code:20, Expand window left, resizeactive, -100 0 # - key'; do
  assert_binding "$line" "native spatial binding: $line"
done
pass "arrow and punctuation controls are native qvOS bindings"

if grep -Eq '^[[:space:]]*unbind[[:space:]]*=' "$bindings"; then
  fail "native binding source contains an overlay unbind"
fi
pass "native qvOS bindings require no override directives"
