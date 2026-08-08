#!/bin/bash
# shellcheck disable=SC2016,SC2030,SC2031
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
menu_log="$test_root/menu.log"
base_packages="$test_root/base.packages"
other_packages="$test_root/other.packages"

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

"$root/qvcore/install/packaging/resolve" base >"$base_packages"
"$root/qvcore/install/packaging/resolve" other >"$other_packages"

if rg -q '/home/qv(/|$)' "$root/release/iso" "$root/qvcore/tui"; then
  fail "development-machine home path leaked into ISO-owned source"
fi
pass "ISO-owned source excludes development-machine home paths"

if rg -n '\.local/share/qvos/(desktop|direct|menu|power|screensaver|shell|theme|thunar|tmux|tui|waybar|windows|devel-tools|defaults)(/|$)' \
  --glob '!qvcore/config/migrate-runtime-root' \
  --glob '!qvcore/install/cleanup-obsolete' \
  --glob '!qvcore/shell/install' \
  "$root/bin" \
  "$root/config" \
  "$root/development" \
  "$root/qvcore" \
  "$root/services"; then
  fail "generated runtime payload still occupies the canonical source root"
fi
grep -Fq "'.local/share/qvos/desktop/' '.local/lib/qvos/desktop/'" \
  "$root/qvcore/config/migrate-runtime-root" ||
  fail "legacy runtime config cleanup"
grep -Fq 'legacy_runtime_source=' "$root/qvcore/shell/install" ||
  fail "legacy shell runtime cleanup"
grep -Fq 'legacy_share_helper=' "$root/qvcore/install/cleanup-obsolete" ||
  fail "legacy Thunar runtime cleanup"
grep -Fq 'mkdir -p "$HOME/.local/lib/qvos"' "$root/qvcore/install/desktop" ||
  fail "native qvOS runtime root"
grep -Fq 'runtime_root="$lib_root/qvos"' \
  "$root/qvcore/install/migrate-source-root" ||
  fail "legacy runtime relocation owner"
pass "source and generated runtime roots are singular and separate"

[[ -f $root/qvcore/install/packaging/base.packages &&
  -f $root/qvcore/install/packaging/other.packages ]] ||
  fail "native qvOS package manifest is missing"
for retired_package_layer in \
  install/omarchy-base.packages \
  install/omarchy-other.packages \
  qvcore/install/packaging/base.additions \
  qvcore/install/packaging/base.exclusions \
  qvcore/install/packaging/other.additions \
  qvcore/install/packaging/other.exclusions; do
  [[ ! -e $root/$retired_package_layer ]] ||
    fail "retired package layer remains: $retired_package_layer"
done
[[ -x $root/qvcore/install/packaging/resolve ]] ||
  fail "qvOS package resolver mode"
grep -qx 'localsend' "$base_packages" ||
  fail "qvOS LocalSend package resolution"
pass "qvOS resolves singular native package manifests"

grep -qx 'chromium' "$base_packages" || fail "Chromium package contract"
grep -qx 'alacritty' "$base_packages" || fail "Alacritty package contract"
grep -qx 'neovim' "$base_packages" || fail "Neovim package contract"
grep -qx 'omarchy-nvim' "$base_packages" || fail "qvOS Neovim package contract"
grep -qx 'wtype' "$base_packages" || fail "Codex Wayland input contract"
grep -qx 'xdg-user-dirs' "$base_packages" ||
  fail "fresh-install user directory command package contract"
grep -Fq 'xdg-user-dirs-update --set' "$root/qvcore/install/config/user-dirs.sh" ||
  fail "fresh-install user directory command usage contract"
for independent_base_package in \
  bubblewrap \
  bind \
  openssh \
  rsync \
  openbsd-netcat \
  poppler \
  qpdf \
  python \
  mise; do
  grep -Fqx "$independent_base_package" "$base_packages" ||
    fail "independent base package contract: $independent_base_package"
done

editor_env=$(bash -c 'source "$1"; printf "%s\n%s\n%s\n" "$EDITOR" "$VISUAL" "$SUDO_EDITOR"' _ "$root/qvcore/config/files/uwsm/default")
[[ $editor_env == $'nvim\nnvim\nnvim' ]] || fail "editor environment contract"

terminal_desktop=$(grep -vE '^($|#)' "$root/config/xdg-terminals.list" | head -n 1)
[[ $terminal_desktop == "Alacritty.desktop" ]] || fail "terminal default contract"

refresh_home="$test_root/refresh-home"
refresh_source="$test_root/refresh-source"
refresh_fail_bin="$test_root/refresh-fail-bin"
install -d \
  "$refresh_source/qvcore/config/files/qvos" \
  "$refresh_home/.config/qvos" \
  "$refresh_fail_bin"
printf 'staged source\n' >"$refresh_source/qvcore/config/files/qvos/path.conf"
printf 'personal config\n' >"$refresh_home/.config/qvos/path.conf"
HOME="$refresh_home" OMARCHY_PATH="$refresh_source" \
  "$root/qvcore/config/refresh" qvos/path.conf
[[ $(<"$refresh_home/.config/qvos/path.conf") == "staged source" ]] ||
  fail "OMARCHY_PATH config refresh"
refresh_backup=$(
  find "$refresh_home/.config/qvos" \
    -maxdepth 1 \
    -name 'path.conf.bak.*' \
    -print \
    -quit
)
[[ -n $refresh_backup && $(<"$refresh_backup") == "personal config" ]] ||
  fail "qvOS config refresh backup"

install -m 0755 /dev/stdin "$refresh_fail_bin/install" <<'INSTALL'
#!/bin/bash
exit 1
INSTALL
printf 'current config\n' >"$refresh_home/.config/qvos/path.conf"
printf 'future source\n' >"$refresh_source/qvcore/config/files/qvos/path.conf"
refresh_backup_count=$(
  find "$refresh_home/.config/qvos" \
    -maxdepth 1 \
    -name 'path.conf.bak.*' |
    wc -l
)
if HOME="$refresh_home" \
  OMARCHY_PATH="$refresh_source" \
  PATH="$refresh_fail_bin:/usr/bin" \
  "$root/qvcore/config/refresh" qvos/path.conf >/dev/null 2>&1; then
  fail "failed qvOS config staging was accepted"
fi
[[ $(<"$refresh_home/.config/qvos/path.conf") == "current config" ]] ||
  fail "failed qvOS config staging changed the current config"
[[ $(
  find "$refresh_home/.config/qvos" \
    -maxdepth 1 \
    -name 'path.conf.bak.*' |
    wc -l
) == "$refresh_backup_count" ]] ||
  fail "failed qvOS config staging created a misleading backup"
pass "config refreshes honor staged and installed Omarchy roots"

grep -Fqx '"$QVOS_PATH/qvcore/defaults/browser" chromium' "$root/qvcore/install/config/mimetypes" || fail "browser default contract"
grep -Fqx 'editor_desktop=nvim.desktop' "$root/qvcore/install/config/mimetypes" || fail "text MIME default contract"
if grep -Eq 'editor_desktop=(code|code-oss)\.desktop|command -v (code|code-oss)' "$root/qvcore/install/config/mimetypes"; then
  fail "retired Code text MIME preference"
fi
pass "Chromium, Alacritty, and Neovim are the qvOS defaults"

for retired_file_manager_package in nautilus nautilus-python sushi; do
  if grep -Fqx "$retired_file_manager_package" "$base_packages"; then
    fail "$retired_file_manager_package remains in the qvOS base"
  fi
done
[[ ! -e $root/qvcore/install/config/nautilus-python ]] ||
  fail "retired Nautilus configuration owner"
[[ ! -e $root/default/nautilus-python && ! -L $root/default/nautilus-python ]] ||
  fail "retired Nautilus extension source"
