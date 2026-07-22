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

assert_binding 'bindd = SUPER, N, Default editor, exec, omarchy-launch-editor' "default editor binding"
assert_binding 'bindd = SUPER SHIFT, N, Default editor here, exec, ~/.local/share/qvos/hyprland/qvos-launch-editor-here' "contextual default editor binding"
pass "the editor family follows the Omarchy default"

assert_binding 'bindd = SUPER, RETURN, Default terminal, exec, uwsm-app -- xdg-terminal-exec' "default terminal binding"
assert_binding 'bindd = SUPER SHIFT, RETURN, Default terminal here, exec, ~/.local/share/qvos/hyprland/qvos-launch-terminal-here terminal' "contextual default terminal binding"
pass "the terminal family follows the Omarchy default"

assert_binding 'bindd = SUPER, backslash, Tmux, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/hyprland/qvos-tmux last' "tmux resume binding"
assert_binding 'bindd = SUPER SHIFT, backslash, Tmux manager, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/hyprland/qvos-tmux manager' "tmux manager binding"
pass "the backslash family owns tmux"

if grep -Eq '^bindd = SUPER( SHIFT)? CTRL, RETURN, (Tmux|Tmux manager),' "$bindings"; then
  fail "retired Ctrl+Return tmux binding"
fi

if grep -Eqi '^bindd = SUPER( SHIFT)?, (B|N|RETURN), .*(brave|chromium|firefox|alacritty|foot|ghostty|kitty|code|cursor|zeditor|nvim)' "$bindings"; then
  fail "hardcoded default application"
fi
pass "default-app bindings contain no concrete application choice"
