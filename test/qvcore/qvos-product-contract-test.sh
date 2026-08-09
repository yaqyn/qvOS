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

compatibility_source_refs=$(
  rg -n 'OMARCHY_PATH' "$root/qvcore" "$root/bin" \
    --glob '!**/AGENTS.md' \
    --glob '!**/README.md' \
    --glob '!**/check' \
    --glob '!*_test.go' \
    --glob '!**/config/migrate-runtime-root' \
    --glob '!**/config/files/uwsm/env' \
    --glob '!**/shell/files/envs' || true
)
if [[ -n $compatibility_source_refs ]]; then
  printf '%s\n' "$compatibility_source_refs" >&2
  fail "native qvCORE owner accepts the compatibility source root"
fi
pass "native qvCORE source resolution uses QVOS_PATH only"

if rg -n '\.local/share/qvos/(desktop|direct|menu|power|screensaver|shell|theme|thunar|tmux|tui|waybar|windows|devel-tools|defaults)(/|$)' \
  --glob '!qvcore/config/migrate-runtime-root' \
  --glob '!qvcore/install/cleanup-obsolete' \
  --glob '!qvcore/shell/install' \
  "$root/bin" \
  "$root/qvcore/config/files" \
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
for official_menu_package in \
  elephant \
  elephant-calc \
  elephant-clipboard \
  elephant-desktopapplications \
  elephant-files \
  elephant-menus \
  elephant-providerlist \
  elephant-symbols \
  elephant-websearch \
  walker; do
  grep -Fqx "$official_menu_package" "$base_packages" ||
    fail "official Walker package contract: $official_menu_package"
done
for retired_app_package in \
  omarchy-nvim \
  omarchy-walker \
  elephant-bluetooth \
  elephant-runner \
  elephant-todo \
  elephant-unicode; do
  ! grep -Fqx "$retired_app_package" "$base_packages" ||
    fail "retired or unused application package remains: $retired_app_package"
done
[[ -x $root/qvcore/config/neovim &&
  -f $root/qvcore/config/files/nvim/init.lua ]] ||
  fail "native Neovim config lifecycle"
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

terminal_desktop=$(grep -vE '^($|#)' "$root/qvcore/config/files/xdg-terminals.list" | head -n 1)
[[ $terminal_desktop == "Alacritty.desktop" ]] || fail "terminal default contract"

refresh_home="$test_root/refresh-home"
refresh_source="$test_root/refresh-source"
refresh_fail_bin="$test_root/refresh-fail-bin"
install -d \
  "$refresh_source/qvcore/config/files/qvos" \
  "$refresh_home/.config/qvos" \
  "$refresh_fail_bin"
printf 'native source\n' >"$refresh_source/qvcore/config/files/qvos/path.conf"
printf 'owned source\n' >"$refresh_source/qvcore/config/files/qvos/owned.conf"
printf 'personal config\n' >"$refresh_home/.config/qvos/path.conf"
HOME="$refresh_home" QVOS_PATH="$refresh_source" \
  "$root/qvcore/config/refresh" qvos/path.conf
[[ $(<"$refresh_home/.config/qvos/path.conf") == "native source" ]] ||
  fail "QVOS_PATH config refresh"
refresh_backup=$(
  find "$refresh_home/.config/qvos" \
    -maxdepth 1 \
    -name 'path.conf.bak.*' \
    -print \
    -quit
)
[[ -n $refresh_backup && $(<"$refresh_backup") == "personal config" ]] ||
  fail "qvOS config refresh backup"
refresh_backup_count=$(
  find "$refresh_home/.config/qvos" \
    -maxdepth 1 \
    -name 'path.conf.bak.*' |
    wc -l
)
HOME="$refresh_home" QVOS_PATH="$refresh_source" \
  "$root/qvcore/config/refresh" qvos/path.conf
[[ $(
  find "$refresh_home/.config/qvos" \
    -maxdepth 1 \
    -name 'path.conf.bak.*' |
    wc -l
) == "$refresh_backup_count" ]] || fail "idempotent config refresh backup"
HOME="$refresh_home" QVOS_PATH="$refresh_source" \
  "$root/qvcore/config/refresh" qvos/owned.conf
[[ $(<"$refresh_home/.config/qvos/owned.conf") == "owned source" ]] ||
  fail "singular native qvOS config refresh"
if HOME="$refresh_home" QVOS_PATH="$refresh_source" \
  "$root/qvcore/config/refresh" --owned qvos/owned.conf >/dev/null 2>&1; then
  fail "retired config source selector accepted"
fi
invalid_refresh_paths=(
  ../outside
  /absolute
  path..conf
)
for invalid_path in "${invalid_refresh_paths[@]}"; do
  if HOME="$refresh_home" QVOS_PATH="$refresh_source" \
    "$root/qvcore/config/refresh" "$invalid_path" >/dev/null 2>&1; then
    fail "unsafe config path accepted: $invalid_path"
  fi
done
ln -s path.conf "$refresh_source/qvcore/config/files/qvos/linked.conf"
if HOME="$refresh_home" QVOS_PATH="$refresh_source" \
  "$root/qvcore/config/refresh" qvos/linked.conf >/dev/null 2>&1; then
  fail "linked config source accepted"
