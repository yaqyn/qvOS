#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
bindings="$root/config/hypr/bindings.conf"
packages=$("$root/qv/install/packaging/resolve" base)

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
assert_binding 'bindd = SUPER CTRL, Q, Proton Meet, exec, omarchy-launch-webapp "https://meet.proton.me"' "Proton Meet binding"
assert_binding 'bindd = SUPER SHIFT CTRL, Q, Proton Docs, exec, omarchy-launch-webapp "https://docs.proton.me"' "Proton Docs binding"
assert_binding 'bindd = SUPER ALT, Q, Proton Pass, exec, omarchy-launch-webapp "https://pass.proton.me"' "Proton Pass binding"
assert_binding 'bindd = SUPER SHIFT ALT, Q, Proton Lumo, exec, omarchy-launch-webapp "https://lumo.proton.me"' "Proton Lumo binding"
assert_binding 'bindd = SUPER CTRL ALT, Q, Proton Calendar, exec, omarchy-launch-webapp "https://calendar.proton.me"' "Proton Calendar binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, Q, Proton Account, exec, omarchy-launch-webapp "https://account.proton.me"' "Proton Account binding"
pass "the Q family owns all selected Proton apps"

assert_binding 'bindd = SUPER, A, ChatGPT, exec, omarchy-launch-webapp "https://chatgpt.com"' "ChatGPT binding"
assert_binding "bindd = SUPER SHIFT, A, Codex YOLO, exec, ~/.local/share/qvos/desktop/context/qvos-launch-terminal-here codex-yolo \"\$HOME\"" "home Codex YOLO binding"
assert_binding 'bindd = SUPER CTRL, A, Recraft, exec, omarchy-launch-webapp "https://www.recraft.ai/"' "Recraft binding"
assert_binding 'bindd = SUPER SHIFT CTRL, A, Codex YOLO here, exec, ~/.local/share/qvos/desktop/context/qvos-launch-terminal-here codex-yolo' "contextual Codex YOLO binding"
pass "the A family owns daily AI tools"

assert_binding 'bindd = SUPER SHIFT, C, WhatsApp, exec, omarchy-launch-webapp "https://web.whatsapp.com/"' "WhatsApp binding"
assert_binding 'bindd = SUPER CTRL, C, Telegram, exec, omarchy-launch-webapp "https://web.telegram.org/"' "Telegram binding"
assert_binding 'bindd = SUPER SHIFT CTRL, C, Discord, exec, omarchy-launch-webapp "https://discord.com/app"' "Discord binding"
assert_binding 'bindd = SUPER ALT, C, X, exec, omarchy-launch-webapp "https://x.com/"' "X binding"
assert_binding 'bindd = SUPER CTRL ALT, C, Bluesky, exec, omarchy-launch-webapp "https://bsky.app/"' "Bluesky binding"
pass "the C family owns communication and social apps"

assert_binding 'bindd = SUPER, R, Quran, exec, omarchy-launch-webapp "https://quran.com/"' "Quran binding"
assert_binding 'bindd = SUPER SHIFT, R, Qayyimental on Telegram, exec, uwsm-app -- Telegram -- "https://t.me/Qayyimental"' "Qayyimental Telegram binding"
assert_binding 'bindd = SUPER CTRL, R, Qirtaas, exec, omarchy-launch-webapp "https://qirtaas.io/dashboard"' "Qirtaas binding"
assert_binding 'bindd = SUPER SHIFT CTRL, R, Elm Academy curriculum, exec, omarchy-launch-webapp "https://www.elm-academy.net/ar/%D8%A7%D9%84%D9%85%D9%86%D9%87%D8%AC"' "Elm Academy binding"
assert_binding 'bindd = SUPER ALT, R, Set reminder, exec, omarchy-menu reminder-set' "Set reminder binding"
assert_binding 'bindd = SUPER CTRL ALT, R, Clear reminders, exec, omarchy-reminder clear' "Clear reminders binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, R, Show reminders, exec, omarchy-reminder show' "Show reminders binding"
pass "the R family owns Quran destinations and relocated reminders"

assert_binding 'bindd = SUPER, C, Universal copy, sendshortcut, CTRL, Insert, activewindow' "Universal copy binding"
assert_binding 'bindd = SUPER SHIFT, PRINT, Capture menu, exec, omarchy-menu capture' "relocated Capture menu binding"
pass "Universal copy and Capture have singular qvOS bindings"

assert_binding 'bindd = SUPER, SPACE, qvOS apps, exec, omarchy-menu apps' "shared qvOS Apps menu binding"
pass "Super+Space opens the shared qvOS menu in Apps mode"

assert_binding 'bindd = SUPER CTRL, W, Wifi controls, exec, omarchy-launch-wifi' "Wifi binding"
assert_binding 'bindd = SUPER SHIFT, W, Audio controls, exec, omarchy-launch-audio' "audio binding"
assert_binding 'bindd = SUPER SHIFT CTRL, W, Bluetooth controls, exec, omarchy-launch-bluetooth' "Bluetooth binding"
pass "the W family provides Wifi, Audio, and Bluetooth controls"