grep -Fqx 'default/nautilus-python/' "$root/qvcore/install/retired-paths" ||
  fail "retired Nautilus extension inventory"
if grep -Eq '^[[:space:]]*nautilus([[:space:]]|$)' \
  "$root/bin/qv-theme-bg-install" \
  "$root/bin/omarchy-install-gaming-retroarch"; then
  fail "direct Nautilus launcher remains"
fi
if rg -n 'Nautilus action icons|nautilus-python/extensions' \
  "$root/qvcore/install/config" \
  "$root/qvcore/install/first-run" \
  "$root/qvcore/install/post-install"; then
  fail "Nautilus install integration remains"
fi
pass "Thunar is singular and Nautilus install integration is retired"

grep -qx 'gnome-keyring' "$base_packages" || fail "desktop keyring package contract"
grep -Fqx 'run_logged "$QVOS_PATH/qvcore/boot/login/default-keyring.sh"' "$root/qvcore/boot/install" || fail "default keyring setup contract"
grep -Fq "pam_gnome_keyring\\.so/d" "$root/qvcore/boot/install-sddm" || fail "SDDM keyring setup contract"
if rg -q 'omarchy-pkg-drop[[:space:]]+gnome-keyring' "$root/qvcore/migrations"; then
  fail "retired keyring removal migration"
fi

[[ ! -e $root/qvcore/install/packaging/warp.sh ]] || fail "WARP fresh-install stage"
grep -Fqx '    qv-pkg-aur-add cloudflare-warp-nox-bin || return 1' \
  "$root/qvcore/network/setup-dns" || fail "on-demand WARP package contract"
if rg -q -i 'qvcore/(core|warp)|state/qvos/.*/warp' \
  "$root/qvcore/network/setup-dns" "$root/qvcore/network/dns-policy"; then
  fail "DNS-owned WARP writes retired qvCORE state"
fi
grep -Fqx 'dns|󰐕|DNS|Settings · Connections|network,warp,cloudflare,quad9|Configure|present:qv-setup-dns' \
  "$root/qvcore/menu/concepts.psv" ||
  fail "WARP remains available through DNS configuration"
pass "WARP stays DNS-owned and installs only when selected"

if grep -Eq '^(7zip|act|age|clang|cloudflared|cmake|codex|codex-cli|dos2unix|gdb|git-lfs|gitleaks|go-yq|hurl|hyperfine|infisical|just|lldb|llvm|lsof|mkcert|ninja|osv-scanner|pacman-contrib|pass-cli|postgresql-libs|proton-drive-cli|proton-vpn-cli|proton-vpn-daemon|protonmail-bridge|protonmail-bridge-core|ruby|rust|semgrep|sentry-cli|shellcheck|shfmt|sops|steam|strace|supabase|time|tinyxxd|valgrind|zip)$' "$base_packages" "$other_packages"; then
  fail "optional Service or Development software leaked into the base manifest"
fi
[[ ! -e $root/qvcore/core ]] || fail "retired optional qvCORE bundle remains"
for owner in \
  services/proton/manage \
  development/devel/manage; do
  [[ -x $root/$owner ]] || fail "optional integration owner: $owner"
done
grep -Fq 'qvos/services/proton' "$root/services/proton/manage" ||
  fail "Proton state ownership"
grep -Fq 'qvos/development/devel' "$root/development/devel/manage" ||
  fail "Devel state ownership"
[[ -x $root/qvcore/install/migrate-structure ]] ||
  fail "legacy integration migration owner"
for retired_qvcore_source in \
  bin/omarchy-qvcore-status \
  bin/omarchy-qvcore-repair \
  bin/omarchy-qvcore-disable; do
  [[ ! -e $root/$retired_qvcore_source ]] ||
    fail "retired qvCORE source remains: $retired_qvcore_source"
done
grep -Fqx 'localsend' "$base_packages" ||
  fail "qvOS base LocalSend package"
grep -Fqx '  run_fixed_command "$ufw" allow 53317/udp' \
  "$root/qvcore/install/first-run/root" ||
  fail "qvOS LocalSend UDP firewall ownership"
grep -Fqx '  run_fixed_command "$ufw" allow 53317/tcp' \
  "$root/qvcore/install/first-run/root" ||
  fail "qvOS LocalSend TCP firewall ownership"
grep -Fqx 'share||Share|More · Share|localsend,send|Send|menu:share' \
  "$root/qvcore/menu/concepts.psv" ||
  fail "LocalSend concept stays independent from qvCORE"
if rg -q -i 'qvcore share|qvcore/core/share' \
  "$root/bin/qv-share" \
  "$root/qvcore/install" \
  "$root/qvcore/menu" \
  "$root/qvcore/share"; then
  fail "retired qvCORE Share ownership reference"
fi
pass "LocalSend and its network policy remain base-owned"
if grep -Eq '^(warp|media|qvcore)\|' "$root/qvcore/menu/concepts.psv"; then
  fail "retired optional qvCORE concept remains"
fi
for adapter in bin/omarchy-install-qvcore bin/omarchy-qvcore-remove; do
  [[ -x $root/$adapter ]] || fail "former qvCORE compatibility adapter: $adapter"
  grep -Fqx '# omarchy:hidden=true' "$root/$adapter" ||
    fail "former qvCORE adapter is publicly listed: $adapter"
  grep -Fq 'compat/omarchy/' "$root/$adapter" ||
    fail "former qvCORE adapter bypasses compatibility ownership: $adapter"
done
[[ ! -e $root/qvcore/codex ]] ||
  fail "redundant qvOS Codex inspection domain remains"
grep -Fqx 'omarchy-npx-install @openai/codex codex' \
  "$root/qvcore/install/packaging/npx" ||
  fail "Omarchy Codex wrapper is not preserved"
if rg -qi '\bcodex\b' "$root/qvcore/direct" "$root/qvcore/install/configure"; then
  fail "qvOS retains a duplicate Codex installer"
fi
if grep -Eq "^alias qv=" "$root/qvcore/shell/aliases"; then
  fail "fragile qv alias remains"
fi
for retired_path in \
  bin/omarchy-qvos-block-upstream-maintenance \
  bin/omarchy-qvos-health \
  bin/omarchy-qvos-repair \
  bin/omarchy-qvos-system \
  qvcore/maintenance/essential-packages \
  qvcore/maintenance/qvos-block-upstream-maintenance \
  qvcore/maintenance/qvos-repair \
  qvcore/maintenance/qvos-system \
  qvcore/tui/bin/qvos-repair; do
  [[ ! -e $root/$retired_path ]] ||
    fail "retired qvOS Recovery path remains: $retired_path"
done
if rg -q 'qvcore/codex|qvos/codex|qv codex doctor' \
  "$root/qvcore" \
  "$root/bin"; then
  fail "retired qvOS Codex inspection reference remains"
fi
pass "qvCORE is mandatory while Proton and Devel remain independent integrations"

grep -Fqx 'qmk-hid' "$root/qvcore/install/packaging/other.packages" ||
  fail "qvOS Framework 16 offline package ownership"
grep -Fqx 'qmk-hid' "$other_packages" || fail "Framework 16 offline package contract"
pass "conditional hardware packages remain available offline"

keyring_home="$test_root/keyring-home"
HOME="$keyring_home" bash "$root/qvcore/boot/login/default-keyring.sh"
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
(($(find "$keyring_dir" -maxdepth 1 -type f | wc -l) == 2)) || fail "clean keyring file set"
pass "desktop keyring support stays complete"

grep -Fq 'Text = "󱅾  Update qvOS"' \
  "$root/qvcore/menu/elephant/qvos_menu.lua" ||
  fail "qvOS update menu icon"
grep -Fq 'Actions = { activate = "qv-launch-update" }' \
  "$root/qvcore/menu/elephant/qvos_menu.lua" ||
  fail "qvOS update menu route"
