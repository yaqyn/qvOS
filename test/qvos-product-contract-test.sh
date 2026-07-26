#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
menu_log="$test_root/menu.log"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

grep -qx 'chromium' "$root/install/omarchy-base.packages" || fail "Chromium package contract"
grep -qx 'alacritty' "$root/install/omarchy-base.packages" || fail "Alacritty package contract"
grep -qx 'neovim' "$root/install/omarchy-base.packages" || fail "Neovim package contract"
grep -qx 'omarchy-nvim' "$root/install/omarchy-base.packages" || fail "qvOS Neovim package contract"

editor_env=$(bash -c 'source "$1"; printf "%s\n%s\n%s\n" "$EDITOR" "$VISUAL" "$SUDO_EDITOR"' _ "$root/config/uwsm/default")
[[ $editor_env == $'nvim\nnvim\nnvim' ]] || fail "editor environment contract"

terminal_desktop=$(grep -vE '^($|#)' "$root/config/xdg-terminals.list" | head -n 1)
[[ $terminal_desktop == "Alacritty.desktop" ]] || fail "terminal default contract"

refresh_home="$test_root/refresh-home"
refresh_source="$test_root/refresh-source"
install -d "$refresh_source/config/qvos" "$refresh_home"
printf 'staged source\n' >"$refresh_source/config/qvos/path.conf"
HOME="$refresh_home" OMARCHY_PATH="$refresh_source" \
  "$root/bin/omarchy-refresh-config" qvos/path.conf
[[ $(<"$refresh_home/.config/qvos/path.conf") == "staged source" ]] ||
  fail "OMARCHY_PATH config refresh"
pass "config refreshes honor staged and installed Omarchy roots"

grep -Fqx 'xdg-settings set default-web-browser chromium.desktop' "$root/install/config/mimetypes.sh" || fail "browser default contract"
grep -Fqx 'editor_desktop=nvim.desktop' "$root/install/config/mimetypes.sh" || fail "text MIME default contract"
if grep -Eq 'editor_desktop=(code|code-oss)\.desktop|command -v (code|code-oss)' "$root/install/config/mimetypes.sh"; then
  fail "retired Code text MIME preference"
fi
pass "Chromium, Alacritty, and Neovim are the qvOS defaults"

for retired_file_manager_package in nautilus nautilus-python sushi; do
  grep -Fqx "# $retired_file_manager_package" \
    "$root/install/omarchy-base.packages" ||
    fail "$retired_file_manager_package disabled base package"
done
grep -Fq 'omarchy-cmd-missing nautilus && return 0' \
  "$root/install/config/nautilus-python.sh" ||
  fail "Nautilus configuration guard"
if grep -Eq '^[[:space:]]*nautilus([[:space:]]|$)' \
  "$root/bin/omarchy-theme-bg-install" \
  "$root/bin/omarchy-install-gaming-retroarch"; then
  fail "direct Nautilus launcher remains"
fi
pass "Thunar is singular while inherited Nautilus hooks remain safe to sync"

grep -qx 'gnome-keyring' "$root/install/omarchy-base.packages" || fail "desktop keyring package contract"
grep -Fqx "run_logged \"\$OMARCHY_INSTALL/login/default-keyring.sh\"" "$root/install/login/all.sh" || fail "default keyring setup contract"
grep -Fq "pam_gnome_keyring\\.so/d" "$root/install/login/sddm.sh" || fail "SDDM keyring setup contract"
if grep -RqsE 'omarchy-pkg-drop[[:space:]]+gnome-keyring' "$root/migrations"; then
  fail "retired keyring removal migration"
fi

[[ ! -e $root/install/packaging/warp.sh ]] || fail "WARP fresh-install stage"
grep -Fqx '    omarchy-pkg-aur-add cloudflare-warp-nox-bin || return 1' "$root/bin/omarchy-setup-dns" || fail "on-demand WARP package contract"
pass "WARP stays optional and installs only when selected"

