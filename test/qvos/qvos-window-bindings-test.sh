#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
bindings="$root/qv/config/files/hypr/qv/bindings.conf"
tiling="$root/default/hypr/bindings/tiling-v2.conf"

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

assert_binding 'unbind = SUPER CTRL, F' "inherited tiled full screen override"
assert_binding 'bindd = SUPER SHIFT, F, Tiled full screen, fullscreenstate, 0 2' "tiled full screen binding"
assert_binding 'bindd = SUPER CTRL, F, Toggle window floating/tiling, togglefloating,' "toggle floating binding"
assert_binding 'bindd = SUPER SHIFT CTRL, F, Pop window out (float & pin), exec, omarchy-hyprland-window-pop' "pop window binding"
pass "the F family descends from full screen to advanced window states"

for binding in \
  'SUPER, T' \
  'SUPER, F' \
  'SUPER, O'; do
  if grep -Fqx "unbind = $binding" "$bindings"; then
    fail "qvOS suppresses inherited window control $binding"
  fi
done
grep -Fqx 'bindd = SUPER, T, Toggle window floating/tiling, togglefloating,' "$tiling" || fail "inherited toggle floating binding"
grep -Fqx 'bindd = SUPER, F, Full screen, fullscreen, 0' "$tiling" || fail "inherited full screen binding"
grep -Fqx 'bindd = SUPER CTRL, F, Tiled full screen, fullscreenstate, 0 2' "$tiling" || fail "inherited tiled full screen binding"
grep -Fqx 'bindd = SUPER, O, Pop window out (float & pin), exec, omarchy-hyprland-window-pop' "$tiling" || fail "inherited pop window binding"
pass "every inherited window-state capability remains available"

if grep -Eq '^bind[a-z]* = SUPER (ALT|SHIFT ALT), (A|W|D|S), .*resizeactive' "$bindings"; then
  fail "resize binding outside Super+Ctrl+Alt+WASD"
fi
pass "the resize layer uses only Super+Ctrl+Alt+WASD"

# Arrow family.
if grep -Eq '^(unbind|bind[a-z]*) = SUPER SHIFT, (LEFT|RIGHT|UP|DOWN),' "$bindings"; then
  fail "qvOS overrides inherited Super+Shift+Arrow swapping"
fi
pass "Super+Shift+Arrows remain Omarchy-owned window swapping"

grep -Fqx 'unbind = SUPER CTRL, LEFT' "$bindings" || fail "grouped focus left override"
grep -Fqx 'unbind = SUPER CTRL, RIGHT' "$bindings" || fail "grouped focus right override"
assert_binding 'bindd = SUPER CTRL, LEFT, Resize window left, resizeactive, -100 0' "arrow resize left binding"
assert_binding 'bindd = SUPER CTRL, UP, Resize window up, resizeactive, 0 -100' "arrow resize up binding"
assert_binding 'bindd = SUPER CTRL, RIGHT, Resize window right, resizeactive, 100 0' "arrow resize right binding"
assert_binding 'bindd = SUPER CTRL, DOWN, Resize window down, resizeactive, 0 100' "arrow resize down binding"
pass "Super+Ctrl+Arrows resize windows"

assert_binding 'bindd = SUPER SHIFT CTRL, LEFT, Move workspace to left monitor, movecurrentworkspacetomonitor, l' "arrow workspace left binding"
assert_binding 'bindd = SUPER SHIFT CTRL, UP, Move workspace to up monitor, movecurrentworkspacetomonitor, u' "arrow workspace up binding"
assert_binding 'bindd = SUPER SHIFT CTRL, RIGHT, Move workspace to right monitor, movecurrentworkspacetomonitor, r' "arrow workspace right binding"
assert_binding 'bindd = SUPER SHIFT CTRL, DOWN, Move workspace to down monitor, movecurrentworkspacetomonitor, d' "arrow workspace down binding"
pass "Super+Shift+Ctrl+Arrows moves workspaces between monitors"

for key in LEFT RIGHT UP DOWN; do
  if grep -Fqx "unbind = SUPER, $key" "$bindings"; then
    fail "qvOS suppresses inherited Super+$key focus"
  fi
done
pass "Super+Arrows focus remains Omarchy-owned"

if grep -Eq '^(unbind|bind[a-z]*) = SUPER (ALT|SHIFT ALT|CTRL ALT|SHIFT CTRL ALT), (LEFT|RIGHT|UP|DOWN),' "$bindings"; then
  fail "qvOS overrides an Alt+Arrow binding"
fi
pass "Alt+Arrows remain Omarchy-owned"

if grep -Eq '^unbind = SUPER( SHIFT)?, code:(20|21)$' "$bindings"; then
  fail "qvOS suppresses inherited punctuation resize binding"
fi

grep -Fqx 'bindd = SUPER, LEFT, Focus on left window, movefocus, l' "$tiling" || fail "upstream focus arrows"
grep -Fqx 'bindd = SUPER SHIFT, LEFT, Swap window to the left, swapwindow, l' "$tiling" || fail "upstream replaced swap arrows"
grep -Fqx 'bindd = SUPER CTRL, LEFT, Move grouped window focus left, changegroupactive, b' "$tiling" || fail "upstream replaced grouped focus"
grep -Fqx 'bindd = SUPER ALT, LEFT, Move window to group on left, moveintogroup, l' "$tiling" || fail "upstream group movement arrows"
grep -Fqx 'bindd = SUPER SHIFT ALT, LEFT, Move workspace to left monitor, movecurrentworkspacetomonitor, l' "$tiling" || fail "upstream monitor movement arrows"
grep -Fq 'bindd = SUPER, code:20, Expand window left, resizeactive, -100 0' "$tiling" || fail "upstream resize punctuation"
pass "the intended Omarchy arrow and punctuation bindings remain upstream-owned"

duplicates=$(
  sed -nE 's/^bindd = ([^,]+), ([^,]+),.*/\1,\2/p' "$bindings" |
    sort |
    uniq -d
)
[[ -z $duplicates ]] || fail "duplicate qvOS binding: $duplicates"
pass "qvOS bindings contain no duplicate modifier and key pairs"
