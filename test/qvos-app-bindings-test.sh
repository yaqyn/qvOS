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
assert_binding 'bindd = SUPER SHIFT, Q, Proton Drive, exec, omarchy-launch-webapp "https://drive.proton.me"' "Proton Drive binding"
assert_binding 'bindd = SUPER CTRL, Q, Proton Pass, exec, omarchy-launch-webapp "https://pass.proton.me"' "Proton Pass binding"
assert_binding 'bindd = SUPER SHIFT CTRL, Q, Proton Account, exec, omarchy-launch-webapp "https://account.proton.me"' "Proton Account binding"
assert_binding 'bindd = SUPER ALT, Q, Proton Docs, exec, omarchy-launch-webapp "https://docs.proton.me"' "Proton Docs binding"
assert_binding 'bindd = SUPER SHIFT ALT, Q, Proton Meet, exec, omarchy-launch-webapp "https://meet.proton.me"' "Proton Meet binding"
assert_binding 'bindd = SUPER CTRL ALT, Q, Proton Calendar, exec, omarchy-launch-webapp "https://calendar.proton.me"' "Proton Calendar binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, Q, Proton Account Settings, exec, omarchy-launch-webapp "https://account.proton.me/u/1/dashboard"' "Proton Account Settings binding"
pass "the Q family owns all selected Proton apps"

assert_binding 'unbind = SUPER CTRL, A' "inherited audio binding override"
assert_binding 'unbind = SUPER CTRL, S' "inherited Share binding override"
assert_binding 'unbind = SUPER CTRL ALT, W' "inherited Weather binding override"
assert_binding 'bindd = SUPER, A, ChatGPT, exec, omarchy-launch-webapp "https://chatgpt.com"' "ChatGPT binding"
assert_binding 'bindd = SUPER CTRL, A, Brave Ask, exec, omarchy-launch-webapp "https://search.brave.com/ask"' "Brave Ask binding"
assert_binding 'bindd = SUPER SHIFT CTRL, A, Codex YOLO here, exec, ~/.local/share/qvos/hyprland/qvos-launch-terminal-here codex-yolo' "contextual Codex YOLO binding"
pass "the A family owns daily AI tools"

assert_binding 'bindd = SUPER SHIFT CTRL, W, Audio controls, exec, omarchy-launch-audio' "audio binding"
if grep -Eq '^(unbind|bindd) = SUPER CTRL, W,' "$bindings"; then
  fail "qvOS overrides inherited Wifi"
fi
pass "the W family inherits Wifi and adds Audio"

assert_binding 'bindd = SUPER, D, Localhost, exec, ~/.local/share/qvos/hyprland/qvos-localhost-open' "Localhost binding"
assert_binding 'bindd = SUPER CTRL, D, Cloudflare, exec, omarchy-launch-webapp "https://dash.cloudflare.com"' "Cloudflare binding"
assert_binding 'bindd = SUPER SHIFT CTRL, D, GitHub, exec, omarchy-launch-webapp "https://github.com"' "GitHub binding"
pass "the D family owns developer destinations"

assert_binding 'bindd = SUPER, S, Discord, exec, omarchy-launch-webapp "https://discord.com/app"' "Discord binding"
assert_binding 'bindd = SUPER CTRL, S, Telegram, exec, omarchy-launch-webapp "https://web.telegram.org/"' "Telegram binding"
assert_binding 'bindd = SUPER SHIFT CTRL, S, WhatsApp, exec, omarchy-launch-webapp "https://web.whatsapp.com/"' "WhatsApp binding"
pass "the S family owns communication apps"

if grep -Eq '^bindd = SUPER( SHIFT)?, (M|P),|^bindd = SUPER SHIFT, C,' "$bindings" ||
  grep -Eq '^bindd = SUPER (SHIFT|SHIFT CTRL), Q, Proton (Calendar|Meet),' "$bindings" ||
  grep -Eq '^bindd = SUPER( SHIFT)?, D, Proton (Drive|Docs),' "$bindings"; then
  fail "retired Proton route"
fi

if grep -Eq '^bindd = SUPER SHIFT, A, Lumo,|^bindd = SUPER SHIFT CTRL, A, Brave Ask,' "$bindings" ||
  grep -Eq '^bindd = SUPER SHIFT, W, Wifi controls,|^bindd = SUPER CTRL, W, Audio controls,|^bindd = SUPER SHIFT CTRL, W, Btop,|^bindd = SUPER ALT, W, Bluetooth controls,' "$bindings" ||
  grep -Eq '^bindd = SUPER( SHIFT)?, S, Codex|^bindd = SUPER ALT, L, Localhost,' "$bindings"; then
  fail "retired application or control route"
fi

if grep -Eq 'Proton Wallet|Codex Docs|Lumo' "$bindings"; then
  fail "retired app action"
fi
pass "retired app and control routes stay absent"