fi

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
  QVOS_PATH="$refresh_source" \
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
pass "config refreshes are bounded, atomic, idempotent, and source-scoped"

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
  bin/omarchy-install-qvcore \
  bin/omarchy-qvcore-remove \
  bin/omarchy-qvcore-status \
  bin/omarchy-qvcore-repair \
  bin/omarchy-qvcore-disable \
  compat/omarchy/install-qvcore \
  compat/omarchy/remove-qvcore; do
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
[[ ! -e $root/qvcore/codex ]] ||
  fail "redundant qvOS Codex inspection domain remains"
grep -Fqx 'openai-codex' "$base_packages" ||
  fail "qvOS Codex is not base-owned through the Arch package"
if rg -q '@openai/codex|command_name=.*codex|omarchy-npx-install' \
  "$root/qvcore/install/packaging/npx" \
  "$root/qvcore/install/packaging/npx-wrappers.psv"; then
  fail "qvOS retains a mutable Codex NPX wrapper"
fi
[[ ! -e $root/bin/omarchy-npx-install ]] ||
  fail "retired generic NPX wrapper generator remains"
grep -Fqx 'bin/omarchy-npx-install' "$root/qvcore/install/retired-paths" ||
  fail "retired generic NPX wrapper generator is not inventoried"
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
for unsupported_t2_package in \
  apple-bcm-firmware \
  apple-t2-audio-config \
  linux-t2 \
  linux-t2-headers \
  t2fanrd \
  tiny-dfr \
  vulkan-asahi; do
  ! grep -Fqx "$unsupported_t2_package" "$other_packages" ||
    fail "unsupported T2 package remains: $unsupported_t2_package"
done
[[ ! -e $root/qvcore/install/config/hardware/apple/fix-t2.sh ]] ||
  fail "unsupported T2 configuration owner remains"
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
  sed -n '/^show_update_menu()/,/^}/p' "$root/qvcore/menu/routes"
)
[[ $update_override == $'show_update_menu() {\n  qv-launch-update\n}' ]] ||
  fail "Update qvOS is not direct"
if rg -q 'qvos-system|qvOS System' \
  "$root/qvcore/menu/routes" \
  "$root/qvcore/menu/concepts.psv" \
  "$root/qvcore/menu/search-intents.psv"; then
  fail "retired qvOS System menu route remains"
fi
install_gaming_override=$(
  sed -n '/^show_install_gaming_menu()/,/^}/p' "$root/qvcore/menu/routes"
)
remove_gaming_override=$(
  sed -n '/^show_remove_gaming_menu()/,/^}/p' "$root/qvcore/menu/routes"
)
grep -Fqx \
  'steam|package|steam|tui|true|tui|true|qv-install-gaming-steam|qvcore/gaming/steam-remove' \
  "$root/qvcore/menu/software-actions.psv" ||
  fail "Steam lifecycle bypasses its safe removal owner"
grep -Fq 'show_software_menu gaming' <<<"$install_gaming_override" ||
  fail "Steam install bypasses Omarchy's owner"
grep -Fq 'show_software_menu gaming' <<<"$remove_gaming_override" ||
  fail "Steam removal bypasses Omarchy's owner"
grep -Fq '  qvOS Source' "$root/qvcore/menu/base" || fail "qvOS learning entry"
grep -Fq 'https://github.com/Yaqyn-qvOS/qvOS' "$root/qvcore/menu/base" ||
  fail "qvOS learning destination"
if rg -q 'actionRepair|qvos-repair|QVOS_REPAIR|Repair qvOS' \
  "$root/qvcore/tui"; then
  fail "retired qvOS Repair TUI action remains"
fi
grep -Fq '"format": "󱅾"' "$root/qvcore/config/files/waybar/config.jsonc" ||
  fail "qvOS Waybar noodle icon"
if grep -Fq '' "$root/qvcore/menu/routes"; then
  fail "retired Omarchy menu glyph"
fi
if rg -q 'show_qvos_menu|omarchy-menu qvos|SUPER SHIFT ALT, SPACE' \
  "$root/qvcore/menu/routes" \
  "$root/qvcore/config/files/hypr/bindings.conf" \
  "$root/qvcore/config/files/waybar/config.jsonc"; then
  fail "retired qvOS feature menu"
fi
grep -Fq '`qvcore/config/base/hypr/` is the singular source-side Hyprland base.' \
  "$root/qvcore/config/AGENTS.md" ||
  fail "qvOS Hyprland source ownership instruction"
grep -Fq 'There is no inherited base, fragment fan-out, binding layer, or qvOS overlay.' \
  "$root/qvcore/config/AGENTS.md" ||
  fail "qvOS singular binding ownership instruction"
grep -Fq '`qvcore/config/refresh-hyprland` is the single complete Hyprland restore owner.' \
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
  "$root/qvcore/config/base/hypr/windows.conf" ||
  fail "qvOS TUI floating window contract"
grep -Fqx 'windowrule = size 1024 509, match:class ^org\.qvos\.tui$' \
  "$root/qvcore/config/base/hypr/windows.conf" ||
  fail "qvOS TUI default window size"