update_override=$(
  sed -n '/^show_update_menu()/,/^}/p' "$root/qvcore/menu/extension.sh"
)
[[ $update_override == $'show_update_menu() {\n  qv-launch-update\n}' ]] ||
  fail "Update qvOS is not direct"
if rg -q 'qvos-system|qvOS System' \
  "$root/qvcore/menu/extension.sh" \
  "$root/qvcore/menu/concepts.psv" \
  "$root/qvcore/menu/search-intents.psv"; then
  fail "retired qvOS System menu route remains"
fi
install_gaming_override=$(
  sed -n '/^show_install_gaming_menu()/,/^}/p' "$root/qvcore/menu/extension.sh"
)
remove_gaming_override=$(
  sed -n '/^show_remove_gaming_menu()/,/^}/p' "$root/qvcore/menu/extension.sh"
)
grep -Fqx \
  'steam|package|steam|tui|true|tui|true|omarchy-install-gaming-steam|qvcore/menu/steam-remove' \
  "$root/qvcore/menu/software-actions.psv" ||
  fail "Steam lifecycle bypasses its safe removal owner"
grep -Fq 'show_software_menu gaming' <<<"$install_gaming_override" ||
  fail "Steam install bypasses Omarchy's owner"
grep -Fq 'show_software_menu gaming' <<<"$remove_gaming_override" ||
  fail "Steam removal bypasses Omarchy's owner"
grep -Fq '  qvOS Source' "$root/bin/omarchy-menu" || fail "qvOS learning entry"
grep -Fq 'https://github.com/Yaqyn-qvOS/qvOS' "$root/bin/omarchy-menu" ||
  fail "qvOS learning destination"
if rg -q 'actionRepair|qvos-repair|QVOS_REPAIR|Repair qvOS' \
  "$root/qvcore/tui"; then
  fail "retired qvOS Repair TUI action remains"
fi
grep -Fq '"format": "󱅾"' "$root/qvcore/waybar/overrides.jsonc" ||
  fail "qvOS Waybar noodle icon"
if grep -Fq '' "$root/qvcore/menu/extension.sh"; then
  fail "retired Omarchy menu glyph"
fi
if rg -q 'show_qvos_menu|omarchy-menu qvos|SUPER SHIFT ALT, SPACE' \
  "$root/qvcore/menu/extension.sh" \
  "$root/config/hypr/bindings.conf" \
  "$root/qvcore/waybar/overrides.jsonc"; then
  fail "retired qvOS feature menu"
fi
grep -Fq '`config/hypr/bindings.conf` is the single authoritative qvOS binding source.' \
  "$root/qvcore/config/AGENTS.md" ||
  fail "qvOS Hyprland source ownership instruction"
grep -Fq 'There is no inherited binding layer and no qvOS binding overlay.' \
  "$root/qvcore/config/AGENTS.md" ||
  fail "qvOS singular binding ownership instruction"
grep -Fq '`qvcore/config/refresh-hyprland` is the single restore owner.' \
  "$root/qvcore/config/AGENTS.md" ||
  fail "qvOS singular Hyprland restore instruction"
[[ -x $root/qvcore/config/refresh-hyprland ]] ||
  fail "qvOS Hyprland restore owner"
for adapter in qv-refresh-hyprland omarchy-refresh-hyprland; do
  grep -Fqx 'exec "$QVOS_PATH/qvcore/config/refresh-hyprland" "$@"' \
    "$root/bin/$adapter" ||
    fail "Hyprland route does not delegate to the config owner: $adapter"
done
[[ ! -e $root/qvcore/hyprland ]] ||
  fail "redundant qvOS Hyprland domain remains"
grep -Fq 'three rings are system-critical or high-impact operations' \
  "$root/qvcore/tui/AGENTS.md" ||
  fail "qvOS TUI three-ring model role"
grep -Fq 'one ring is an ordinary safe task or' "$root/qvcore/tui/AGENTS.md" ||
  fail "qvOS TUI one-ring model role"
if ! grep -Fq 'Generic non-install mutations never bind, advertise, or react to' \
  "$root/qvcore/tui/AGENTS.md" ||
  ! grep -Fq 'Captured Install, qvOS Update, and ISO Build retain' \
    "$root/qvcore/tui/AGENTS.md"; then
  fail "qvOS TUI interruption policy"
fi
grep -Fq 'Ring count controls visual role only' \
  "$root/qvcore/tui/AGENTS.md" ||
  fail "qvOS task behavior is independent from visual ring role"
if ! grep -Fq 'Treat availability, active/default/applied state, behavior, and privilege as' \
  "$root/qvcore/tui/AGENTS.md" ||
  ! grep -Fq 'For every reachable matrix row, account for entry and Preparing' \
    "$root/qvcore/tui/AGENTS.md" ||
  ! grep -Fq 'complete state-to-action and screen matrix' \
    "$root/qvcore/menu/AGENTS.md" ||
  ! grep -Fq 'For a TUI-managed installable or defaultable lifecycle' \
    "$root/qvcore/tui/AGENTS.md"; then
  fail "qvOS TUI lifecycle screen matrix rule"
fi
if ! rg -Uq 'cancellation[[:space:]]+freezes progress immediately' \
  "$root/qvcore/tui/AGENTS.md" ||
  ! rg -Uq 'never animate[[:space:]]+toward `100%` or imply success' \
    "$root/qvcore/tui/AGENTS.md"; then
  fail "qvOS TUI cancellation result rule"
fi
if ! grep -Fq 'through one ordered pseudo-terminal stream' "$root/qvcore/tui/AGENTS.md" ||
  ! grep -Fq 'Retain the complete normalized history without line-count or' \
    "$root/qvcore/tui/AGENTS.md"; then
  fail "qvOS TUI live terminal output rule"
fi
if ! grep -Fq 'log-producing results keep `V` and `Ctrl+V` active' "$root/qvcore/tui/AGENTS.md" ||
  ! grep -Fq 'The boot finale is the exception' "$root/qvcore/tui/AGENTS.md" ||
  ! grep -Fq 'Never discard captured history for general' \
    "$root/qvcore/tui/AGENTS.md"; then
  fail "qvOS TUI completed-result log access rule"
fi
if ! grep -Fq '## Zero Duplication' "$root/AGENTS.md" ||
  ! grep -Fq 'A second consumer must call or extract it' "$root/AGENTS.md" ||
  ! grep -Fq 'leave no equivalent implementation behind' \
    "$root/AGENTS.md"; then
  fail "qvOS shared implementation and zero-duplication rule"
fi
if grep -Fq 'tea.WithInput(nil)' "$root/qvcore/tui/iso_progress.go"; then
  fail "qvOS output-only progress disabled terminal response consumption"
fi
grep -Fq 'qv-launch-update' "$root/qvcore/theme/yaqyn/mako.ini" ||
  fail "qvOS update notification TUI route"
grep -Fqx 'windowrule = float on, match:class ^org\.qvos\.tui$' \
  "$root/qvcore/config/files/hypr/qv/windows.conf" ||
  fail "qvOS TUI floating window contract"
grep -Fqx 'windowrule = size 1024 509, match:class ^org\.qvos\.tui$' \
  "$root/qvcore/config/files/hypr/qv/windows.conf" ||
  fail "qvOS TUI default window size"
grep -Fqx 'windowrule = center on, match:class ^org\.qvos\.tui$' \
  "$root/qvcore/config/files/hypr/qv/windows.conf" ||
  fail "qvOS TUI centered window contract"
grep -Fqx 'exec "$QVOS_PATH/qvcore/install/first-run/run" "$@"' \
  "$root/bin/omarchy-first-run" ||
  fail "qvOS first-run owner adapter"
elephant_line=$(grep -nF 'bash "$QVOS_PATH/qvcore/install/first-run/elephant.sh"' \
  "$root/qvcore/install/first-run/run" | cut -d: -f1)
