#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bindings="$root/config/hypr/qv/bindings.conf"
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

assert_binding 'bindd = SUPER SHIFT, A, Focus left, movefocus, l' "focus left binding"
assert_binding 'bindd = SUPER SHIFT, W, Focus up, movefocus, u' "focus up binding"
assert_binding 'bindd = SUPER SHIFT, D, Focus right, movefocus, r' "focus right binding"
assert_binding 'bindd = SUPER SHIFT, S, Focus down, movefocus, d' "focus down binding"
pass "Super+Shift+WASD moves focus"

assert_binding 'bindd = SUPER ALT, A, Swap window left, swapwindow, l' "swap left binding"
assert_binding 'bindd = SUPER ALT, W, Swap window up, swapwindow, u' "swap up binding"
assert_binding 'bindd = SUPER ALT, D, Swap window right, swapwindow, r' "swap right binding"
assert_binding 'bindd = SUPER ALT, S, Swap window down, swapwindow, d' "swap down binding"
pass "Super+Alt+WASD swaps windows"

assert_binding 'bindd = SUPER CTRL ALT, A, Resize window left, resizeactive, -100 0' "resize left binding"
assert_binding 'bindd = SUPER CTRL ALT, W, Resize window up, resizeactive, 0 -100' "resize up binding"
assert_binding 'bindd = SUPER CTRL ALT, D, Resize window right, resizeactive, 100 0' "resize right binding"
assert_binding 'bindd = SUPER CTRL ALT, S, Resize window down, resizeactive, 0 100' "resize down binding"
pass "Super+Ctrl+Alt+WASD resizes windows"

for key in LEFT RIGHT UP DOWN; do
  if grep -Fqx "unbind = SUPER, $key" "$bindings" ||
    grep -Fqx "unbind = SUPER SHIFT, $key" "$bindings"; then
    fail "qvOS suppresses inherited arrow binding $key"
  fi
done

if grep -Eq '^unbind = SUPER( SHIFT)?, code:(20|21)$' "$bindings"; then
  fail "qvOS suppresses inherited punctuation resize binding"
fi

grep -Fqx 'bindd = SUPER, LEFT, Focus on left window, movefocus, l' "$tiling" || fail "upstream focus arrows"
grep -Fqx 'bindd = SUPER SHIFT, LEFT, Swap window to the left, swapwindow, l' "$tiling" || fail "upstream swap arrows"
grep -Fq 'bindd = SUPER, code:20, Expand window left, resizeactive, -100 0' "$tiling" || fail "upstream resize punctuation"
pass "the original arrow and punctuation spatial bindings remain upstream-owned"

duplicates=$(
  sed -nE 's/^bindd = ([^,]+), ([^,]+),.*/\1,\2/p' "$bindings" |
    sort |
    uniq -d
)
[[ -z $duplicates ]] || fail "duplicate qvOS binding: $duplicates"
pass "qvOS bindings contain no duplicate modifier and key pairs"
