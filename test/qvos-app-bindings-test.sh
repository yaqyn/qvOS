#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bindings="$root/config/hypr/qv/bindings.conf"

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

assert_binding 'bindd = SUPER, Q, Proton Mail, exec, omarchy-launch-webapp "https://mail.proton.me"' "Proton Mail binding"
assert_binding 'bindd = SUPER SHIFT, Q, Proton Calendar, exec, omarchy-launch-webapp "https://calendar.proton.me"' "Proton Calendar binding"
assert_binding 'bindd = SUPER SHIFT CTRL, Q, Proton Meet, exec, omarchy-launch-webapp "https://meet.proton.me"' "Proton Meet binding"
assert_binding 'bindd = SUPER SHIFT, W, Proton Pass, exec, omarchy-launch-webapp "https://pass.proton.me"' "Proton Pass binding"
pass "the Q family and Shift+W own the selected Proton apps"

assert_binding "bindd = SUPER, S, Codex YOLO, exec, ~/.local/share/qvos/hyprland/qvos-launch-terminal-here codex-yolo \"\$HOME\"" "Codex YOLO binding"
assert_binding 'bindd = SUPER SHIFT, S, Codex YOLO here, exec, ~/.local/share/qvos/hyprland/qvos-launch-terminal-here codex-yolo' "contextual Codex YOLO binding"
pass "the S family owns Codex YOLO"

assert_binding 'bindd = SUPER SHIFT CTRL, A, Brave Ask, exec, omarchy-launch-webapp "https://search.brave.com/ask"' "Brave Ask binding"
pass "Brave Ask uses Shift+Ctrl+A"

if grep -Eq '^bindd = SUPER( SHIFT)?, (M|P),|^bindd = SUPER SHIFT, C,' "$bindings"; then
  fail "retired Proton app binding"
fi

if grep -Eq 'Proton Wallet|Codex Docs|^bindd = SUPER( SHIFT)? CTRL, A, Codex' "$bindings"; then
  fail "retired app action"
fi
pass "retired app bindings stay absent"