qvos_first_run_line=$(grep -nF '"$QVOS_PATH/qvcore/install/first-run/gnome-theme"' \
  "$root/qvcore/install/first-run/run" | cut -d: -f1)
((qvos_first_run_line > elephant_line)) ||
  fail "qvOS first-run theme runs before session setup is complete"
grep -Fqx '"$QVOS_PATH/qvcore/menu/install" --install' \
  "$root/qvcore/install/first-run/run" ||
  fail "qvOS first-run menu reconciliation"
grep -Fq 'ls-remote --heads origin refs/heads/OS' \
  "$root/qvcore/update/update-available" || fail "qvOS update status"
grep -Fq 'Update qvOS source' "$root/qvcore/update/update-source" ||
  fail "qvOS source update progress"
grep -Fq '# qv:summary=Update qvOS and system packages safely' \
  "$root/bin/qv-update" || fail "qvOS update help"
grep -Fq 'powers the qvOS Menu' "$root/bin/omarchy-refresh-walker" ||
  fail "qvOS menu help"
grep -Fq 'QVOS_CLI_NAME=qv' "$root/bin/qv" ||
  fail "native qv CLI adapter"
grep -Fq 'QVOS_CLI_NAME=omarchy' "$root/bin/omarchy" ||
  fail "Omarchy CLI compatibility adapter"
grep -Fq 'qvOS command center' "$root/qvcore/cli/qv" ||
  fail "qvOS CLI heading"
grep -Fq 'GROUP_DESCRIPTIONS[restart]="Restart qvOS components"' \
  "$root/qvcore/cli/qv" || fail "qvOS restart help"
grep -Fq 'GROUP_DESCRIPTIONS[toggle]="Toggle qvOS features"' \
  "$root/qvcore/cli/qv" || fail "qvOS toggle help"
grep -Fq 'Name=qvOS (Hyprland uwsm)' "$root/qvcore/boot/wayland-sessions/omarchy.desktop" || fail "qvOS login session label"
grep -Fq 'NamePretty = "qvOS Unlocks"' "$root/qvcore/menu/elephant/omarchy_unlocks.lua" || fail "qvOS unlock provider label"
grep -Fq 'local qvos_path = os.getenv("QVOS_PATH")' \
  "$root/qvcore/menu/elephant/omarchy_unlocks.lua" ||
  fail "qvOS unlock provider native source environment"
grep -Fq 'dofile(qvos_path .. "/default/elephant/omarchy_unlocks.lua")' \
  "$root/qvcore/menu/elephant/omarchy_unlocks.lua" ||
  fail "qvOS unlock provider source ownership"
grep -Fq -- '--app-id=org.qvos.terminal' "$root/qvcore/presentation/run" ||
  fail "native terminal app ID"
grep -Fq -- '--title=qvOS' "$root/qvcore/presentation/run" ||
  fail "qvOS terminal title"
grep -Fq 'Description=qvOS Battery Monitor Check' "$root/config/systemd/user/qvos-battery-monitor.service" || fail "qvOS battery service label"
grep -Fq 'Description=qvOS Battery Monitor Timer' "$root/config/systemd/user/qvos-battery-monitor.timer" || fail "qvOS battery timer label"
grep -Fq 'too small for qvOS layout' "$root/qvcore/tui/iso_config.go" || fail "qvOS installer layout error"
[[ ! -e $root/qvcore/tui/bin/qvos-apply ]] ||
  fail "unsupported qvOS apply action"
if rg -q '"APPLY"|qvos-apply|QVOS_INSTALL_SCRIPT' "$root/qvcore/tui"; then
  fail "unsupported qvOS apply route"
fi

iso_build="$root/release/iso/build"
grep -Fq 'release/iso/build' "$root/qvcore/tui/bin/qvos-build" ||
  fail "TUI qvos-build adapter bypasses the release owner"
grep -Fq 'omarchy_iso_ref="${QVOS_OMARCHY_ISO_REF:-$reviewed_iso_ref}"' "$iso_build" ||
  fail "qvOS ISO reviewed builder ref"
[[ $(<"$root/release/iso/upstream-ref") =~ ^[0-9a-f]{40}$ ]] ||
  fail "qvOS ISO reviewed ref format"
grep -Fq 'Never default to a floating branch' \
  "$root/release/iso/AGENTS.md" ||
  fail "qvOS ISO compatibility pin instruction"
grep -Fq 'freeze feature work until its' "$root/release/iso/AGENTS.md" ||
  fail "qvOS release-candidate feature freeze"
grep -Fq 'An ISO is a development artifact until every base gate' \
  "$root/release/iso/README.md" ||
  fail "qvOS ISO release evidence gate"
grep -Fq 'prove that its embedded qvOS source equals' \
  "$root/release/iso/README.md" ||
  fail "qvOS ISO embedded-source proof"
grep -Fq 'Never overwrite this development installation for rehearsal.' \
  "$root/release/iso/README.md" ||
  fail "qvOS ISO safe installation rehearsal"
grep -Fq 'After the base passes, test the Proton Service and Devel Development' \
  "$root/release/iso/README.md" ||
  fail "qvOS optional-integration release rehearsal"
grep -Fq -- '-e "OMARCHY_INSTALLER_REF=master"' "$iso_build" ||
  fail "qvOS ISO installer branch contract"
grep -Fq -- '-v "$staged_qvos:/omarchy:ro"' "$iso_build" ||
  fail "qvOS ISO source overlay mount"
if rg -q 'omarchy-pkgs|OMARCHY_ISO_REF=local|staged_pkgs|quattro' "$iso_build"; then
  fail "qvOS ISO development branch coupling"
fi
grep -Fq 'docker_args+=(--network "$docker_network")' "$iso_build" ||
  fail "qvOS ISO explicit Docker network option"
grep -Fq 'QVOS_ARCH_MIRROR must use HTTPS' "$iso_build" ||
  fail "qvOS ISO secure Arch mirror override"
grep -Fq 'configure_arch_mirror "$staged_iso"' "$iso_build" ||
  fail "qvOS ISO staged Arch repository override"
grep -Fq 'cp --reflink=auto -- "$latest_iso" "$partial_iso"' "$iso_build" ||
  fail "qvOS ISO atomic release copy"
grep -Fq 'qvOS ISO failed stage retained:' "$iso_build" ||
  fail "qvOS ISO publish failure stage retention"
grep -Fq 'if ! run_iso_builder "$staged_iso" "$staged_qvos" "$stage_out"; then' \
  "$iso_build" ||
  fail "qvOS ISO build failure stage retention"
grep -Fq 'checkout_qvos_update_branch "$target"' "$iso_build" ||
  fail "qvOS ISO attached update branch"
grep -Fq -- '--filter=blob:none --no-checkout' "$iso_build" ||
  fail "qvOS ISO source clone transfers unnecessary historical blobs"
grep -Fq 'git -c http.version=HTTP/1.1' "$iso_build" ||
  fail "qvOS ISO Git transfer retry transport"
grep -Fq 'retrying Git transfer' "$iso_build" ||
  fail "qvOS ISO Git checkout retry contract"
grep -Fq 'retrying Git clone' "$iso_build" ||
  fail "qvOS ISO Git clone retry contract"
grep -Fq 'source_branch != "OS" || $source_upstream != "origin/OS"' \
  "$iso_build" ||
  fail "qvOS ISO staged update branch validation"
grep -Fq 'DisableDownloadTimeout' "$iso_build" ||
  fail "qvOS ISO slow-link repository support"
grep -Fq 'print "ParallelDownloads = 2"' "$iso_build" ||
  fail "qvOS ISO bounded mirror concurrency"
