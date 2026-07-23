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

assert_binding 'bindd = SUPER, B, Default browser, exec, omarchy-launch-browser' "default browser binding"
assert_binding 'bindd = SUPER SHIFT, B, Private default browser, exec, omarchy-launch-browser --private' "private default browser binding"
pass "the browser family follows the Omarchy default"

assert_binding 'bindd = SUPER CTRL, E, Default editor, exec, omarchy-launch-editor' "default editor binding"
assert_binding 'bindd = SUPER SHIFT CTRL, E, Default editor here, exec, ~/.local/share/qvos/hyprland/qvos-launch-editor-here' "contextual default editor binding"
pass "the E family follows the Omarchy editor default"

assert_binding 'bindd = SUPER, X, Default terminal, exec, uwsm-app -- xdg-terminal-exec' "default terminal binding"
assert_binding 'bindd = SUPER SHIFT, X, Default terminal here, exec, ~/.local/share/qvos/hyprland/qvos-launch-terminal-here terminal' "contextual default terminal binding"
pass "the X family follows the Omarchy terminal default"

assert_binding 'bindd = SUPER CTRL, X, Tmux, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/hyprland/qvos-tmux last' "tmux resume binding"
assert_binding 'bindd = SUPER SHIFT CTRL, X, Tmux manager, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/hyprland/qvos-tmux manager' "tmux manager binding"
pass "the X family owns tmux"

if grep -Eqi '^bindd = SUPER( SHIFT)?, (RETURN|backslash|N),' "$bindings"; then
  fail "retired qvOS terminal, tmux, or editor family"
fi

if grep -Eqi '^bindd = SUPER( SHIFT)?, B, .*(brave|chromium|firefox)|^bindd = SUPER( SHIFT)?, X, .*(alacritty|foot|ghostty|kitty)|^bindd = SUPER( SHIFT)? CTRL, E, .*(code|cursor|zeditor|nvim)' "$bindings"; then
  fail "hardcoded default application"
fi
pass "default-app bindings contain no concrete application choice"