grep -Fqx 'windowrule = center on, match:class ^org\.qvos\.tui$' \
  "$root/qvcore/config/base/hypr/windows.conf" ||
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
grep -Fq '# qv:summary=Restore Walker and Elephant defaults' \
  "$root/bin/qv-refresh-walker" || fail "qvOS menu help"
! rg -q '^# (qv|omarchy):' "$root/bin/omarchy-refresh-walker" ||
  fail "Walker compatibility metadata"
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
grep -Fq 'Name=qvOS (Hyprland uwsm)' "$root/qvcore/boot/wayland-sessions/qvos.desktop" || fail "qvOS login session label"
grep -Fq 'Name = "qvosUnlocks"' "$root/qvcore/menu/elephant/qvos_unlocks.lua" ||
  fail "qvOS unlock provider identity"
grep -Fq 'NamePretty = "qvOS Unlocks"' "$root/qvcore/menu/elephant/qvos_unlocks.lua" ||
  fail "qvOS unlock provider label"
! rg -q 'dofile|default/elephant' "$root/qvcore/menu/elephant/qvos_unlocks.lua" ||
  fail "qvOS unlock provider retains inherited source ownership"
grep -Fq -- '--app-id=org.qvos.terminal' "$root/qvcore/presentation/run" ||
  fail "native terminal app ID"
grep -Fq -- '--title=qvOS' "$root/qvcore/presentation/run" ||
  fail "qvOS terminal title"
grep -Fq 'Description=qvOS Battery Monitor Check' "$root/qvcore/config/files/systemd/user/qvos-battery-monitor.service" || fail "qvOS battery service label"
grep -Fq 'Description=qvOS Battery Monitor Timer' "$root/qvcore/config/files/systemd/user/qvos-battery-monitor.timer" || fail "qvOS battery timer label"
grep -Fq 'too small for qvOS layout' "$root/qvcore/tui/iso_config.go" || fail "qvOS installer layout error"
if rg -n '\bomarchy[A-Z]' "$root/qvcore/tui/iso_config.go"; then
  fail "qvOS installer retains an inherited private schema identity"
fi
[[ ! -e $root/qvcore/tui/bin/qvos-apply ]] ||
  fail "unsupported qvOS apply action"
if rg -q '"APPLY"|qvos-apply|QVOS_INSTALL_SCRIPT' "$root/qvcore/tui"; then
  fail "unsupported qvOS apply route"
fi

iso_build="$root/release/iso/build"
iso_builder="$root/release/iso/builder/build-iso.sh"
iso_profile="$root/release/iso/profile"
iso_installer="$iso_profile/airootfs/root/.automated_script.sh"
grep -Fq 'release/iso/build' "$root/qvcore/tui/bin/qvos-build" ||
  fail "TUI qvos-build adapter bypasses the release owner"
[[ -x $iso_builder && -f $iso_profile/profiledef.sh ]] ||
  fail "qvOS native ISO owner"
[[ ! -e $root/release/iso/omarchy-iso-qvos-tui.patch &&
  ! -e $root/release/iso/upstream-ref ]] ||
  fail "qvOS ISO retains its runtime upstream patch boundary"
grep -Fq 'No Omarchy ISO source is cloned, patched, mounted, or executed' \
  "$root/release/iso/AGENTS.md" ||
  fail "qvOS native ISO ownership instruction"
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
if rg -q 'OMARCHY_INSTALLER_(REPO|REF)' "$iso_build"; then
  fail "qvOS ISO retains an unpinned product-source fallback"
fi
grep -Fq -- '-v "$staged_qvos:/qvos:ro"' "$iso_build" ||
  fail "qvOS ISO pinned source mount"
if rg -q 'omarchy-pkgs|OMARCHY_ISO_REF|QVOS_OMARCHY_ISO|staged_pkgs|quattro|patch_omarchy' \
  "$iso_build" "$iso_builder"; then
  fail "qvOS ISO development branch coupling"
fi
grep -Fq 'provider_channel="${QVOS_PROVIDER_CHANNEL:-stable}"' "$iso_build" ||
  fail "qvOS ISO Stable provider default"
grep -Fq 'provider_channel=edge' "$iso_build" ||
  fail "qvOS ISO explicit Edge image channel"
grep -Fq 'provider_channel=rc' "$iso_build" ||
  fail "qvOS ISO explicit RC image channel"
grep -Fq 'docker_args+=(--network "$docker_network")' "$iso_build" ||
  fail "qvOS ISO explicit Docker network option"
grep -Fq -- '--pull=always' "$iso_build" ||
  fail "qvOS ISO refreshes its ephemeral build container"
grep -Fq 'QVOS_ARCH_MIRROR must use HTTPS' "$iso_build" ||
  fail "qvOS ISO secure Arch mirror override"
grep -Fq 'QVOS_ARCH_MIRROR' \
  "$iso_builder" ||
  fail "qvOS ISO staged Arch repository override"
grep -Fq 'cp --reflink=auto -- "$latest_iso" "$partial_iso"' "$iso_build" ||
  fail "qvOS ISO atomic release copy"
grep -Fq 'qvOS ISO failed stage retained:' "$iso_build" ||
  fail "qvOS ISO publish failure stage retention"