if grep -Eq '^(act|age|brave-origin-beta-bin|cloudflare-warp-nox-bin|cloudflared|codex|codex-cli|gitleaks|hurl|infisical|localsend|mkcert|osv-scanner|pass-cli|proton-drive-cli|proton-vpn-cli|proton-vpn-daemon|protonmail-bridge|protonmail-bridge-core|semgrep|sentry-cli|sops|steam|supabase)$' "$root"/install/*.packages ||
  grep -RqsF '@openai/codex' "$root/install"; then
  fail "qvCORE application leaked into the base installation"
fi
grep -Fqx '  for component in warp brave-origin share dev codex proton steam media; do' "$root/bin/omarchy-install-qvcore" || fail "complete qvCORE profile"
grep -Fqx 'omarchy-install-gaming-steam' "$root/qv/core/steam.sh" || fail "qvCORE Steam delegates to Omarchy"
grep -Fqx 'GROUP_DESCRIPTIONS[qvcore]="qvCORE integration health and repair"' "$root/bin/omarchy" ||
  fail "qvCORE command group"
[[ -x $root/bin/omarchy-qvcore-status && -x $root/bin/omarchy-qvcore-repair ]] ||
  fail "qvCORE health commands"
pass "qvCORE applications stay outside the base installation"

grep -Fqx 'qmk-hid' "$root/install/omarchy-other.packages" || fail "Framework 16 offline package contract"
pass "conditional hardware packages remain available offline"

keyring_home="$test_root/keyring-home"
HOME="$keyring_home" bash "$root/install/login/default-keyring.sh"
keyring_dir="$keyring_home/.local/share/keyrings"
keyring_file="$keyring_dir/Default_keyring.keyring"
default_file="$keyring_dir/default"
grep -Fqx '[keyring]' "$keyring_file" || fail "passwordless keyring format"
grep -Fqx 'display-name=Default keyring' "$keyring_file" || fail "passwordless keyring name"
grep -Fqx 'lock-on-idle=false' "$keyring_file" || fail "passwordless keyring idle behavior"
grep -Fqx 'lock-after=false' "$keyring_file" || fail "passwordless keyring timeout behavior"
grep -Fqx 'Default_keyring' "$default_file" || fail "default keyring selection"
[[ $(stat -c '%a' "$keyring_dir") == "700" ]] || fail "keyring directory permissions"
[[ $(stat -c '%a' "$keyring_file") == "600" ]] || fail "keyring file permissions"
[[ $(stat -c '%a' "$default_file") == "644" ]] || fail "default keyring pointer permissions"
(( $(find "$keyring_dir" -maxdepth 1 -type f | wc -l) == 2 )) || fail "clean keyring file set"
pass "desktop keyring support stays complete"

grep -Fq '󱅾  qvOS' "$root/bin/omarchy-menu" || fail "qvOS update menu icon"
grep -Fq '*qvOS*) present_terminal omarchy-update ;;' "$root/bin/omarchy-menu" || fail "qvOS update menu route"
grep -Fq '  Omarchy' "$root/bin/omarchy-menu" || fail "upstream Omarchy learning entry"
grep -Fq '"02", "RESET", "Reset to Omarchy"' "$root/qv/tui/main.go" || fail "upstream Omarchy reset identity"
grep -Fq '"format": "󱅾"' "$root/config/waybar/qv/overrides.jsonc" || fail "qvOS Waybar noodle icon"
if grep -Fq '' "$root/bin/omarchy-menu"; then
  fail "retired Omarchy menu glyph"
fi
grep -Fq 'Super + Alt + Space for qvOS Menu.' "$root/install/first-run/welcome.sh" || fail "qvOS first-run menu label"
grep -Fq 'voice dictation for qvOS.' "$root/install/first-run/install-voxtype.hook" || fail "qvOS first-run product label"
grep -Fq 'qvOS menu, exec, omarchy-menu' "$root/default/hypr/bindings/utilities.conf" || fail "qvOS binding description"
grep -Fq '/(qvOS|Omarchy) menu/' "$root/bin/omarchy-menu-keybindings" || fail "current and inherited menu binding priority"
grep -Fq 'qvOS update available' "$root/bin/omarchy-update-available" || fail "qvOS update status"
grep -Fq 'Update qvOS' "$root/bin/omarchy-update-git" || fail "qvOS update progress"
grep -Fq 'omarchy update              Update qvOS and system packages' "$root/bin/omarchy" || fail "qvOS update help"
grep -Fq 'powers the qvOS Menu' "$root/bin/omarchy-refresh-walker" || fail "qvOS menu help"
grep -Fq 'qvOS command center' "$root/bin/omarchy" || fail "qvOS CLI heading"
grep -Fq 'GROUP_DESCRIPTIONS[restart]="Restart qvOS components"' "$root/bin/omarchy" || fail "qvOS restart help"
grep -Fq 'GROUP_DESCRIPTIONS[toggle]="Toggle qvOS features"' "$root/bin/omarchy" || fail "qvOS toggle help"
grep -Fq 'Name=qvOS (Hyprland uwsm)' "$root/default/wayland-sessions/omarchy.desktop" || fail "qvOS login session label"
grep -Fq 'NamePretty = "qvOS Themes"' "$root/default/elephant/omarchy_themes.lua" || fail "qvOS theme provider label"
grep -Fq 'NamePretty = "qvOS Unlocks"' "$root/default/elephant/omarchy_unlocks.lua" || fail "qvOS unlock provider label"
grep -Fq 'NamePretty = "qvOS Background Selector"' "$root/default/elephant/omarchy_background_selector.lua" || fail "qvOS background provider label"
grep -Fq -- '--app-id=org.omarchy.terminal --title=qvOS' "$root/bin/omarchy-launch-floating-terminal-with-presentation" || fail "qvOS terminal title with inherited app ID"
grep -Fq '/title:"Windows VM - qvOS"' "$root/bin/omarchy-windows-vm" || fail "qvOS Windows VM title"
grep -Fq 'Description=qvOS Battery Monitor Check' "$root/config/systemd/user/omarchy-battery-monitor.service" || fail "qvOS battery service label"
grep -Fq 'Description=qvOS Battery Monitor Timer' "$root/config/systemd/user/omarchy-battery-monitor.timer" || fail "qvOS battery timer label"
grep -Fq 'Description=qvOS NVMe Suspend Fix for MacBook' "$root/install/config/hardware/apple/fix-suspend-nvme.sh" || fail "qvOS MacBook service label"
grep -Fq 'this extension is installed by qvOS' "$root/default/chromium/extensions/copy-url/manifest.json" || fail "qvOS Chromium extension label"
grep -Fq 'too small for qvOS layout' "$root/qv/tui/iso_config.go" || fail "qvOS installer layout error"
grep -Fq '(qvOS|Omarchy)([[:space:]]|$)' "$root/bin/omarchy-config-direct-boot" || fail "current and legacy EFI label detection"
grep -Fq -- '--label "qvOS"' "$root/bin/omarchy-config-direct-boot" || fail "qvOS EFI label"
grep -Fq -- '-name "omarchy*.efi"' "$root/bin/omarchy-config-direct-boot" || fail "inherited Omarchy UKI filename"
grep -Fq 'GROUP_DESCRIPTIONS[branch]="Omarchy git branch management"' "$root/bin/omarchy" || fail "upstream branch identity"
pass "visible system branding is qvOS without renaming Omarchy internals"

grep -Fq 'ping -c 1 9.9.9.9' "$root/bin/omarchy-debug" || fail "Quad9 diagnostic probe"
pass "diagnostics follow the qvOS Quad9 policy"

if grep -Eq '^alias (c|cx|ic|ix|icx)=' "$root/default/bash/aliases"; then
  fail "disabled AI aliases"
fi
pass "disabled AI aliases stay out of the default shell"

while IFS= read -r qvos_test; do
  [[ -x $qvos_test ]] || fail "$(basename "$qvos_test") executable mode"
done < <(find "$root/test" -maxdepth 1 -type f -name 'qv*-test.sh' | sort)
pass "qvOS-owned test entrypoints are executable"

install -d "$test_bin" "$test_root/.config/omarchy/themes"

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ $1 == "localsend" && ${QVOS_TEST_LOCALSEND:-0} == "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-missing" <<'SCRIPT'
#!/bin/bash
[[ $1 == "localsend" && ${QVOS_TEST_LOCALSEND:-0} != "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-missing" <<'SCRIPT'
#!/bin/bash
[[ $1 == "code" && ${QVOS_TEST_CODE_MISSING:-0} == "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_PACKAGE_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-refresh-config" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-theme-current" <<'SCRIPT'
#!/bin/bash
printf 'Orion\n'
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-theme-set" <<'SCRIPT'
#!/bin/bash
printf 'theme %s\n' "$1" >>"$QVOS_TEST_STYLE_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-plymouth-reset" <<'SCRIPT'
#!/bin/bash
printf 'unlock Yaqyn\n' >>"$QVOS_TEST_STYLE_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-restart-walker" <<'SCRIPT'
#!/bin/bash
printf 'restart Walker\n' >>"$QVOS_TEST_STYLE_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-walker" <<'SCRIPT'
#!/bin/bash
{
  printf '%s\n' "$*"
  cat
} >>"$QVOS_TEST_MENU_LOG"
SCRIPT

run_menu() {
  QVOS_TEST_LOCALSEND="$1" \
    QVOS_TEST_MENU_LOG="$menu_log" \
    HOME="$test_root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/omarchy-menu" trigger
}

: >"$menu_log"
run_menu 0
if grep -q 'Share' "$menu_log"; then
  fail "LocalSend menu hidden when unavailable"
fi

: >"$menu_log"
run_menu 1
grep -q 'Share' "$menu_log" || fail "LocalSend menu shown when available"
pass "LocalSend menu follows command availability"

for capture_command in \
  "$root/bin/omarchy-capture-screenshot" \
  "$root/bin/omarchy-capture-screenrecording"; do
  grep -Fq 'notification_args+=(-A "share=Share")' "$capture_command" ||
    fail "$(basename "$capture_command") Share action"
  grep -Fq 'share) omarchy-menu-share file "$filename" ;;' "$capture_command" &&
    continue
  grep -Fq 'share) omarchy-menu-share file "$FILEPATH" ;;' "$capture_command" ||
    fail "$(basename "$capture_command") Share delegation"
done
grep -Fq 'notify_transcode_ready' "$root/bin/omarchy-transcode" ||
  fail "transcode result notification"
grep -Fq 'omarchy-menu-share file "$output"' "$root/bin/omarchy-transcode" ||
  fail "transcode result Share delegation"
jq -e '
  ."network"."on-click-right"
    == "omarchy-launch-floating-terminal-with-presentation omarchy-setup-dns"
' "$root/config/waybar/qv/overrides.jsonc" >/dev/null ||
  fail "Waybar network DNS route"
pass "capture, transcode, and network surfaces reuse their established owners"

set +e
share_output=$(QVOS_TEST_LOCALSEND=0 PATH="$test_bin:$root/bin:/usr/bin" "$root/bin/omarchy-menu-share" clipboard 2>&1)
share_status=$?
set -e
((share_status == 1)) || fail "missing LocalSend exit status"
[[ $share_output == "LocalSend is not installed" ]] || fail "missing LocalSend error"
pass "direct LocalSend route fails clearly when unavailable"

migration_home="$test_root/migration-home"
package_log="$test_root/package.log"
install -d "$migration_home/.config/uwsm"
printf '%s\n' \
  'export EDITOR=code-oss' \
  'export VISUAL=code-oss' \
  'export SUDO_EDITOR=code-oss' \
  >"$migration_home/.config/uwsm/default"

QVOS_TEST_PACKAGE_LOG="$package_log" HOME="$migration_home" PATH="$test_bin:$root/bin:/usr/bin" bash -c 'source "$1"' _ "$root/migrations/1784657678.sh" >/dev/null
migrated_editor_env=$(bash -c 'source "$1"; printf "%s\n%s\n%s\n" "$EDITOR" "$VISUAL" "$SUDO_EDITOR"' _ "$migration_home/.config/uwsm/default")
[[ $migrated_editor_env == $'code\ncode\ncode' ]] || fail "existing editor migration"

HOME="$migration_home" PATH="$test_bin:$root/bin:/usr/bin" bash -c 'source "$1"' _ "$root/migrations/1784904379.sh" >/dev/null
migrated_editor_env=$(bash -c 'source "$1"; printf "%s\n%s\n%s\n" "$EDITOR" "$VISUAL" "$SUDO_EDITOR"' _ "$migration_home/.config/uwsm/default")
[[ $migrated_editor_env == $'nvim\nnvim\nnvim' ]] || fail "Neovim editor migration"
grep -Fqx 'omarchy-refresh-config hypr/qv/bindings.conf' "$root/migrations/1784904379.sh" || fail "qvOS binding refresh migration"
grep -Fqx 'omarchy-refresh-config hypr/qv/bindings.conf' "$root/migrations/1784906399.sh" || fail "Chromium dev browser migration"
grep -Fqx 'omarchy-refresh-config hypr/qv/bindings.conf' "$root/migrations/1784991051.sh" || fail "prompted website binding migration"

printf '%s\n' \
  'export EDITOR=helix' \
  'export VISUAL=helix' \
  'export SUDO_EDITOR=helix' \
  >"$migration_home/.config/uwsm/default"
QVOS_TEST_CODE_MISSING=1 QVOS_TEST_PACKAGE_LOG="$package_log" HOME="$migration_home" PATH="$test_bin:$root/bin:/usr/bin" bash -c 'source "$1"' _ "$root/migrations/1784657678.sh" >/dev/null
HOME="$migration_home" PATH="$test_bin:$root/bin:/usr/bin" bash -c 'source "$1"' _ "$root/migrations/1784904379.sh" >/dev/null
migrated_custom_env=$(bash -c 'source "$1"; printf "%s\n%s\n%s\n" "$EDITOR" "$VISUAL" "$SUDO_EDITOR"' _ "$migration_home/.config/uwsm/default")
[[ $migrated_custom_env == $'helix\nhelix\nhelix' ]] || fail "custom editor migration"
[[ $(<"$package_log") == "code" ]] || fail "existing Code OSS package migration"
pass "existing qvOS editor defaults migrate to Neovim while custom choices stay intact"

theme_list=$(HOME="$test_root" OMARCHY_PATH="$root" "$root/bin/omarchy-theme-list")
[[ $theme_list == "Yaqyn" ]] || fail "single bundled theme"
pass "Yaqyn is the only bundled theme"

HOME="$test_root" OMARCHY_PATH="$root" lua - "$root" <<'LUA' || fail "single Yaqyn Style entries"
local root = arg[1]

dofile(root .. "/default/elephant/omarchy_themes.lua")
local themes = GetEntries()
assert(#themes == 1)
assert(themes[1].Text == "Yaqyn  ")
assert(themes[1].Preview == root .. "/themes/yaqyn/preview.png")
assert(themes[1].Actions.activate == "omarchy-theme-set yaqyn")

dofile(root .. "/default/elephant/omarchy_unlocks.lua")
local unlocks = GetEntries()
assert(#unlocks == 1)
assert(unlocks[1].Text == "Yaqyn  ")
assert(unlocks[1].Preview == root .. "/default/plymouth/preview-unlock.png")
assert(
  unlocks[1].Actions.activate
    == "omarchy-launch-floating-terminal-with-presentation 'omarchy-plymouth-reset'"
)
LUA
pass "dynamic Style catalogs resolve to Yaqyn only"

grep -qx 'omarchy-theme-set "Yaqyn"' "$root/install/config/theme.sh" || fail "fresh install theme"
if rg -q 'chmod[[:space:]]+a\\+rw' \
  "$root/install/config/theme.sh" \
  "$root/bin/omarchy-install-browser"; then
  fail "world-writable browser policy setup"
fi
grep -Fq 'sudo install -d -o root -g root -m 0755 /etc/chromium/policies/managed' \
  "$root/install/config/theme.sh" ||
  fail "root-owned Chromium policy directory"
grep -Fq 'sudo chown "$USER:$policy_group" /etc/chromium/policies/managed/color.json' \
  "$root/install/config/theme.sh" ||
  fail "user-owned Chromium theme policy"
if rg -q 'chmod[[:space:]]+666' "$root/install/helpers/logging.sh"; then
  fail "world-writable install log"
fi
grep -Fq 'sudo chown "$USER:$install_group" "$OMARCHY_INSTALL_LOG_FILE"' \
  "$root/install/helpers/logging.sh" ||
  fail "desktop-owned install log"
grep -Fq 'sudo chmod 0640 "$OMARCHY_INSTALL_LOG_FILE"' \
  "$root/install/helpers/logging.sh" ||
  fail "restricted install log"
grep -qx 'Name=Yaqyn' "$root/default/plymouth/omarchy.plymouth" || fail "Plymouth theme identity"
grep -qx 'Name=Yaqyn' "$root/default/sddm/omarchy/metadata.desktop" || fail "SDDM theme identity"
pass "fresh theme policies are scoped to the desktop user and named Yaqyn"

if [[ -e $root/themes/yaqyn/unlock.png || -e $root/themes/yaqyn/preview-unlock.png ]]; then
  fail "theme-specific unlock variant"
fi
pass "the unlock catalog has no bundled variants"

style_log="$test_root/style.log"
install -d \
  "$migration_home/.config/omarchy/themes/orion" \
  "$migration_home/.config/omarchy/themes/qvos" \
  "$migration_home/.config/omarchy/themes/personal"
QVOS_TEST_STYLE_LOG="$style_log" HOME="$migration_home" OMARCHY_PATH="$root" PATH="$test_bin:$root/bin:/usr/bin" \
  bash -c 'source "$1"' _ "$root/migrations/1784659873.sh" >/dev/null
[[ ! -e $migration_home/.config/omarchy/themes/orion ]] || fail "legacy Orion cleanup"
[[ ! -e $migration_home/.config/omarchy/themes/qvos ]] || fail "legacy qvOS cleanup"
[[ -d $migration_home/.config/omarchy/themes/personal ]] || fail "personal theme preservation"
[[ $(readlink "$migration_home/.config/elephant/menus/omarchy_themes.lua") == "$root/default/elephant/omarchy_themes.lua" ]] || fail "theme provider refresh"
[[ $(readlink "$migration_home/.config/elephant/menus/omarchy_unlocks.lua") == "$root/default/elephant/omarchy_unlocks.lua" ]] || fail "unlock provider refresh"
[[ $(<"$style_log") == $'theme Yaqyn\nrestart Walker\nunlock Yaqyn' ]] || fail "Yaqyn migration actions"
pass "existing qvOS themes migrate to Yaqyn without deleting personal themes"

vsix="$root/themes/yaqyn/vscode/extension/yaqyn-theme-0.1.0.vsix"
vsix_manifest=$(unzip -p "$vsix" extension/package.json)
[[ $(jq -r '.name + "|" + .displayName + "|" + .contributes.themes[0].label' <<<"$vsix_manifest") == "yaqyn-theme|Yaqyn|Yaqyn" ]] || fail "Yaqyn VS Code package"
pass "the bundled VS Code theme is Yaqyn end to end"