grep -Fq 'QVOS_ARCH_MIRROR must use HTTPS' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO builder mirror validation"
grep -Fq 'DisableDownloadTimeout' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO slow-link builder support"
grep -Fq -- '-buildvcs=false' "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO reproducible TUI build"
[[ -x $root/qvcore/tui/source-hash ]] || fail "qvOS TUI source-hash owner mode"
[[ $("$root/qvcore/tui/source-hash" "$root/qvcore/tui") =~ ^[0-9a-f]{64}$ ]] ||
  fail "qvOS TUI source-hash owner output"
grep -Fq '"$source_dir/source-hash" "$source_dir"' "$root/qvcore/tui/install" ||
  fail "qvOS TUI installer source-hash ownership"
grep -Fq 'qvos_tui_source_hash=$("$qvos_tui_source/source-hash" "$qvos_tui_source")' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO TUI source-hash ownership"
grep -Fq -- '-X main.buildSourceHash=$qvos_tui_source_hash' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO TUI source provenance"
grep -Fq 'safe.directory="$build_cache_dir/airootfs/root/omarchy"' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO command-scoped embedded source trust"
grep -Fq 'config --local core.logAllRefUpdates false' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO embedded source reflog suppression"
grep -Fq 'rm -rf -- "$build_cache_dir/airootfs/root/omarchy/.git/logs"' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO embedded source reflog cleanup"
grep -Fq 'for attempt in 1 2 3' "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO bounded package download retries"
grep -Fq 'XferCommand = /usr/bin/curl --http1.1' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO HTTP/1.1 package transport"
grep -Fq -- '--retry 5 --retry-all-errors' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO bounded curl retries"
grep -Fq '/omarchy/qvcore/install/packaging/resolve' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO package resolution"
grep -Fq 'QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-installer' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO configurator integration"
grep -Fq 'QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-progress' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO progress fullscreen contract"
git apply --numstat <"$root/release/iso/omarchy-iso-qvos-tui.patch" >/dev/null ||
  fail "qvOS ISO patch structure"
for qvos_source_root_contract in \
  '/home/$OMARCHY_USER/.local/share/qvos/install.sh' \
  'cp -r /root/omarchy /mnt/home/$OMARCHY_USER/.local/share/qvos' \
  'ln -s qvos /mnt/home/$OMARCHY_USER/.local/share/omarchy'; do
  grep -Fq "$qvos_source_root_contract" \
    "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
    fail "qvOS ISO canonical source root: $qvos_source_root_contract"
done
grep -Fq 'root/omarchy/qvcore/boot/plymouth/' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO live Plymouth owner"
grep -Fq 'root/omarchy/release/iso/syslinux-splash.png' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO Syslinux splash owner"
[[ $(magick identify -format '%wx%h' "$root/release/iso/syslinux-splash.png") == "640x480" ]] ||
  fail "qvOS Syslinux splash dimensions"
[[ $(magick "$root/release/iso/syslinux-splash.png" -depth 8 -format '%[hex:p{0,0}]' info:) == "000000" ]] ||
  fail "qvOS Syslinux exact-black background"
[[ $(magick identify -format '%[colorspace]' "$root/release/iso/syslinux-splash.png") == "Gray" ]] ||
  fail "qvOS Syslinux splash retained a chromatic pixel"
for syslinux_grayscale_contract in \
  'MENU COLOR border       30;40   #00000000 #00000000 none' \
  'MENU COLOR title        1;37;40 #ffd8d8d8 #00000000 std' \
  'MENU COLOR sel          7;37;40 #ffffffff #ff303030 all'; do
  grep -Fq "$syslinux_grayscale_contract" \
    "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
    fail "qvOS Syslinux grayscale menu: $syslinux_grayscale_contract"
done
grep -Fq 'set_qvos_console_colors' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO console palette owner"
iso_patch_additions=$(sed -n '/^+++ /! s/^+//p' "$root/release/iso/omarchy-iso-qvos-tui.patch")
for retired_iso_color in 1a1b26 f7768e a9b1d6 c0caf5 9ece6a e0af68 7aa2f7 bb9af7 7dcfff; do
  if grep -Fqi "$retired_iso_color" <<<"$iso_patch_additions"; then
    fail "qvOS ISO retained inherited Tokyo Night color: $retired_iso_color"
  fi
done
grep -Fq 'echo -en "\e]P0000000"' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO exact-black console background"
grep -Fq 'echo -en "\e]P1b00000"' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO normal red console accent"
grep -Fq 'echo -en "\e]P9d00000"' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO hot red console accent"
for qvos_boot_branding in \
  'title    qvOS (x86_64, UEFI)' \
  'menuentry "qvOS (%ARCH%, ${archiso_platform})"' \
  'MENU TITLE qvOS' \
  'MENU LABEL qvOS install medium (x86_64, BIOS)' \
  'iso_name="qvos"' \
  'iso_label="QVOS_' \
  'iso_publisher="qvOS <https://github.com/Yaqyn-qvOS/qvOS>"' \
  'iso_application="qvOS Installer"'; do
  grep -Fq "$qvos_boot_branding" \
    "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
    fail "qvOS ISO boot branding: $qvos_boot_branding"
done
grep -Fq 'install -Dm755 /usr/local/bin/qvos-tui /mnt/usr/local/bin/qvos-tui' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS installed-system TUI payload"
grep -Fq 'mount --bind /var/log/qvos-install.log /mnt/var/log/qvos-install.log' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS continuous boot-install log"
grep -Fq 'stop_qvos_iso_progress' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS live-media progress stop before target install"
grep -Fq 'QVOS_ISO_PROGRESS_PID=$!' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS live-media shared progress process tracking"
grep -Fq 'stop_log_output' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS live-media shared progress teardown"
grep -Fq 'release/iso/source-permissions' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO tracked executable-mode integration"
grep -Fq 'if [[ -n ${OMARCHY_CHROOT_INSTALL:-} && -n $qvos_tui && -x $qvos_tui ]]; then' \
  "$root/qvcore/install/helpers/logging.sh" ||
  fail "qvOS target install progress ownership"
grep -Fq 'QVOS_ISO_PROGRESS_PID=$!' \
  "$root/qvcore/install/helpers/logging.sh" ||
  fail "qvOS target install progress process tracking"
grep -Fq 'kill -KILL "$QVOS_ISO_PROGRESS_PID"' \
  "$root/qvcore/install/helpers/logging.sh" ||
  fail "qvOS shared progress forced stop fallback"

progress_bin="$test_root/progress-bin"
progress_log="$test_root/progress-owner.log"
install -d "$progress_bin"
install -m 0755 /dev/stdin "$progress_bin/qvos-tui" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_PROGRESS_LOG"
trap 'exit 0' TERM INT
while true; do
  sleep 1
done
SCRIPT
(
  set -euo pipefail
  # shellcheck disable=SC2329
  sudo() {
    "$@"
  }
  PATH="$progress_bin:/usr/bin"
  export PATH
  export QVOS_TEST_PROGRESS_LOG="$progress_log"
  export OMARCHY_CHROOT_INSTALL=1
  export QVOS_INSTALL_LOG_FILE="$test_root/target-install.log"
  # shellcheck disable=SC1091
  source "$root/qvcore/install/helpers/logging.sh"
  start_install_log
  [[ -n ${QVOS_ISO_PROGRESS_PID:-} ]] ||
    fail "target install did not track its progress process"
  kill -0 "$QVOS_ISO_PROGRESS_PID"
  for _ in {1..20}; do
    [[ -f $progress_log ]] && break
    sleep 0.05
  done
  stop_log_output >/dev/null
  [[ -z ${QVOS_ISO_PROGRESS_PID:-} ]] ||
    fail "target install retained its stopped progress PID"
)
grep -Fqx -- "--iso-progress --log $test_root/target-install.log --no-input" \
  "$progress_log" ||
  fail "target install progress arguments"