grep -Fq 'if ! run_iso_builder "$native_iso" "$staged_qvos" "$stage_out"; then' \
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
grep -Fq 'DisableDownloadTimeout' \
  "$iso_builder" ||
  fail "qvOS ISO slow-link repository support"
grep -Fq '/qvcore/packages/provider-files' \
  "$iso_builder" ||
  fail "qvOS ISO provider-owned mirror concurrency"
grep -Fq 'QVOS_ARCH_MIRROR must use HTTPS' \
  "$iso_builder" ||
  fail "qvOS ISO builder mirror validation"
grep -Fq 'pacman --noconfirm -Syu --needed' "$iso_builder" ||
  fail "qvOS ISO avoids a partial Arch build-container upgrade"
grep -Fq '/usr/share/archiso/configs/releng/' "$iso_builder" ||
  fail "qvOS ISO uses the signed Archiso releng profile"
if rg -q "(^|[[:space:]\"'])/archiso(/|[[:space:]\"']|$)|omarchy-iso" \
  "$iso_build" "$iso_builder"; then
  fail "qvOS ISO executes an external distribution builder"
fi
grep -Fq -- '-buildvcs=false' "$iso_builder" ||
  fail "qvOS ISO reproducible TUI build"
[[ -x $root/qvcore/tui/source-hash ]] || fail "qvOS TUI source-hash owner mode"
[[ $("$root/qvcore/tui/source-hash" "$root/qvcore/tui") =~ ^[0-9a-f]{64}$ ]] ||
  fail "qvOS TUI source-hash owner output"
grep -Fq '"$source_dir/source-hash" "$source_dir"' "$root/qvcore/tui/install" ||
  fail "qvOS TUI installer source-hash ownership"
grep -Fq 'qvos_tui_source_hash=$("$qvos_tui_source/source-hash" "$qvos_tui_source")' \
  "$iso_builder" ||
  fail "qvOS ISO TUI source-hash ownership"
grep -Fq -- '-X main.buildSourceHash=$qvos_tui_source_hash' \
  "$iso_builder" ||
  fail "qvOS ISO TUI source provenance"
grep -Fq 'unexpected source digest' "$iso_builder" ||
  fail "qvOS ISO verifies its built TUI provenance"
grep -Fq 'safe.directory="$build_cache_dir/airootfs/root/qvos"' \
  "$iso_builder" ||
  fail "qvOS ISO command-scoped embedded source trust"
grep -Fq 'config --local core.logAllRefUpdates false' \
  "$iso_builder" ||
  fail "qvOS ISO embedded source reflog suppression"
grep -Fq 'rm -rf -- "$build_cache_dir/airootfs/root/qvos/.git/logs"' \
  "$iso_builder" ||
  fail "qvOS ISO embedded source reflog cleanup"
grep -Fq 'for attempt in 1 2 3' "$iso_builder" ||
  fail "qvOS ISO bounded package download retries"
grep -Fq 'XferCommand = /usr/bin/curl --http1.1' \
  "$iso_builder" ||
  fail "qvOS ISO HTTP/1.1 package transport"
grep -Fq -- '--retry 5 --retry-connrefused --retry-delay 2' \
  "$iso_builder" ||
  fail "qvOS ISO bounded curl retries"
if grep -F 'XferCommand =' "$iso_builder" | grep -Fq -- '--retry-all-errors'; then
  fail "qvOS ISO retries permanent package transport failures"
fi
grep -Fq 'chmod 0755 "$offline_db_dir"' "$iso_builder" ||
  fail "qvOS ISO package database sandbox traversal"
grep -Fq 'qvcore/install/packaging/resolve' "$iso_builder" ||
  fail "qvOS ISO package resolution"
grep -Fq 'QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-installer' \
  "$iso_installer" ||
  fail "qvOS ISO configurator integration"
grep -Fq 'QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-progress' \
  "$iso_installer" ||
  fail "qvOS ISO progress fullscreen contract"
[[ ! -e $iso_profile/airootfs/root/configurator ]] ||
  fail "qvOS ISO ships a duplicate fallback configurator"
grep -Fq 'package_file.sig' "$iso_builder" ||
  fail "qvOS ISO package signature retention"
grep -Fq 'Server = file:///var/cache/qvos/mirror/offline/' \
  "$iso_profile/pacman-offline.conf" ||
  fail "qvOS ISO signed offline mirror path"
grep -Fq 'qvOS cannot safely install on T2 Macs' "$root/qvcore/tui/iso_installer.go" ||
  fail "qvOS ISO T2 safety refusal"
if rg -q '"/root/omarchy"' "$root/qvcore/tui"; then
  fail "qvOS ISO TUI retains the retired embedded source root"
fi
for qvos_source_root_contract in \
  'source "$HOME/.local/share/qvos/install.sh"' \
  'cp -a -- /root/qvos "/mnt/home/$QVOS_USER/.local/share/qvos"' \
  'ln -s qvos "/mnt/home/$QVOS_USER/.local/share/omarchy"'; do
  grep -Fq "$qvos_source_root_contract" "$iso_installer" ||
    fail "qvOS ISO canonical source root: $qvos_source_root_contract"
