#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bindings="$root/config/hypr/qv/bindings.conf"
legacy_bindings="$root/default/hypr/bindings.conf"

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
assert_binding 'bindd = SUPER, Z, Default browser, exec, omarchy-launch-browser' "Z default browser binding"
assert_binding 'bindd = SUPER SHIFT, Z, Private default browser, exec, omarchy-launch-browser --private' "Z private default browser binding"
assert_binding 'bindd = SUPER CTRL, Z, Default browser, exec, omarchy-launch-browser' "Z alternate default browser binding"
pass "the B and Z browser families follow the Omarchy default"

assert_binding 'bindd = SUPER CTRL, E, Default editor, exec, omarchy-launch-editor' "default editor binding"
assert_binding 'bindd = SUPER SHIFT CTRL, E, Default editor here, exec, ~/.local/share/qvos/hyprland/qvos-launch-editor-here' "contextual default editor binding"
pass "the E family follows the Omarchy editor default"

assert_binding 'bindd = SUPER, X, Default terminal, exec, uwsm-app -- xdg-terminal-exec' "default terminal binding"
assert_binding 'bindd = SUPER SHIFT, X, Default terminal here, exec, ~/.local/share/qvos/hyprland/qvos-launch-terminal-here terminal' "contextual default terminal binding"
pass "the X family follows the Omarchy terminal default"

assert_binding 'bindd = SUPER CTRL, X, Tmux, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/hyprland/qvos-tmux last' "tmux resume binding"
assert_binding 'bindd = SUPER SHIFT CTRL, X, Tmux manager, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/hyprland/qvos-tmux manager' "tmux manager binding"
pass "the X family owns tmux"

assert_binding 'bindd = SUPER, RETURN, Default terminal, exec, uwsm-app -- xdg-terminal-exec' "Return default terminal binding"
assert_binding 'bindd = SUPER SHIFT, RETURN, Default terminal here, exec, ~/.local/share/qvos/hyprland/qvos-launch-terminal-here terminal' "Return contextual default terminal binding"
assert_binding 'bindd = SUPER CTRL, RETURN, Tmux, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/hyprland/qvos-tmux last' "Return tmux binding"
assert_binding 'bindd = SUPER SHIFT CTRL, RETURN, Tmux manager, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/hyprland/qvos-tmux manager' "Return tmux manager binding"
pass "the Return family mirrors X"

if grep -Eqi '^bindd = SUPER( SHIFT)?, (backslash|N),' "$bindings"; then
  fail "retired qvOS tmux or editor family"
fi

grep -Fqx 'bindd = SUPER, N, Editor, exec, omarchy-launch-editor' "$legacy_bindings" || fail "legacy editor binding"

if grep -Eqi '^bindd = .*exec, .*(brave-browser|brave-origin-beta|chromium|firefox|google-chrome|microsoft-edge|alacritty|foot|ghostty|kitty|code-oss|cursor|zeditor|nvim|helix|sublime_text|emacs)([[:space:]]|$)' "$bindings" "$legacy_bindings"; then
  fail "hardcoded default application"
fi
pass "all default-app bindings contain no concrete application choice"