pass "target install owns and stops its progress TUI inside the target namespace"

logged_script="$test_root/logged script's owner.sh"
logged_marker="$test_root/logged-script.marker"
logged_output="$test_root/logged-script.log"
install -m 0644 /dev/stdin "$logged_script" <<'SCRIPT'
printf 'ran\n' >"$QVOS_TEST_LOGGED_MARKER"
SCRIPT
(
  set -euo pipefail
  export QVOS_INSTALL_LOG_FILE="$logged_output"
  export QVOS_TEST_LOGGED_MARKER="$logged_marker"
  # shellcheck disable=SC1091
  source "$root/qvcore/install/helpers/logging.sh"
  run_logged "$logged_script"
)
grep -Fqx 'ran' "$logged_marker" ||
  fail "installer logging did not preserve the exact script path"
grep -Fq "Completed: $logged_script" "$logged_output" ||
  fail "installer logging omitted successful exact-path completion"
pass "installer logging safely preserves exact script paths"

source_permissions="$root/release/iso/source-permissions"
[[ -x $source_permissions ]] || fail "qvOS ISO source-permissions mode"
grep -Fq 'git -c safe.directory="$source_root"' "$source_permissions" ||
  fail "qvOS ISO command-scoped source trust"
expected_executable_count=$(git -C "$root" ls-files --stage | awk '$1 == "100755" { count++ } END { print count + 0 }')
source_permission_output=$("$source_permissions" "$root")
actual_executable_count=$(grep -c '^file_permissions\[' <<<"$source_permission_output")
(( actual_executable_count == expected_executable_count )) ||
  fail "qvOS ISO tracked executable-mode count"
grep -Fq 'file_permissions[/root/omarchy/bin/omarchy]=0:0:755' \
  <<<"$source_permission_output" ||
  fail "qvOS ISO command executable mode"
if grep -Fq 'file_permissions[/root/omarchy/README.md]' \
  <<<"$source_permission_output"; then
  fail "qvOS ISO non-executable source mode"
fi
pass "qvOS ISO derives embedded executable modes from Git"

# shellcheck disable=SC1090
source <(sed -n '/^checkout_git_ref() {$/,/^}$/p' "$iso_build")
# shellcheck disable=SC1090
source <(sed -n '/^retry_git_transfer() {$/,/^}$/p' "$iso_build")
# shellcheck disable=SC1090
source <(sed -n '/^clone_git_source() {$/,/^}$/p' "$iso_build")
# shellcheck disable=SC1090
source <(sed -n '/^stage_omarchy_iso() {$/,/^}$/p' "$iso_build")
# shellcheck disable=SC1090
source <(sed -n '/^checkout_qvos_update_branch() {$/,/^}$/p' "$iso_build")
# shellcheck disable=SC1090
source <(sed -n '/^stage_qvos_source() {$/,/^}$/p' "$iso_build")

iso_source_fixture="$test_root/iso-source"
iso_source_stage="$test_root/iso-source-stage"
iso_mismatch_stage="$test_root/iso-mismatch-stage"
git init -q -b OS "$iso_source_fixture"
git -C "$iso_source_fixture" config user.name Fixture
git -C "$iso_source_fixture" config user.email fixture@example.invalid
printf 'release source\n' >"$iso_source_fixture/source"
git -C "$iso_source_fixture" add source
git -C "$iso_source_fixture" commit -q -m 'Release source'
iso_source_commit=$(git -C "$iso_source_fixture" rev-parse HEAD)

git -C "$iso_source_fixture" switch -q -c fixture-mismatch
printf 'mismatched source\n' >"$iso_source_fixture/source"
git -C "$iso_source_fixture" commit -q -am 'Mismatched source'
iso_mismatch_commit=$(git -C "$iso_source_fixture" rev-parse HEAD)
git -C "$iso_source_fixture" switch -q OS

# shellcheck disable=SC2034
qvos_source_repo="$iso_source_fixture"
# shellcheck disable=SC2034
qvos_source_ref="$iso_source_commit"
stage_qvos_source "$iso_source_stage" >/dev/null
[[ $(git -C "$iso_source_stage" rev-parse HEAD) == "$iso_source_commit" ]] ||
  fail "qvOS ISO staged commit identity"
[[ $(git -C "$iso_source_stage" branch --show-current) == "OS" ]] ||
  fail "qvOS ISO staged OS branch"
[[ $(git -C "$iso_source_stage" rev-parse --abbrev-ref '@{upstream}') == "origin/OS" ]] ||
  fail "qvOS ISO staged OS upstream"
[[ -z $(git -C "$iso_source_stage" status --porcelain=v1 --untracked-files=all) ]] ||
  fail "qvOS ISO staged branch cleanliness"

# shellcheck disable=SC2034
qvos_source_ref="$iso_mismatch_commit"
set +e
iso_mismatch_output=$(stage_qvos_source "$iso_mismatch_stage" 2>&1)
iso_mismatch_status=$?
set -e
((iso_mismatch_status != 0)) || fail "qvOS ISO accepted a non-OS pinned commit"
grep -Fq 'pinned qvOS source commit to equal origin/OS' \
  <<<"$iso_mismatch_output" ||
  fail "qvOS ISO mismatched commit failure"
pass "qvOS ISO embeds the exact origin/OS commit on its usable update branch"

iso_builder_fixture="$test_root/iso-builder"
iso_builder_stage="$test_root/iso-builder-stage"
git init -q -b main "$iso_builder_fixture"
git -C "$iso_builder_fixture" config user.name Fixture
git -C "$iso_builder_fixture" config user.email fixture@example.invalid
printf 'reviewed builder\n' >"$iso_builder_fixture/builder"
git -C "$iso_builder_fixture" add builder
git -C "$iso_builder_fixture" commit -q -m 'Reviewed builder'
reviewed_builder_commit=$(git -C "$iso_builder_fixture" rev-parse HEAD)
printf 'unreviewed worktree\n' >"$iso_builder_fixture/builder"
# shellcheck disable=SC2034
omarchy_iso_repo="$iso_builder_fixture"
# shellcheck disable=SC2034
omarchy_iso_ref="$reviewed_builder_commit"
# shellcheck disable=SC2034
prepare_only=true
stage_omarchy_iso "$iso_builder_stage" >/dev/null
[[ $(git -C "$iso_builder_stage" rev-parse HEAD) == "$reviewed_builder_commit" ]] ||
  fail "qvOS ISO local builder commit identity"
[[ $(<"$iso_builder_stage/builder") == "reviewed builder" ]] ||
  fail "qvOS ISO local builder worktree isolation"
[[ -z $(git -C "$iso_builder_stage" status --porcelain=v1 --untracked-files=all) ]] ||
  fail "qvOS ISO local builder stage cleanliness"
pass "local ISO builders obey the same reviewed commit pin"

publish_fixture="$test_root/iso-publish"
publish_bin="$publish_fixture/bin"
publish_out="$publish_fixture/out"
release_dir="$publish_fixture/release"
install -d "$publish_bin" "$publish_out" "$release_dir"
printf 'complete ISO\n' >"$publish_out/omarchy-test.iso"
# shellcheck disable=SC1090
source <(sed -n '/^publish_release_artifact() {$/,/^}$/p' "$iso_build")
preserve_stage=false
publish_release_artifact "$publish_out" >/dev/null
cmp -s "$publish_out/omarchy-test.iso" "$release_dir/qvos-test.iso" ||
  fail "qvOS ISO atomic publication"

printf 'existing release\n' >"$release_dir/qvos-test.iso"
install -m 0755 /dev/stdin "$publish_bin/cp" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
preserve_stage=false
if PATH="$publish_bin:/usr/bin" publish_release_artifact "$publish_out" 2>/dev/null; then
  fail "qvOS ISO failed-copy handling"