done
grep -Fq 'source "$QVOS_INSTALL/helpers/run"' "$iso_installer" ||
  fail "qvOS ISO native helper owner"
if rg -q 'helpers/all\.sh|OMARCHY_(USER|MIRROR|PATH|INSTALL)=' \
  "$iso_installer" "$iso_builder"; then
  fail "qvOS ISO activates the retired installer helper tree"
fi
grep -Fq 'root/qvos/qvcore/boot/plymouth/' \
  "$iso_builder" ||
  fail "qvOS ISO live Plymouth owner"
grep -Fq 'root/qvos/release/iso/syslinux-splash.png' \
  "$iso_builder" ||
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
  grep -Fq "$syslinux_grayscale_contract" "$iso_profile/syslinux/archiso_head.cfg" ||
    fail "qvOS Syslinux grayscale menu: $syslinux_grayscale_contract"
done
grep -Fq 'set_qvos_console_colors' "$iso_installer" ||
  fail "qvOS ISO console palette owner"
for retired_iso_color in 1a1b26 f7768e a9b1d6 c0caf5 9ece6a e0af68 7aa2f7 bb9af7 7dcfff; do
  if rg -Fqi "$retired_iso_color" "$iso_profile"; then
    fail "qvOS ISO retained inherited Tokyo Night color: $retired_iso_color"
  fi
done
grep -Fq 'echo -en "\e]P0000000"' "$iso_installer" ||
  fail "qvOS ISO exact-black console background"
grep -Fq 'echo -en "\e]P1b00000"' "$iso_installer" ||
  fail "qvOS ISO normal red console accent"
grep -Fq 'echo -en "\e]P9d00000"' "$iso_installer" ||
  fail "qvOS ISO hot red console accent"
grep -Fq 'title    qvOS (x86_64, UEFI)' \
  "$iso_profile/efiboot/loader/entries/01-archiso-x86_64-linux.conf" ||
  fail "qvOS ISO UEFI branding"
grep -Fq 'menuentry "qvOS (%ARCH%, ${archiso_platform})"' \
  "$iso_profile/grub/grub.cfg" || fail "qvOS ISO GRUB branding"
grep -Fq 'MENU TITLE qvOS' "$iso_profile/syslinux/archiso_head.cfg" ||
  fail "qvOS ISO Syslinux title"
grep -Fq 'MENU LABEL qvOS install medium (x86_64, BIOS)' \
  "$iso_profile/syslinux/archiso_sys-linux.cfg" || fail "qvOS ISO BIOS branding"
for qvos_profile_contract in \
  'iso_name="qvos"' \
  'iso_label="QVOS_' \
  'iso_publisher="qvOS <https://github.com/Yaqyn-qvOS/qvOS>"' \
  'iso_application="qvOS Installer"'; do
  grep -Fq "$qvos_profile_contract" "$iso_profile/profiledef.sh" ||
    fail "qvOS ISO profile branding: $qvos_profile_contract"
done
grep -Fq "'-comp' 'zstd'" "$iso_profile/profiledef.sh" ||
  fail "qvOS ISO fast live-root compression"
grep -Fq 'uncompressed@subpathname(var/cache/qvos/mirror/offline)' \
  "$iso_profile/profiledef.sh" || fail "qvOS ISO avoids recompressing packages"
grep -Fq 'install -Dm755 /usr/local/bin/qvos-tui /mnt/usr/local/bin/qvos-tui' \
  "$iso_installer" ||
  fail "qvOS installed-system TUI payload"
grep -Fq 'bind_qvos_target /var/log/qvos-install.log /mnt/var/log/qvos-install.log' \
  "$iso_installer" ||
  fail "qvOS continuous boot-install log"
grep -Fq 'stop_qvos_iso_progress' "$iso_installer" ||
  fail "qvOS live-media progress stop before target install"
grep -Fq 'QVOS_ISO_PROGRESS_PID=$!' "$iso_installer" ||
  fail "qvOS live-media shared progress process tracking"
grep -Fq 'stop_log_output' "$iso_installer" ||
  fail "qvOS live-media shared progress teardown"
grep -Fq 'release/iso/source-permissions' "$iso_builder" ||
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
grep -Fq 'file_permissions[/root/qvos/bin/omarchy]=0:0:755' \
  <<<"$source_permission_output" ||
  fail "qvOS ISO command executable mode"
if grep -Fq 'file_permissions[/root/qvos/README.md]' \
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

publish_fixture="$test_root/iso-publish"
publish_bin="$publish_fixture/bin"
publish_out="$publish_fixture/out"
release_dir="$publish_fixture/release"
install -d "$publish_bin" "$publish_out" "$release_dir"
printf 'complete ISO\n' >"$publish_out/qvos-test.iso"
# shellcheck disable=SC1090
source <(sed -n '/^publish_release_artifact() {$/,/^}$/p' "$iso_build")
preserve_stage=false
publish_release_artifact "$publish_out" >/dev/null
cmp -s "$publish_out/qvos-test.iso" "$release_dir/qvos-test.iso" ||
  fail "qvOS ISO atomic publication"
[[ $(stat -c '%a' "$release_dir/qvos-test.iso") == "644" ]] ||
  fail "qvOS ISO release mode"

