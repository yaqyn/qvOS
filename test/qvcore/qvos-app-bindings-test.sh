#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
bindings="$root/config/hypr/bindings.conf"
packages=$("$root/qvcore/install/packaging/resolve" base)

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

assert_binding "bindd = SUPER SHIFT, A, Codex YOLO, exec, ~/.local/lib/qvos/desktop/context/qvos-launch-terminal-here codex-yolo \"\$HOME\"" "home Codex YOLO binding"
assert_binding 'bindd = SUPER SHIFT CTRL, A, Codex YOLO here, exec, ~/.local/lib/qvos/desktop/context/qvos-launch-terminal-here codex-yolo' "contextual Codex YOLO binding"
pass "the A family keeps only native development tools"

assert_binding 'bindd = SUPER ALT, R, Set reminder, exec, omarchy-menu reminder-set' "Set reminder binding"
assert_binding 'bindd = SUPER CTRL ALT, R, Clear reminders, exec, qv-reminder clear' "Clear reminders binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, R, Show reminders, exec, qv-reminder show' "Show reminders binding"
pass "the R family keeps only native reminder actions"

assert_binding 'bindd = SUPER, C, Universal copy, sendshortcut, CTRL, Insert, activewindow' "Universal copy binding"
assert_binding 'bindd = SUPER SHIFT, PRINT, Capture menu, exec, omarchy-menu capture' "relocated Capture menu binding"
pass "Universal copy and Capture have singular qvOS bindings"

assert_binding 'bindd = SUPER, SPACE, qvOS apps, exec, omarchy-menu apps' "shared qvOS Apps menu binding"
pass "Super+Space opens the shared qvOS menu in Apps mode"

assert_binding 'bindd = SUPER CTRL, W, Wifi controls, exec, qv-launch-wifi' "Wifi binding"
assert_binding 'bindd = SUPER SHIFT, W, Audio controls, exec, qv-launch-audio' "audio binding"
assert_binding 'bindd = SUPER SHIFT CTRL, W, Bluetooth controls, exec, qv-launch-bluetooth' "Bluetooth binding"
pass "the W family provides Wifi, Audio, and Bluetooth controls"

assert_binding 'bindd = SUPER, Z, Default browser, exec, qv-launch-browser' "Z default browser binding"
assert_binding 'bindd = SUPER SHIFT, Z, Dev browser (Chromium), exec, uwsm-app -- chromium' "Chromium dev browser binding"
assert_binding 'bindd = SUPER CTRL, Z, Private default browser, exec, qv-launch-browser --private' "Z private browser binding"
assert_binding 'bindd = SUPER SHIFT CTRL, Z, Localhost, exec, ~/.local/lib/qvos/desktop/web/qvos-localhost-open' "Localhost binding"
assert_binding "bindd = SUPER ALT, Z, Zoom in, exec, hyprctl keyword cursor:zoom_factor \$(hyprctl getoption cursor:zoom_factor -j | jq '.float + 1')" "relocated zoom binding"
assert_binding 'bindd = SUPER CTRL ALT, Z, Reset zoom, exec, hyprctl keyword cursor:zoom_factor 1' "qvOS reset zoom binding"
assert_binding 'bindd = SUPER SHIFT CTRL ALT, Z, Open website, exec, ~/.local/lib/qvos/desktop/web/qvos-website-open' "prompted website binding"
pass "the Z family owns browsers, websites, localhost, and zoom"

assert_binding 'bindd = SUPER ALT, E, Obsidian, exec, uwsm-app -- obsidian' "Obsidian binding"
grep -qx 'obsidian' <<<"$packages" || fail "Obsidian binding requires the default notes package"
if grep -qx 'libreoffice-fresh' <<<"$packages"; then
  fail "LibreOffice must stay outside the qvOS base manifest"
fi
pass "the E family keeps native file, editor, and notes tools"

assert_binding 'bindd = SUPER, grave, Gaming workspace, workspace, name:G' "gaming workspace binding"
assert_binding 'bindd = SUPER SHIFT, grave, Move window to gaming workspace, movetoworkspace, name:G' "gaming workspace transfer binding"
assert_binding 'bindd = SUPER CTRL, grave, Steam, exec, setsid gtk-launch steam >/dev/null 2>&1' "Steam binding"
pass "the grave family uses Shift for workspace movement and Ctrl for Steam"

if grep -Eq '^bindd = SUPER SHIFT, A, (Brave Ask|Lumo),|^bindd = SUPER CTRL, A, (Brave Ask|Codex YOLO here),|^bindd = SUPER SHIFT CTRL, W, (Audio controls|Btop),|^bindd = SUPER ALT, W, Bluetooth controls,|^bindd = SUPER, D, Localhost,|^bindd = SUPER( SHIFT)?, S, Codex|^bindd = SUPER ALT, L, Localhost,' "$bindings"; then
  fail "retired application or control route"
fi

if grep -Eq 'Proton Wallet|Codex Docs|Signal|signal-desktop|LibreOffice|uwsm-app -- libreoffice' "$bindings"; then
  fail "retired app action"
fi

if rg -q 'qv-launch-webapp[[:space:]]+"https?://|omarchy-launch-webapp[[:space:]]+"?https?://|uwsm-app -- Telegram -- "https?://' \
  "$bindings"; then
  fail "fresh qvOS contains a fixed Web App destination"
fi
pass "fresh qvOS carries no preconfigured Web Apps or service URLs"

if grep -Eq '^(signal-desktop|spotify)$' <<<"$packages"; then
  fail "retired personal apps remain in the qvOS base manifest"
fi
pass "retired app and control routes stay absent or disabled"