fi
[[ $preserve_stage == "true" ]] ||
  fail "qvOS ISO failed-copy stage retention"
[[ $(<"$release_dir/qvos-test.iso") == "existing release" ]] ||
  fail "qvOS ISO failed-copy release preservation"
if compgen -G "$release_dir/.qvos-iso.partial.*" >/dev/null; then
  fail "qvOS ISO failed-copy partial cleanup"
fi
pass "qvOS TUI exposes only supported lifecycle actions on the matching Omarchy ISO"

grep -Fq '(qvOS|Omarchy)([[:space:]]|$)' "$root/qvcore/boot/config-direct-boot" || fail "current and legacy EFI label detection"
grep -Fq -- '--label "qvOS"' "$root/qvcore/boot/config-direct-boot" || fail "qvOS EFI label"
grep -Fxq 'TARGET_OS_NAME="qvOS"' "$root/qvcore/boot/limine/default.conf" || fail "qvOS Limine OS name"
grep -Fxq 'interface_branding:' "$root/qvcore/boot/limine/limine.conf" || fail "qvOS Limine empty header"
grep -Fq -- '-name "omarchy*.efi"' "$root/qvcore/boot/config-direct-boot" || fail "inherited Omarchy UKI filename"
for retired_switcher in \
  bin/omarchy-branch-set \
  bin/omarchy-channel-set \
  bin/omarchy-update-branch; do
  [[ ! -e $root/$retired_switcher ]] ||
    fail "unsupported installed source switcher: $retired_switcher"
done
if rg -q 'omarchy-(branch-set|channel-set|update-branch)|Update channel' \
  "$root/bin/omarchy" "$root/bin/omarchy-menu" "$root/qvcore/menu"; then
  fail "unsupported installed source channel route"
fi
pass "visible system branding is qvOS while compatibility internals remain stable"

for retired_duplicate in \
  qvcore/diagnostics/debug \
  qvcore/share/notification \
  qvcore/menu/elephant/omarchy_background_selector.lua \
  qvcore/menu/elephant/omarchy_themes.lua; do
  [[ ! -e $root/$retired_duplicate ]] ||
    fail "duplicated Omarchy implementation remains: $retired_duplicate"
done
pass "debug and Capture presentation retain singular native owners"
[[ ! -e $root/qvcore/launcher ]] ||
  fail "redundant qvOS launcher domain"
if rg -q 'qvcore/launcher' "$root/qvcore" "$root/bin"; then
  fail "qvOS launcher ownership reference"
fi

if grep -Eq '^alias (c|cx|ic|ix|icx)=' "$root/qvcore/shell/aliases"; then
  fail "disabled AI aliases"
fi
pass "disabled AI aliases stay out of the default shell"