printf 'existing release\n' >"$release_dir/qvos-test.iso"
preserve_stage=false
if publish_release_artifact "$publish_out" 2>/dev/null; then
  fail "qvOS ISO existing-artifact no-clobber"
fi
[[ $preserve_stage == "true" ]] ||
  fail "qvOS ISO existing-artifact stage retention"
[[ $(<"$release_dir/qvos-test.iso") == "existing release" ]] ||
  fail "qvOS ISO existing release preservation"

printf 'copy failure ISO\n' >"$publish_out/qvos-copy-fail.iso"
touch "$publish_out/qvos-copy-fail.iso"
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
[[ ! -e $release_dir/qvos-copy-fail.iso ]] ||
  fail "qvOS ISO failed-copy release preservation"
if compgen -G "$release_dir/.qvos-iso.partial.*" >/dev/null; then
  fail "qvOS ISO failed-copy partial cleanup"
fi
pass "qvOS ISO stages one pinned source and publishes without clobbering artifacts"

grep -Fq '(qvOS|Omarchy)([[:space:]]|$)' "$root/qvcore/boot/config-direct-boot" || fail "current and legacy EFI label detection"
grep -Fq -- '--label "qvOS"' "$root/qvcore/boot/config-direct-boot" || fail "qvOS EFI label"
grep -Fxq 'TARGET_OS_NAME="qvOS"' "$root/qvcore/boot/limine/default.conf" || fail "qvOS Limine OS name"
grep -Fxq 'interface_branding:' "$root/qvcore/boot/limine/limine.conf" || fail "qvOS Limine empty header"
grep -Fq -- '-name "qvos*.efi"' "$root/qvcore/boot/config-direct-boot" || fail "native qvOS UKI filename"
for retired_switcher in \
  bin/omarchy-branch-set \
  bin/omarchy-channel-set \
  bin/omarchy-update-branch; do
  [[ ! -e $root/$retired_switcher ]] ||
    fail "unsupported installed source switcher: $retired_switcher"
done
if rg -q 'omarchy-(branch-set|channel-set|update-branch)|Update channel' \
  "$root/bin/omarchy" "$root/qvcore/menu"; then
  fail "unsupported installed source channel route"
fi
pass "visible and boot identities are native while reviewed upstream interfaces remain explicit"

for retired_duplicate in \
  qvcore/diagnostics/debug \
  qvcore/share/notification \
  qvcore/menu/elephant/omarchy_background_selector.lua \
  qvcore/menu/elephant/omarchy_themes.lua \
  qvcore/menu/elephant/omarchy_unlocks.lua; do
  [[ ! -e $root/$retired_duplicate ]] ||
    fail "duplicated Omarchy implementation remains: $retired_duplicate"
done
[[ -x $root/qvcore/security/debug ]] ||
  fail "native qvOS debug owner is unavailable"
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
  "$test_root/.config/qvos/themes"

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
  if [[ " $* " == *' --dmenu '* ]]; then
    cat
  fi
} >>"$QVOS_TEST_MENU_LOG"
SCRIPT

unsafe_menu_home="$test_root/unsafe-menu-home"
external_menu="$test_root/external-menu"
install -d \
  "$unsafe_menu_home/.config/omarchy/extensions" \
  "$unsafe_menu_home/.config/qvos/extensions"
printf 'external personal menu\n' >"$external_menu"
ln -s "$external_menu" \
  "$unsafe_menu_home/.config/omarchy/extensions/menu.sh"
if HOME="$unsafe_menu_home" QVOS_PATH="$root" \
  "$root/qvcore/menu/install" --preflight \
  >"$test_root/unsafe-personal.out" \
  2>"$test_root/unsafe-personal.err"; then
  fail "linked personal menu preflight"
fi
grep -Fq 'Refusing an unsafe inherited personal menu extension:' \
  "$test_root/unsafe-personal.err" || fail "linked inherited menu diagnostic"
grep -Fqx 'external personal menu' "$external_menu" ||
  fail "linked inherited menu preservation"
unlink -- "$unsafe_menu_home/.config/omarchy/extensions/menu.sh"
ln -s "$external_menu" \
  "$unsafe_menu_home/.config/qvos/extensions/menu.sh"
if HOME="$unsafe_menu_home" QVOS_PATH="$root" \
  "$root/qvcore/menu/install" --preflight \
  >"$test_root/unsafe-native-personal.out" \
  2>"$test_root/unsafe-native-personal.err"; then
  fail "linked native personal menu preflight"
fi
grep -Fq 'Refusing an unsafe personal qvOS menu extension:' \
  "$test_root/unsafe-native-personal.err" ||
  fail "linked native personal menu diagnostic"
grep -Fqx 'external personal menu' "$external_menu" ||
  fail "linked native personal menu preservation"
unlink -- "$unsafe_menu_home/.config/qvos/extensions/menu.sh"
ln -s "$external_menu" \
  "$unsafe_menu_home/.config/omarchy/extensions/qvos-menu.sh"
if HOME="$unsafe_menu_home" QVOS_PATH="$root" \
  "$root/qvcore/menu/install" --preflight \
  >"$test_root/unsafe-overlay.out" \
  2>"$test_root/unsafe-overlay.err"; then
  fail "linked retired menu overlay preflight"
