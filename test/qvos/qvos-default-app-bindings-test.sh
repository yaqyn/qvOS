#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
bindings="$root/config/hypr/bindings.conf"

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
assert_binding 'bindd = SUPER CTRL, B, Private default browser, exec, omarchy-launch-browser --private' "private default browser binding"
assert_binding 'bindd = SUPER, Z, Default browser, exec, omarchy-launch-browser' "Z default browser binding"
assert_binding 'bindd = SUPER SHIFT, Z, Dev browser (Chromium), exec, uwsm-app -- chromium' "Chromium dev browser binding"
assert_binding 'bindd = SUPER CTRL, Z, Private default browser, exec, omarchy-launch-browser --private' "Z private default browser binding"
pass "the default and private B/Z routes follow the qvOS default"

assert_binding 'bindd = SUPER SHIFT, E, Default editor, exec, omarchy-launch-editor' "default editor binding"
assert_binding 'bindd = SUPER SHIFT CTRL, E, Default editor here, exec, ~/.local/share/qvos/desktop/context/qvos-launch-editor-here' "contextual default editor binding"
pass "the E family follows the qvOS editor default"

assert_binding 'bindd = SUPER, X, Default terminal, exec, uwsm-app -- xdg-terminal-exec' "default terminal binding"
assert_binding 'bindd = SUPER CTRL, X, Default terminal here, exec, ~/.local/share/qvos/desktop/context/qvos-launch-terminal-here terminal' "contextual default terminal binding"
pass "the X family follows the qvOS terminal default"

assert_binding 'bindd = SUPER SHIFT, X, Tmux, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/tmux/qvos-tmux last' "tmux resume binding"
assert_binding 'bindd = SUPER SHIFT CTRL, X, Tmux manager, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/tmux/qvos-tmux manager' "tmux manager binding"
pass "the X family owns tmux"

assert_binding 'bindd = SUPER, RETURN, Default terminal, exec, uwsm-app -- xdg-terminal-exec' "Return default terminal binding"
assert_binding 'bindd = SUPER SHIFT, RETURN, Tmux, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/tmux/qvos-tmux last' "Return tmux binding"
assert_binding 'bindd = SUPER CTRL, RETURN, Default terminal here, exec, ~/.local/share/qvos/desktop/context/qvos-launch-terminal-here terminal' "Return contextual default terminal binding"
assert_binding 'bindd = SUPER SHIFT CTRL, RETURN, Tmux manager, exec, uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/share/qvos/tmux/qvos-tmux manager' "Return tmux manager binding"
pass "the Return family mirrors X"

if grep -Eqi '^bindd = SUPER( SHIFT)?, (backslash|N),' "$bindings"; then
  fail "retired qvOS tmux or editor family"
fi

if grep -Fvx 'bindd = SUPER SHIFT, Z, Dev browser (Chromium), exec, uwsm-app -- chromium' "$bindings" |
  grep -Eqi '^bindd = .*exec, .*(brave-browser|brave-origin-beta|chromium|firefox|google-chrome|microsoft-edge|alacritty|foot|ghostty|kitty|code-oss|cursor|zeditor|nvim|helix|sublime_text|emacs)([[:space:]]|$)'; then
  fail "hardcoded default application"
fi
pass "default-app bindings are dynamic except for the Chromium dev browser"