mapfile -t qvos_tests < <(
  find "$root/test/qvcore" -maxdepth 1 -type f \
    \( -name '*-test.sh' -o -name 'run.sh' \) |
    sort
)
((${#qvos_tests[@]} > 0)) || fail "qvOS test entrypoint inventory"
for qvos_test in "${qvos_tests[@]}"; do
  [[ -x $qvos_test ]] || fail "$(basename "$qvos_test") executable mode"
done
grep -Fqx '  env -u QVOS_PATH -u OMARCHY_PATH bash "$test_file"' \
  "$root/test/qvcore/run.sh" ||
  fail "full test runner can inherit the live source root"
pass "qvOS-owned test entrypoints are executable"

install -d \
  "$test_bin" \
  "$test_root/.config/omarchy/extensions" \
  "$test_root/.config/omarchy/themes"

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ $1 == "localsend" && ${QVOS_TEST_LOCALSEND:-0} == "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qv-cmd-missing" <<'SCRIPT'
#!/bin/bash
[[ $1 == "localsend" && ${QVOS_TEST_LOCALSEND:-0} != "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-refresh-config" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qv-launch-walker" <<'SCRIPT'
#!/bin/bash
{
  printf '%s\n' "$*"
  cat
} >>"$QVOS_TEST_MENU_LOG"
SCRIPT

printf '%s\n' 'show_about() { printf "personal menu\n"; }' \
  >"$test_root/.config/omarchy/extensions/menu.sh"
HOME="$test_root" QVOS_PATH="$root" OMARCHY_PATH="$root" \
  "$root/qvcore/menu/install" --install
grep -Fqx 'show_about() { printf "personal menu\n"; }' \
  "$test_root/.config/omarchy/extensions/menu.sh" ||
  fail "personal Omarchy menu extension preservation"
cmp -s \
  "$root/qvcore/menu/extension.sh" \
  "$test_root/.config/omarchy/extensions/qvos-menu.sh" ||
  fail "qvOS menu extension installation"
pass "qvOS menu overrides preserve personal Omarchy extensions"

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

jq -e '
  ."network"."on-click-right"
    == "omarchy-launch-qvos-task dns-configure"
' "$root/qvcore/waybar/overrides.jsonc" >/dev/null ||
  fail "Waybar network DNS route"
pass "network surfaces reuse their established owners"

set +e
share_output=$(
  QVOS_TEST_LOCALSEND=0 \
    QVOS_PATH="$root" \
    OMARCHY_PATH="$root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/qv-share" clipboard 2>&1
)
share_status=$?
set -e
((share_status == 1)) || fail "missing LocalSend exit status"
[[ $share_output == "LocalSend is not installed" ]] || fail "missing LocalSend error"
pass "direct LocalSend route fails clearly when unavailable"

install -d \
  "$test_root/.config/omarchy/themes/yaqyn" \
  "$test_root/custom-theme"
printf 'personal theme\n' >"$test_root/.config/omarchy/themes/yaqyn/personal-marker"
cp -a "$root/qvcore/theme/yaqyn/." "$test_root/custom-theme/"
touch "$test_root/custom-theme/preview-unlock.png"
ln -s "$test_root/custom-theme" "$test_root/.config/omarchy/themes/custom"
HOME="$test_root" QVOS_PATH="$root" OMARCHY_PATH="$root" \
  "$root/qvcore/theme/install" >/dev/null
compgen -G "$test_root/.local/state/qvos/theme-backups/yaqyn.*/personal-marker" >/dev/null ||
  fail "personal Yaqyn theme backup"

theme_list=$(HOME="$test_root" QVOS_PATH="$root" "$root/bin/qv-theme-list")
grep -Fqx 'Yaqyn' <<<"$theme_list" || fail "bundled qvOS Yaqyn theme"
grep -Fqx 'Custom' <<<"$theme_list" || fail "linked compatible user theme"
if grep -Fqx 'Tokyo Night' <<<"$theme_list"; then
  fail "retired inherited theme catalog"
fi
pass "Yaqyn is the only bundled theme while compatible user themes remain available"

HOME="$test_root" QVOS_PATH="$root" OMARCHY_PATH="$root" \
  lua - "$root" <<'LUA' || fail "qvOS Style entries"
local root = arg[1]

dofile(root .. "/default/elephant/omarchy_themes.lua")
local themes = GetEntries()
assert(#themes == 2)
local yaqyn_theme
local custom_theme
for _, theme in ipairs(themes) do
  if theme.Text == "Yaqyn  " then yaqyn_theme = theme end
  if theme.Text == "Custom  " then custom_theme = theme end
end
assert(yaqyn_theme)
assert(yaqyn_theme.Preview:match("/%.config/omarchy/themes/yaqyn/preview%.png$"))
assert(yaqyn_theme.Actions.activate == "qv-theme-set 'yaqyn'")
assert(custom_theme)
assert(custom_theme.Preview:match("/%.config/omarchy/themes/custom/preview%.png$"))
assert(custom_theme.Actions.activate == "qv-theme-set 'custom'")

dofile(root .. "/qvcore/menu/elephant/omarchy_unlocks.lua")
local unlocks = GetEntries()
local yaqyn_unlock
local custom_unlock
for _, unlock in ipairs(unlocks) do
  if unlock.Text == "Yaqyn  " then yaqyn_unlock = unlock end
  if unlock.Text == "Custom  " then custom_unlock = unlock end
end
assert(yaqyn_unlock)
assert(yaqyn_unlock.Preview == root .. "/qvcore/boot/plymouth/preview-unlock.png")
assert(
  yaqyn_unlock.Actions.activate
    == "qv-launch-floating-terminal-with-presentation qv-plymouth-reset"
)
assert(custom_unlock)
assert(custom_unlock.Preview:match("/%.config/omarchy/themes/custom/preview%-unlock%.png$"))
LUA
pass "dynamic Style catalogs expose Yaqyn and compatible user themes only"

grep -qx 'qv-theme-set "Yaqyn"' "$root/qvcore/theme/configure" || fail "fresh install theme"
if rg -q 'chmod[[:space:]]+a\\+rw' \
  "$root/qvcore/theme/configure" \
  "$root/qvcore/browser/install"; then
  fail "world-writable browser policy setup"
fi
grep -Fq 'sudo install -d -o root -g root -m 0755 /etc/chromium/policies/managed' \
  "$root/qvcore/theme/configure" ||
  fail "root-owned Chromium policy directory"
grep -Fq 'sudo chown "$USER:$policy_group" /etc/chromium/policies/managed/color.json' \
  "$root/qvcore/theme/configure" ||
  fail "user-owned Chromium theme policy"
if rg -q 'chmod[[:space:]]+666' "$root/qvcore/install/helpers/logging.sh"; then
  fail "world-writable install log"
fi
grep -Fq 'sudo chown "$USER:$install_group" "$QVOS_INSTALL_LOG_FILE"' \
  "$root/qvcore/install/helpers/logging.sh" ||
  fail "desktop-owned install log"
grep -Fq 'sudo chmod 0640 "$QVOS_INSTALL_LOG_FILE"' \
  "$root/qvcore/install/helpers/logging.sh" ||
  fail "restricted install log"
[[ -f $root/qvcore/install/helpers/errors && ! -x $root/qvcore/install/helpers/errors ]] ||
  fail "qvOS installer error owner mode"
grep -Fq '"qvOS installation stopped!"' \
  "$root/qvcore/install/helpers/errors" || fail "qvOS installer error title"
grep -Fq 'https://github.com/Yaqyn-qvOS/qvOS/issues' \
  "$root/qvcore/install/helpers/errors" || fail "qvOS installer support route"
[[ ! -e $root/qvcore/install/helpers/error-title ]] ||
  fail "duplicate installer error title"
grep -qx 'Name=Yaqyn' "$root/qvcore/boot/plymouth/omarchy.plymouth" || fail "Plymouth theme identity"
grep -qx 'ConsoleLogBackgroundColor=0x1a1b26' \
  "$root/qvcore/boot/plymouth/omarchy.plymouth" ||
  fail "Plymouth promoted live console background"
grep -qx 'Window.SetBackgroundTopColor(0.035, 0.035, 0.035);' \
  "$root/qvcore/boot/plymouth/omarchy.script" ||
  fail "Plymouth promoted live top background"
grep -qx 'Window.SetBackgroundBottomColor(0.035, 0.035, 0.035);' \
  "$root/qvcore/boot/plymouth/omarchy.script" ||
  fail "Plymouth promoted live bottom background"
command -v magick >/dev/null 2>&1 || fail "Plymouth asset color verifier"
[[ $(magick "$root/qvcore/boot/plymouth/bullet.png" -depth 8 -format '%[hex:p{7,7}]' info:) == "505050FF" ]] ||
  fail "Plymouth promoted live password accent"
[[ $(magick "$root/qvcore/boot/plymouth/progress_bar.png" -depth 8 -format '%[hex:p{150,5}]' info:) == "505050" ]] ||
  fail "Plymouth promoted live progress accent"
[[ $(magick "$root/qvcore/boot/plymouth/preview-unlock.png" -depth 8 -format '%[hex:p{0,0}]' info:) == "090909" ]] ||
  fail "Plymouth promoted live preview background"
[[ $(magick "$root/qvcore/boot/plymouth/preview-unlock.png" -depth 8 -format '%[hex:p{840,697}]' info:) == "505050" ]] ||
  fail "Plymouth promoted live preview accent"

limine_theme="$root/qvcore/boot/limine/limine.conf"
grep -qx 'timeout: 5' "$limine_theme" || fail "Limine five-second automatic boot"
grep -qx 'default_entry: 2' "$limine_theme" || fail "Limine qvOS default entry"
grep -qx 'remember_last_entry: no' "$limine_theme" || fail "Limine stable qvOS default"
grep -qx 'interface_branding:' "$limine_theme" || fail "Limine center-only empty branding"
grep -qx 'interface_help_hidden: yes' "$limine_theme" || fail "Limine hidden help"
grep -qx 'interface_help_color: 000000' "$limine_theme" || fail "Limine hidden countdown text"
grep -qx 'interface_help_color_bright: 000000' "$limine_theme" || fail "Limine hidden countdown value"
grep -qx 'editor_highlighting: no' "$limine_theme" || fail "Limine readable uncolored editor"
grep -qx 'term_background: 000000' "$limine_theme" || fail "Limine exact-black terminal background"
grep -qx 'backdrop: 000000' "$limine_theme" || fail "Limine exact-black backdrop"
grep -qx 'term_background_bright: 000000' "$limine_theme" || fail "Limine exact-black bright background"
grep -qx 'term_foreground: a0a0a0' "$limine_theme" || fail "Limine restrained menu foreground"
grep -qx 'term_foreground_bright: b8b8b8' "$limine_theme" || fail "Limine restrained bright foreground"
grep -qx 'term_palette: 000000;3a3a3a;5a5a5a;707070;8a8a8a;a0a0a0;000000;d6d6d6' \
  "$limine_theme" || fail "Limine hidden selected-entry comments"
if rg -q '^wallpaper:' "$limine_theme"; then
  fail "Limine center-only menu gained a wallpaper"
fi
if rg -qi 'b00000|d00000' "$limine_theme"; then
  fail "Limine retained a red accent instead of grayscale-only branding"
fi
grep -qx 'Name=Yaqyn' "$root/qvcore/boot/sddm/metadata.desktop" || fail "SDDM theme identity"
pass "fresh theme policies are scoped to the desktop user and named Yaqyn"

if [[ -e $root/qvcore/theme/yaqyn/unlock.png || -e $root/qvcore/theme/yaqyn/preview-unlock.png ]]; then
  fail "theme-specific unlock variant"
fi
pass "the unlock catalog has no bundled variants"

vsix="$root/qvcore/theme/yaqyn/vscode/extension/yaqyn-theme-0.1.0.vsix"
vsix_manifest=$(unzip -p "$vsix" extension/package.json)
[[ $(jq -r '.name + "|" + .displayName + "|" + .contributes.themes[0].label' <<<"$vsix_manifest") == "yaqyn-theme|Yaqyn|Yaqyn" ]] || fail "Yaqyn VS Code package"
cmp -s \
  <(unzip -p "$vsix" extension/package.json) \
  "$root/qvcore/theme/yaqyn/vscode/extension/package.json" ||
  fail "Yaqyn VS Code package source drift"
vsix_metadata=$(unzip -p "$vsix" extension.vsixmanifest)
grep -Fq 'https://github.com/Yaqyn-qvOS/qvOS.git' <<<"$vsix_metadata" ||
  fail "Yaqyn VS Code package repository"
if grep -Fq 'github.com/yaqyn/qv' <<<"$vsix_metadata"; then
  fail "Yaqyn VS Code package stale repository"
fi
pass "the bundled VS Code theme is Yaqyn end to end"