fi
grep -Fq 'Refusing an unsafe retired qvOS menu overlay:' \
  "$test_root/unsafe-overlay.err" || fail "linked menu overlay diagnostic"
grep -Fqx 'external personal menu' "$external_menu" ||
  fail "linked menu overlay preservation"

install -m 0600 /dev/stdin \
  "$test_root/.config/omarchy/extensions/menu.sh" <<'MENU'
[[ -f $HOME/.config/omarchy/extensions/qvos-menu.sh ]] && source "$HOME/.config/omarchy/extensions/qvos-menu.sh"
show_about() { printf "personal menu\n"; }
MENU
cp -a \
  "$test_root/.config/omarchy/extensions/menu.sh" \
  "$test_root/personal-menu.before"
git -C "$root" show \
  e4e308a7d53263e0270e398364315e9acd66a926:qvcore/menu/extension.sh \
  >"$test_root/.config/omarchy/extensions/qvos-menu.sh"
HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/menu/install" --install
grep -Fqx 'show_about() { printf "personal menu\n"; }' \
  "$test_root/.config/qvos/extensions/menu.sh" ||
  fail "personal menu extension migration"
[[ $(stat -c '%a' "$test_root/.config/qvos/extensions/menu.sh") == "600" ]] ||
  fail "personal menu extension mode preservation"
[[ ! -e $test_root/.config/omarchy/extensions/menu.sh &&
  ! -L $test_root/.config/omarchy/extensions/menu.sh ]] ||
  fail "inherited personal menu extension retirement"
if rg -q 'qvos-menu\.sh' "$test_root/.config/qvos/extensions/menu.sh"; then
  fail "retired qvOS menu overlay remains sourced"
fi
[[ ! -e $test_root/.config/omarchy/extensions/qvos-menu.sh ]] ||
  fail "exact generated qvOS menu overlay retirement"