assert_binding 'bindd = SUPER, D, GitHub, exec, omarchy-launch-webapp "https://github.com"' "GitHub binding"
assert_binding 'bindd = SUPER SHIFT, D, Infisical, exec, omarchy-launch-webapp "https://app.infisical.com/"' "Infisical binding"
assert_binding 'bindd = SUPER CTRL, D, Cloudflare, exec, omarchy-launch-webapp "https://dash.cloudflare.com"' "Cloudflare binding"
assert_binding 'bindd = SUPER SHIFT CTRL, D, Supabase, exec, omarchy-launch-webapp "https://supabase.com/dashboard"' "Supabase binding"
pass "the D family owns developer destinations"

assert_binding 'bindd = SUPER, Z, Default browser, exec, omarchy-launch-browser' "Z default browser binding"
assert_binding 'bindd = SUPER SHIFT, Z, Dev browser (Chromium), exec, uwsm-app -- chromium' "Chromium dev browser binding"
assert_binding 'bindd = SUPER CTRL, Z, Private default browser, exec, omarchy-launch-browser --private' "Z private browser binding"
assert_binding 'bindd = SUPER SHIFT CTRL, Z, Localhost, exec, ~/.local/share/qvos/desktop/web/qvos-localhost-open' "Localhost binding"
assert_binding "bindd = SUPER ALT, Z, Zoom in, exec, hyprctl keyword cursor:zoom_factor \$(hyprctl getoption cursor:zoom_factor -j | jq '.float + 1')" "relocated zoom binding"
assert_binding 'bindd = SUPER CTRL ALT, Z, Reset zoom, exec, hyprctl keyword cursor:zoom_factor 1' "qvOS reset zoom binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, Z, Open website, exec, ~/.local/share/qvos/desktop/web/qvos-website-open' "prompted Omarchy web-app website binding"
pass "the Z family owns browsers, websites, localhost, and zoom"

assert_binding 'bindd = SUPER ALT, E, Obsidian, exec, uwsm-app -- obsidian' "Obsidian binding"
assert_binding 'bindd = SUPER CTRL ALT, E, Standard Notes, exec, omarchy-launch-webapp "https://app.standardnotes.com/"' "Standard Notes binding"
assert_binding 'bindd = SUPER SHIFT ALT, E, Google Workspace, exec, omarchy-launch-webapp "https://workspace.google.com/dashboard"' "Google Workspace binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, E, Google Docs, exec, omarchy-launch-webapp "https://docs.google.com/"' "Google Docs binding"
grep -qx 'obsidian' <<<"$packages" || fail "Obsidian binding requires the default notes package"
if grep -qx 'libreoffice-fresh' <<<"$packages"; then
  fail "LibreOffice must stay outside the qvOS base manifest"
fi
pass "the E Alt family owns notes and office tools"

assert_binding 'bindd = SUPER, grave, Gaming workspace, workspace, name:G' "gaming workspace binding"
assert_binding 'bindd = SUPER SHIFT, grave, Move window to gaming workspace, movetoworkspace, name:G' "gaming workspace transfer binding"
assert_binding 'bindd = SUPER CTRL, grave, Steam, exec, setsid gtk-launch steam >/dev/null 2>&1' "Steam binding"
pass "the grave family uses Shift for workspace movement and Ctrl for Steam"

if grep -Eq '^bindd = SUPER( SHIFT)?, (M|P), Proton|^bindd = SUPER SHIFT, C, Proton|^bindd = SUPER CTRL, Q, Proton Pass,|^bindd = SUPER SHIFT CTRL, Q, Proton Account,|^bindd = SUPER ALT, Q, Proton Docs,|^bindd = SUPER SHIFT ALT, Q, Proton Meet,|^bindd = SUPER SHIFT CTRL ALT, Q, Proton Account Settings,|^bindd = SUPER( SHIFT)?, D, Proton (Drive|Docs),' "$bindings"; then
  fail "retired Proton route"
fi

if grep -Eq '^bindd = SUPER SHIFT, A, (Brave Ask|Lumo),|^bindd = SUPER CTRL, A, (Brave Ask|Codex YOLO here),|^bindd = SUPER SHIFT CTRL, W, (Audio controls|Btop),|^bindd = SUPER ALT, W, Bluetooth controls,|^bindd = SUPER, D, Localhost,|^bindd = SUPER CTRL, D, GitHub,|^bindd = SUPER SHIFT CTRL, D, GitHub,|^bindd = SUPER, S, Discord,|^bindd = SUPER SHIFT, S, Telegram,|^bindd = SUPER CTRL, S, WhatsApp,|^bindd = SUPER SHIFT ALT, E, LibreOffice,|^bindd = SUPER CTRL ALT, E, Proton Docs,|^bindd = SUPER( SHIFT)?, S, Codex|^bindd = SUPER ALT, L, Localhost,' "$bindings"; then
  fail "retired application or control route"
fi

if grep -Eq 'Proton Wallet|Codex Docs|Signal|signal-desktop|LibreOffice|uwsm-app -- libreoffice' "$bindings"; then
  fail "retired app action"
fi

if grep -Eq '^(signal-desktop|spotify)$' <<<"$packages"; then
  fail "retired personal apps remain in the qvOS base manifest"
fi
pass "retired app and control routes stay absent or disabled"