mapfile -t menu_backups < <(
  find "$test_root/.config/qvos/extensions" -maxdepth 1 -type f \
    -name 'menu.sh.qvos-backup.*' -print
)
((${#menu_backups[@]} == 1)) || fail "personal menu backup inventory"
cmp -s "$test_root/personal-menu.before" "${menu_backups[0]}" ||
  fail "personal menu backup content"
install -d "$test_root/.config/omarchy/extensions"
printf 'modified retired overlay\n' \
  >"$test_root/.config/omarchy/extensions/qvos-menu.sh"
HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/menu/install" --install \
  >"$test_root/modified-overlay.out" \
  2>"$test_root/modified-overlay.err"
grep -Fq 'Preserving a modified retired qvOS menu overlay:' \
  "$test_root/modified-overlay.err" ||
  fail "modified retired menu overlay diagnostic"
grep -Fqx 'modified retired overlay' \
  "$test_root/.config/omarchy/extensions/qvos-menu.sh" ||
  fail "modified retired menu overlay preservation"
HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/menu/install" --status ||
  fail "modified inert menu overlay status"
pass "native qvOS menu migrates personal overrides and retires only its generated overlay"

stock_menu_home="$test_root/stock-menu-home"
install -d "$stock_menu_home/.config/omarchy/extensions"
printf 'historical stock backup\n' \
  >"$stock_menu_home/.config/omarchy/extensions/menu.sh.bak.123"
printf 'historical generated backup\n' \
  >"$stock_menu_home/.config/omarchy/extensions/menu.sh.qvos-backup.AbC123"
git -C "$root" show \
  74a3797cf0b57a19a458d3e96b19f48b7fbfc2de:config/omarchy/extensions/menu.sh \
  >"$stock_menu_home/.config/omarchy/extensions/menu.sh"
HOME="$stock_menu_home" QVOS_PATH="$root" \
  PATH="$test_bin:$root/bin:/usr/bin" \
  "$root/qvcore/menu/install" --install
cmp -s "$root/qvcore/config/files/qvos/extensions/menu.sh" \
  "$stock_menu_home/.config/qvos/extensions/menu.sh" ||
  fail "stock inherited menu replacement"
[[ ! -e $stock_menu_home/.config/omarchy/extensions/menu.sh &&
  ! -L $stock_menu_home/.config/omarchy/extensions/menu.sh ]] ||
  fail "stock inherited menu retirement"
grep -Fqx 'historical stock backup' \
  "$stock_menu_home/.local/state/qvos/menu-backups/legacy-extensions/menu.sh.bak.123" ||
  fail "historical stock menu-backup archive"
grep -Fqx 'historical generated backup' \
  "$stock_menu_home/.local/state/qvos/menu-backups/legacy-extensions/menu.sh.qvos-backup.AbC123" ||
  fail "historical generated menu-backup archive"
[[ ! -e $stock_menu_home/.config/omarchy/extensions ]] ||
  fail "empty inherited menu-extension root retirement"
pass "stock inherited menu state converges to the native qvOS default"

conflict_menu_home="$test_root/conflict-menu-home"
install -d \
  "$conflict_menu_home/.config/omarchy/extensions" \
  "$conflict_menu_home/.config/qvos/extensions"
printf 'custom inherited menu\n' \
  >"$conflict_menu_home/.config/omarchy/extensions/menu.sh"
printf 'custom native menu\n' \
  >"$conflict_menu_home/.config/qvos/extensions/menu.sh"
if HOME="$conflict_menu_home" QVOS_PATH="$root" \
  "$root/qvcore/menu/install" --preflight \
  >"$test_root/conflicting-menu.out" \
  2>"$test_root/conflicting-menu.err"; then
  fail "conflicting personal menu extensions preflight"
fi
grep -Fq 'Both qvOS and inherited personal menu extensions contain custom content' \
  "$test_root/conflicting-menu.err" || fail "personal menu conflict diagnostic"
grep -Fqx 'custom inherited menu' \
  "$conflict_menu_home/.config/omarchy/extensions/menu.sh" ||
  fail "conflicting inherited menu preservation"
grep -Fqx 'custom native menu' \
  "$conflict_menu_home/.config/qvos/extensions/menu.sh" ||
  fail "conflicting native menu preservation"
pass "conflicting personal menu state fails before mutation"

for menu_adapter in qv-menu omarchy-menu; do
  menu_output=$(
    HOME="$test_root" \
      QVOS_PATH="$root" \
      PATH="$test_bin:$root/bin:/usr/bin" \
      "$root/bin/$menu_adapter" about
  )
  [[ $menu_output == "personal menu" ]] ||
    fail "$menu_adapter personal override order"
done
if HOME="$test_root" QVOS_PATH="$root" \
  PATH="$test_bin:$root/bin:/usr/bin" \
  "$root/bin/qv-menu" one two \
  >"$test_root/menu-usage.out" \
  2>"$test_root/menu-usage.err"; then
  fail "menu accepts multiple destinations"
fi
grep -Fqx 'Usage: qv-menu [destination]' "$test_root/menu-usage.err" ||
  fail "menu argument diagnostic"
pass "native and compatibility menu routes preserve personal overrides and bounded input"

run_menu() {
  QVOS_TEST_LOCALSEND="$1" \
    QVOS_TEST_MENU_LOG="$menu_log" \
    HOME="$test_root" \
    QVOS_PATH="$root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/qv-menu" trigger
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
    == "qv-launch-task dns-configure"
' "$root/qvcore/config/files/waybar/config.jsonc" >/dev/null ||
  fail "Waybar network DNS route"
pass "network surfaces reuse their established owners"

set +e
share_output=$(
  QVOS_TEST_LOCALSEND=0 \
    QVOS_PATH="$root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/qv-share" clipboard 2>&1
)
share_status=$?
set -e
((share_status == 1)) || fail "missing LocalSend exit status"
[[ $share_output == "LocalSend is not installed" ]] || fail "missing LocalSend error"
pass "direct LocalSend route fails clearly when unavailable"

install -d \
  "$test_root/.config/qvos/themes/yaqyn" \
  "$test_root/custom-theme"
printf 'personal theme\n' >"$test_root/.config/qvos/themes/yaqyn/personal-marker"
cp -a "$root/qvcore/theme/yaqyn/." "$test_root/custom-theme/"
touch "$test_root/custom-theme/preview-unlock.png"
ln -s "$test_root/custom-theme" "$test_root/.config/qvos/themes/custom"
HOME="$test_root" QVOS_PATH="$root" \
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

HOME="$test_root" QVOS_PATH="$root" \
  lua - "$root" <<'LUA' || fail "qvOS Style entries"
local root = arg[1]

dofile(root .. "/qvcore/menu/elephant/qvos_themes.lua")
local themes = GetEntries()
assert(#themes == 2)
local yaqyn_theme
local custom_theme
for _, theme in ipairs(themes) do
  if theme.Text == "Yaqyn  " then yaqyn_theme = theme end
  if theme.Text == "Custom  " then custom_theme = theme end
end
assert(yaqyn_theme)
assert(yaqyn_theme.Preview:match("/%.config/qvos/themes/yaqyn/preview%.png$"))
assert(yaqyn_theme.Actions.activate == "qv-theme-set 'yaqyn'")
assert(custom_theme)
assert(custom_theme.Preview:match("/%.config/qvos/themes/custom/preview%.png$"))
assert(custom_theme.Actions.activate == "qv-theme-set 'custom'")

dofile(root .. "/qvcore/menu/elephant/qvos_unlocks.lua")
local unlocks = GetEntries()
assert(#unlocks == 2)
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
assert(custom_unlock.Preview:match("/%.config/qvos/themes/custom/preview%-unlock%.png$"))
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
grep -qx 'Name=Yaqyn' "$root/qvcore/boot/plymouth/qvos.plymouth" || fail "Plymouth theme identity"
grep -qx 'ConsoleLogBackgroundColor=0x1a1b26' \
  "$root/qvcore/boot/plymouth/qvos.plymouth" ||
  fail "Plymouth promoted live console background"
grep -qx 'Window.SetBackgroundTopColor(0.035, 0.035, 0.035);' \
  "$root/qvcore/boot/plymouth/qvos.script" ||
  fail "Plymouth promoted live top background"
grep -qx 'Window.SetBackgroundBottomColor(0.035, 0.035, 0.035);' \
  "$root/qvcore/boot/plymouth/qvos.script" ||
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
