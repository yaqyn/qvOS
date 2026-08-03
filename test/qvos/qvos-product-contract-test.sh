#!/bin/bash
# shellcheck disable=SC2016
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

"$root/qv/install/packaging/resolve" base >"$base_packages"
"$root/qv/install/packaging/resolve" other >"$other_packages"

if rg -q '/home/qv(/|$)' "$root/qv/iso" "$root/qv/tui"; then
  fail "development-machine home path leaked into ISO-owned source"
fi
pass "ISO-owned source excludes development-machine home paths"

[[ -f $root/qv/install/packaging/base.packages &&
  -f $root/qv/install/packaging/other.packages ]] ||
  fail "native qvOS package manifest is missing"
for retired_package_layer in \
  install/omarchy-base.packages \
  install/omarchy-other.packages \
  qv/install/packaging/base.additions \
  qv/install/packaging/base.exclusions \
  qv/install/packaging/other.additions \
  qv/install/packaging/other.exclusions; do
  [[ ! -e $root/$retired_package_layer ]] ||
    fail "retired package layer remains: $retired_package_layer"
done
[[ -x $root/qv/install/packaging/resolve ]] ||
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
grep -Fq 'xdg-user-dirs-update --set' "$root/install/config/user-dirs.sh" ||
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

editor_env=$(bash -c 'source "$1"; printf "%s\n%s\n%s\n" "$EDITOR" "$VISUAL" "$SUDO_EDITOR"' _ "$root/qv/config/files/uwsm/default")
[[ $editor_env == $'nvim\nnvim\nnvim' ]] || fail "editor environment contract"

terminal_desktop=$(grep -vE '^($|#)' "$root/config/xdg-terminals.list" | head -n 1)
[[ $terminal_desktop == "Alacritty.desktop" ]] || fail "terminal default contract"

refresh_home="$test_root/refresh-home"
refresh_source="$test_root/refresh-source"
refresh_fail_bin="$test_root/refresh-fail-bin"
install -d \
  "$refresh_source/qv/config/files/qvos" \
  "$refresh_home/.config/qvos" \
  "$refresh_fail_bin"
printf 'staged source\n' >"$refresh_source/qv/config/files/qvos/path.conf"
printf 'personal config\n' >"$refresh_home/.config/qvos/path.conf"
HOME="$refresh_home" OMARCHY_PATH="$refresh_source" \
  "$root/qv/config/refresh" qvos/path.conf
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
printf 'future source\n' >"$refresh_source/qv/config/files/qvos/path.conf"
refresh_backup_count=$(
  find "$refresh_home/.config/qvos" \
    -maxdepth 1 \
    -name 'path.conf.bak.*' |
    wc -l
)
if HOME="$refresh_home" \
  OMARCHY_PATH="$refresh_source" \
  PATH="$refresh_fail_bin:/usr/bin" \
  "$root/qv/config/refresh" qvos/path.conf >/dev/null 2>&1; then
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

grep -Fqx 'xdg-settings set default-web-browser chromium.desktop' "$root/qv/install/config/mimetypes" || fail "browser default contract"
grep -Fqx 'editor_desktop=nvim.desktop' "$root/qv/install/config/mimetypes" || fail "text MIME default contract"
if grep -Eq 'editor_desktop=(code|code-oss)\.desktop|command -v (code|code-oss)' "$root/qv/install/config/mimetypes"; then
  fail "retired Code text MIME preference"
fi
pass "Chromium, Alacritty, and Neovim are the qvOS defaults"

for retired_file_manager_package in nautilus nautilus-python sushi; do
  if grep -Fqx "$retired_file_manager_package" "$base_packages"; then
    fail "$retired_file_manager_package remains in the qvOS base"
  fi
done
grep -Fq 'omarchy-cmd-missing nautilus && return 0' \
  "$root/qv/install/config/nautilus-python" ||
  fail "Nautilus configuration guard"
if grep -Eq '^[[:space:]]*nautilus([[:space:]]|$)' \
  "$root/bin/omarchy-theme-bg-install" \
  "$root/bin/omarchy-install-gaming-retroarch"; then
  fail "direct Nautilus launcher remains"
fi
pass "Thunar is singular while inherited Nautilus hooks remain safe to sync"

grep -qx 'gnome-keyring' "$base_packages" || fail "desktop keyring package contract"
grep -Fqx 'run_logged $OMARCHY_INSTALL/login/default-keyring.sh' "$root/install/login/all.sh" || fail "default keyring setup contract"
grep -Fq "pam_gnome_keyring\\.so/d" "$root/install/login/sddm.sh" || fail "SDDM keyring setup contract"
if grep -RqsE 'omarchy-pkg-drop[[:space:]]+gnome-keyring' "$root/migrations"; then
  fail "retired keyring removal migration"
fi

[[ ! -e $root/install/packaging/warp.sh ]] || fail "WARP fresh-install stage"
grep -Fqx '    omarchy-pkg-aur-add cloudflare-warp-nox-bin || return 1' \
  "$root/qv/network/setup-dns" || fail "on-demand WARP package contract"
if rg -q -i 'qvcore' "$root/qv/network/setup-dns"; then
  fail "DNS-owned WARP writes qvCORE state"
fi
grep -Fqx 'dns|󰐕|DNS|Settings · Connections|network,warp,cloudflare,quad9|Configure|present:omarchy-qvos-setup-dns' \
  "$root/qv/menu/concepts.psv" ||
  fail "WARP remains available through DNS configuration"
pass "WARP stays DNS-owned and installs only when selected"

if grep -Eq '^(7zip|act|age|clang|cloudflared|cmake|codex|codex-cli|dos2unix|gdb|git-lfs|gitleaks|go-yq|hurl|hyperfine|infisical|just|lldb|llvm|lsof|mkcert|ninja|osv-scanner|pacman-contrib|pass-cli|postgresql-libs|proton-drive-cli|proton-vpn-cli|proton-vpn-daemon|protonmail-bridge|protonmail-bridge-core|ruby|rust|semgrep|sentry-cli|shellcheck|shfmt|sops|steam|strace|supabase|time|tinyxxd|valgrind|zip)$' "$base_packages" "$other_packages"; then
  fail "qvCORE stack software leaked into the base package manifest"
fi
expected_qvcore_catalog=$'# component\tlabel\ticon\nproton\tProton\t󰌾\nqvdev\tqvDEV\t󰵮'
[[ $(<"$root/qv/core/catalog.tsv") == "$expected_qvcore_catalog" ]] ||
  fail "two-stack qvCORE catalog"
while IFS=$'\t' read -r component _; do
  [[ -n $component && $component != "#"* ]] || continue
  [[ -x $root/qv/core/$component.sh ]] ||
    fail "qvCORE stack owner is unavailable: $component"
  grep -Eq 'install\) install_stack ;;|\[\[ \$1 != "install" \]\]' \
    "$root/qv/core/$component.sh" ||
    fail "qvCORE stack lacks Install: $component"
  grep -Eq 'remove\) remove_stack ;;|\[\[ \$1 == "remove" \]\]' \
    "$root/qv/core/$component.sh" ||
    fail "qvCORE stack lacks Remove: $component"
done <"$root/qv/core/catalog.tsv"
for retired_qvcore_source in \
  qv/core/health.sh \
  qv/core/post-update-hook \
  qv/core/software-ownership.tsv \
  qv/core/software-removal-groups \
  qv/core/brave.sh \
  qv/core/media.sh \
  qv/core/share.sh \
  qv/core/share \
  qv/core/warp.sh \
  qv/core/dev.sh \
  qv/core/codex.sh \
  bin/omarchy-qvcore-status \
  bin/omarchy-qvcore-repair \
  bin/omarchy-qvcore-disable; do
  [[ ! -e $root/$retired_qvcore_source ]] ||
    fail "retired qvCORE source remains: $retired_qvcore_source"
done
[[ ! -e $root/qv/core/steam.sh ]] || fail "retired qvCORE Steam owner"
grep -Fqx 'localsend' "$base_packages" ||
  fail "qvOS base LocalSend package"
grep -Fqx '  run_fixed_command "$ufw" allow 53317/udp' \
  "$root/qv/install/first-run/root" ||
  fail "qvOS LocalSend UDP firewall ownership"
grep -Fqx '  run_fixed_command "$ufw" allow 53317/tcp' \
  "$root/qv/install/first-run/root" ||
  fail "qvOS LocalSend TCP firewall ownership"
grep -Fqx 'share||Share|More · Share|localsend,send|Send|menu:share' \
  "$root/qv/menu/concepts.psv" ||
  fail "LocalSend concept stays independent from qvCORE"
if rg -q -i 'qvcore share|qv/core/share' \
  "$root/bin/omarchy-qvos-share" \
  "$root/qv/install" \
  "$root/qv/menu" \
  "$root/qv/share"; then
  fail "retired qvCORE Share ownership reference"
fi
pass "LocalSend and its network policy remain base-owned"
if grep -Eq '^(warp|media)\|' "$root/qv/menu/concepts.psv"; then
  fail "retired WARP or Media qvCORE concept remains"
fi
grep -Fqx '# omarchy:group=qvcore' "$root/bin/omarchy-qvcore-remove" ||
  fail "qvCORE command group"
[[ -x $root/bin/omarchy-install-qvcore &&
  -x $root/bin/omarchy-qvcore-remove ]] ||
  fail "qvCORE Install and Remove commands"
[[ ! -e $root/qv/codex ]] ||
  fail "redundant qvOS Codex inspection domain remains"
grep -Fqx 'omarchy-npx-install @openai/codex codex' \
  "$root/qv/install/packaging/npx" ||
  fail "Omarchy Codex wrapper is not preserved"
if rg -qi '\bcodex\b' "$root/qv/direct" "$root/qv/install/configure"; then
  fail "qvOS retains a duplicate Codex installer"
fi
if grep -Eq "^alias qv=" "$root/qv/shell/aliases"; then
  fail "fragile qv alias remains"
fi
for retired_path in \
  bin/omarchy-qvos-block-upstream-maintenance \
  bin/omarchy-qvos-health \
  bin/omarchy-qvos-repair \
  bin/omarchy-qvos-system \
  qv/maintenance/essential-packages \
  qv/maintenance/qvos-block-upstream-maintenance \
  qv/maintenance/qvos-repair \
  qv/maintenance/qvos-system \
  qv/tui/bin/qvos-repair; do
  [[ ! -e $root/$retired_path ]] ||
    fail "retired qvOS Recovery path remains: $retired_path"
done
if rg -q 'qv/codex|qvos/codex|qv codex doctor' \
  "$root/qv" \
  "$root/bin" \
  "$root/install" \
  "$root/migrations"; then
  fail "retired qvOS Codex inspection reference remains"
fi
pass "qvCORE stays two-stack while Codex remains Omarchy-owned"

grep -Fqx 'qmk-hid' "$root/qv/install/packaging/other.packages" ||
  fail "qvOS Framework 16 offline package ownership"
grep -Fqx 'qmk-hid' "$other_packages" || fail "Framework 16 offline package contract"
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
(($(find "$keyring_dir" -maxdepth 1 -type f | wc -l) == 2)) || fail "clean keyring file set"
pass "desktop keyring support stays complete"

grep -Fq 'Text = "󱅾  Update qvOS"' \
  "$root/qv/menu/elephant/qvos_omarchy_menu.lua" ||
  fail "qvOS update menu icon"
grep -Fq 'Actions = { activate = "omarchy-launch-qvos-update" }' \
  "$root/qv/menu/elephant/qvos_omarchy_menu.lua" ||
  fail "qvOS update menu route"
update_override=$(
  sed -n '/^show_update_menu()/,/^}/p' "$root/qv/menu/extension.sh"
)
[[ $update_override == $'show_update_menu() {\n  omarchy-launch-qvos-update\n}' ]] ||
  fail "Update qvOS is not direct"
if rg -q 'qvos-system|qvOS System' \
  "$root/qv/menu/extension.sh" \
  "$root/qv/menu/concepts.psv" \
  "$root/qv/menu/search-intents.psv"; then
  fail "retired qvOS System menu route remains"
fi
install_gaming_override=$(
  sed -n '/^show_install_gaming_menu()/,/^}/p' "$root/qv/menu/extension.sh"
)
remove_gaming_override=$(
  sed -n '/^show_remove_gaming_menu()/,/^}/p' "$root/qv/menu/extension.sh"
)
grep -Fqx \
  'steam|package|steam|tui|true|tui|true|omarchy-install-gaming-steam|qv/menu/steam-remove' \
  "$root/qv/menu/software-actions.psv" ||
  fail "Steam lifecycle bypasses its safe removal owner"
grep -Fq 'show_software_menu gaming' <<<"$install_gaming_override" ||
  fail "Steam install bypasses Omarchy's owner"
grep -Fq 'show_software_menu gaming' <<<"$remove_gaming_override" ||
  fail "Steam removal bypasses Omarchy's owner"
grep -Fq '  qvOS Source' "$root/bin/omarchy-menu" || fail "qvOS learning entry"
grep -Fq 'https://github.com/Yaqyn-qvOS/qvOS' "$root/bin/omarchy-menu" ||
  fail "qvOS learning destination"
if rg -q 'actionRepair|qvos-repair|QVOS_REPAIR|Repair qvOS' \
  "$root/qv/tui"; then
  fail "retired qvOS Repair TUI action remains"
fi
grep -Fq '"format": "󱅾"' "$root/qv/waybar/overrides.jsonc" ||
  fail "qvOS Waybar noodle icon"
if grep -Fq '' "$root/qv/menu/extension.sh"; then
  fail "retired Omarchy menu glyph"
fi
if rg -q 'show_qvos_menu|omarchy-menu qvos|SUPER SHIFT ALT, SPACE' \
  "$root/qv/menu/extension.sh" \
  "$root/config/hypr/bindings.conf" \
  "$root/qv/waybar/overrides.jsonc"; then
  fail "retired qvOS feature menu"
fi
grep -Fq '`config/hypr/bindings.conf` is the single authoritative qvOS binding source.' \
  "$root/qv/config/AGENTS.md" ||
  fail "qvOS Hyprland source ownership instruction"
grep -Fq 'There is no inherited binding layer and no qvOS binding overlay.' \
  "$root/qv/config/AGENTS.md" ||
  fail "qvOS singular binding ownership instruction"
grep -Fq '`qv/config/refresh-hyprland` is the single restore owner.' \
  "$root/qv/config/AGENTS.md" ||
  fail "qvOS singular Hyprland restore instruction"
[[ -x $root/qv/config/refresh-hyprland ]] ||
  fail "qvOS Hyprland restore owner"
# shellcheck disable=SC2016
grep -Fqx 'exec "$OMARCHY_PATH/qv/config/refresh-hyprland" "$@"' \
  "$root/bin/omarchy-refresh-hyprland" ||
  fail "Hyprland compatibility route does not delegate to the config owner"
[[ ! -e $root/qv/hyprland ]] ||
  fail "redundant qvOS Hyprland domain remains"
grep -Fq 'three rings are system-critical or high-impact operations' \
  "$root/qv/tui/AGENTS.md" ||
  fail "qvOS TUI three-ring model role"
grep -Fq 'one ring is an ordinary safe task or' "$root/qv/tui/AGENTS.md" ||
  fail "qvOS TUI one-ring model role"
if ! grep -Fq 'Generic non-install mutations never bind, advertise, or react to' \
  "$root/qv/tui/AGENTS.md" ||
  ! grep -Fq 'Captured Install, qvOS Update, and ISO Build retain' \
    "$root/qv/tui/AGENTS.md"; then
  fail "qvOS TUI interruption policy"
fi
grep -Fq 'Ring count controls visual role only' \
  "$root/qv/tui/AGENTS.md" ||
  fail "qvOS task behavior is independent from visual ring role"
if ! grep -Fq 'Treat availability, active/default/applied state, behavior, and privilege as' \
  "$root/qv/tui/AGENTS.md" ||
  ! grep -Fq 'For every reachable matrix row, account for entry and Preparing' \
    "$root/qv/tui/AGENTS.md" ||
  ! grep -Fq 'complete state-to-action and screen matrix' \
    "$root/qv/menu/AGENTS.md" ||
  ! grep -Fq 'For a TUI-managed installable or defaultable lifecycle' \
    "$root/qv/tui/AGENTS.md"; then
  fail "qvOS TUI lifecycle screen matrix rule"
fi
if ! rg -Uq 'cancellation[[:space:]]+freezes progress immediately' \
  "$root/qv/tui/AGENTS.md" ||
  ! rg -Uq 'never animate[[:space:]]+toward `100%` or imply success' \
    "$root/qv/tui/AGENTS.md"; then
  fail "qvOS TUI cancellation result rule"
fi
if ! grep -Fq 'through one ordered pseudo-terminal stream' "$root/qv/tui/AGENTS.md" ||
  ! grep -Fq 'Retain the complete normalized history without line-count or' \
    "$root/qv/tui/AGENTS.md"; then
  fail "qvOS TUI live terminal output rule"
fi
if ! grep -Fq 'log-producing results keep `V` and `Ctrl+V` active' "$root/qv/tui/AGENTS.md" ||
  ! grep -Fq 'The boot finale is the exception' "$root/qv/tui/AGENTS.md" ||
  ! grep -Fq 'Never discard captured history for general' \
    "$root/qv/tui/AGENTS.md"; then
  fail "qvOS TUI completed-result log access rule"
fi
if ! grep -Fq '## Zero Duplication' "$root/AGENTS.md" ||
  ! grep -Fq 'A second consumer must call or extract it' "$root/AGENTS.md" ||
  ! grep -Fq 'leave no equivalent implementation behind' \
    "$root/AGENTS.md"; then
  fail "qvOS shared implementation and zero-duplication rule"
fi
if grep -Fq 'tea.WithInput(nil)' "$root/qv/tui/iso_progress.go"; then
  fail "qvOS output-only progress disabled terminal response consumption"
fi
grep -Fq 'omarchy-launch-qvos-update' "$root/qv/theme/yaqyn/mako.ini" ||
  fail "qvOS update notification TUI route"
grep -Fqx 'windowrule = float on, match:class ^org\.qvos\.tui$' \
  "$root/qv/config/files/hypr/qv/windows.conf" ||
  fail "qvOS TUI floating window contract"
grep -Fqx 'windowrule = size 1024 509, match:class ^org\.qvos\.tui$' \
  "$root/qv/config/files/hypr/qv/windows.conf" ||
  fail "qvOS TUI default window size"
grep -Fqx 'windowrule = center on, match:class ^org\.qvos\.tui$' \
  "$root/qv/config/files/hypr/qv/windows.conf" ||
  fail "qvOS TUI centered window contract"
grep -Fqx 'exec "$OMARCHY_PATH/qv/install/first-run/run" "$@"' \
  "$root/bin/omarchy-first-run" ||
  fail "qvOS first-run owner adapter"
elephant_line=$(grep -nF 'bash "$OMARCHY_PATH/install/first-run/elephant.sh"' \
  "$root/qv/install/first-run/run" | cut -d: -f1)
qvos_first_run_line=$(grep -nF '"$OMARCHY_PATH/qv/install/first-run/gnome-theme"' \
  "$root/qv/install/first-run/run" | cut -d: -f1)
((qvos_first_run_line > elephant_line)) ||
  fail "qvOS first-run theme runs before inherited session setup is complete"
grep -Fqx '"$OMARCHY_PATH/qv/menu/install" --install' \
  "$root/qv/install/first-run/run" ||
  fail "qvOS first-run menu reconciliation"
grep -Fq 'output="qvOS ${output#Omarchy }"' \
  "$root/qv/update/update-available" || fail "qvOS update status"
grep -Fq 'Update qvOS source' "$root/qv/update/update-source" ||
  fail "qvOS source update progress"
grep -Fq '# omarchy:summary=Safely update qvOS through its native update engine' \
  "$root/bin/omarchy-qvos-update" || fail "qvOS update help"
grep -Fq 'powers the qvOS Menu' "$root/bin/omarchy-refresh-walker" ||
  fail "qvOS menu help"
grep -Fq 'qvOS command center' "$root/bin/omarchy" ||
  fail "qvOS CLI heading"
grep -Fq 'GROUP_DESCRIPTIONS[restart]="Restart qvOS components"' \
  "$root/bin/omarchy" || fail "qvOS restart help"
grep -Fq 'GROUP_DESCRIPTIONS[toggle]="Toggle qvOS features"' \
  "$root/bin/omarchy" || fail "qvOS toggle help"
grep -Fq 'Name=qvOS (Hyprland uwsm)' "$root/qv/boot/wayland-sessions/omarchy.desktop" || fail "qvOS login session label"
grep -Fq 'NamePretty = "qvOS Unlocks"' "$root/qv/menu/elephant/omarchy_unlocks.lua" || fail "qvOS unlock provider label"
grep -Fq 'dofile(omarchy_path .. "/default/elephant/omarchy_unlocks.lua")' \
  "$root/qv/menu/elephant/omarchy_unlocks.lua" ||
  fail "qvOS unlock provider inherits Omarchy"
grep -Fq -- '--app-id=org.omarchy.terminal' "$root/qv/presentation/run" ||
  fail "inherited terminal app ID"
grep -Fq -- '--title=qvOS' "$root/qv/presentation/run" ||
  fail "qvOS terminal title"
grep -Fq 'Description=qvOS Battery Monitor Check' "$root/config/systemd/user/omarchy-battery-monitor.service" || fail "qvOS battery service label"
grep -Fq 'Description=qvOS Battery Monitor Timer' "$root/config/systemd/user/omarchy-battery-monitor.timer" || fail "qvOS battery timer label"
grep -Fq 'too small for qvOS layout' "$root/qv/tui/iso_config.go" || fail "qvOS installer layout error"
[[ ! -e $root/qv/tui/bin/qvos-apply ]] ||
  fail "unsupported qvOS apply action"
if rg -q '"APPLY"|qvos-apply|QVOS_INSTALL_SCRIPT' "$root/qv/tui"; then
  fail "unsupported qvOS apply route"
fi

iso_build="$root/qv/tui/bin/qvos-build"
grep -Fq 'omarchy_iso_ref="${QVOS_OMARCHY_ISO_REF:-main}"' "$iso_build" ||
  fail "qvOS ISO branch matching Omarchy master"
grep -Fq 'default-branch change is not permission to follow it' \
  "$root/qv/iso/AGENTS.md" ||
  fail "qvOS ISO compatibility pin instruction"
grep -Fq 'freeze feature work until its' "$root/qv/iso/AGENTS.md" ||
  fail "qvOS release-candidate feature freeze"
grep -Fq 'An ISO is a development artifact until every base gate' \
  "$root/qv/iso/README.md" ||
  fail "qvOS ISO release evidence gate"
grep -Fq 'prove that its embedded qvOS source equals' \
  "$root/qv/iso/README.md" ||
  fail "qvOS ISO embedded-source proof"
grep -Fq 'Never overwrite this development installation for rehearsal.' \
  "$root/qv/iso/README.md" ||
  fail "qvOS ISO safe installation rehearsal"
grep -Fq 'base passes, test Proton and qvDEV Install and Uninstall separately' \
  "$root/qv/iso/README.md" ||
  fail "qvOS optional-stack release rehearsal"
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
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO builder mirror validation"
grep -Fq 'DisableDownloadTimeout' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO slow-link builder support"
grep -Fq -- '-buildvcs=false' "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO reproducible TUI build"
[[ -x $root/qv/tui/source-hash ]] || fail "qvOS TUI source-hash owner mode"
[[ $("$root/qv/tui/source-hash" "$root/qv/tui") =~ ^[0-9a-f]{64}$ ]] ||
  fail "qvOS TUI source-hash owner output"
grep -Fq '"$source_dir/source-hash" "$source_dir"' "$root/qv/tui/install" ||
  fail "qvOS TUI installer source-hash ownership"
grep -Fq 'qvos_tui_source_hash=$("$qvos_tui_source/source-hash" "$qvos_tui_source")' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO TUI source-hash ownership"
grep -Fq -- '-X main.buildSourceHash=$qvos_tui_source_hash' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO TUI source provenance"
grep -Fq 'safe.directory="$build_cache_dir/airootfs/root/omarchy"' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO command-scoped embedded source trust"
grep -Fq 'config --local core.logAllRefUpdates false' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO embedded source reflog suppression"
grep -Fq 'rm -rf -- "$build_cache_dir/airootfs/root/omarchy/.git/logs"' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO embedded source reflog cleanup"
grep -Fq 'for attempt in 1 2 3' "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO bounded package download retries"
grep -Fq 'XferCommand = /usr/bin/curl --http1.1' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO HTTP/1.1 package transport"
grep -Fq -- '--retry 5 --retry-all-errors' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO bounded curl retries"
grep -Fq '/omarchy/qv/install/packaging/resolve' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO package resolution"
grep -Fq 'QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-installer' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO configurator integration"
grep -Fq 'QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-progress' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO progress fullscreen contract"
grep -Fq 'root/omarchy/qv/boot/plymouth/' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO live Plymouth owner"
grep -Fq 'root/omarchy/qv/iso/syslinux-splash.png' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO Syslinux splash owner"
[[ $(magick identify -format '%wx%h' "$root/qv/iso/syslinux-splash.png") == "640x480" ]] ||
  fail "qvOS Syslinux splash dimensions"
[[ $(magick "$root/qv/iso/syslinux-splash.png" -depth 8 -format '%[hex:p{0,0}]' info:) == "000000" ]] ||
  fail "qvOS Syslinux exact-black background"
[[ $(magick identify -format '%[colorspace]' "$root/qv/iso/syslinux-splash.png") == "Gray" ]] ||
  fail "qvOS Syslinux splash retained a chromatic pixel"
for syslinux_grayscale_contract in \
  'MENU COLOR border       30;40   #00000000 #00000000 none' \
  'MENU COLOR title        1;37;40 #ffd8d8d8 #00000000 std' \
  'MENU COLOR sel          7;37;40 #ffffffff #ff303030 all'; do
  grep -Fq "$syslinux_grayscale_contract" \
    "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
    fail "qvOS Syslinux grayscale menu: $syslinux_grayscale_contract"
done
grep -Fq 'set_qvos_console_colors' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO console palette owner"
iso_patch_additions=$(sed -n '/^+++ /! s/^+//p' "$root/qv/iso/omarchy-iso-qvos-tui.patch")
for retired_iso_color in 1a1b26 f7768e a9b1d6 c0caf5 9ece6a e0af68 7aa2f7 bb9af7 7dcfff; do
  if grep -Fqi "$retired_iso_color" <<<"$iso_patch_additions"; then
    fail "qvOS ISO retained inherited Tokyo Night color: $retired_iso_color"
  fi
done
grep -Fq 'echo -en "\e]P0000000"' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO exact-black console background"
grep -Fq 'echo -en "\e]P1b00000"' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO normal red console accent"
grep -Fq 'echo -en "\e]P9d00000"' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
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
    "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
    fail "qvOS ISO boot branding: $qvos_boot_branding"
done
grep -Fq 'install -Dm755 /usr/local/bin/qvos-tui /mnt/usr/local/bin/qvos-tui' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS installed-system TUI payload"
grep -Fq 'mount --bind /var/log/omarchy-install.log /mnt/var/log/omarchy-install.log' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS continuous boot-install log"
grep -Fq 'stop_qvos_iso_progress' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS live-media progress stop before target install"
grep -Fq 'QVOS_ISO_PROGRESS_PID=$!' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS live-media shared progress process tracking"
grep -Fq 'stop_log_output' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS live-media shared progress teardown"
grep -Fq 'qv/iso/source-permissions' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO tracked executable-mode integration"
grep -Fq 'if [[ -n ${OMARCHY_CHROOT_INSTALL:-} && -n $qvos_tui && -x $qvos_tui ]]; then' \
  "$root/install/helpers/logging.sh" ||
  fail "qvOS target install progress ownership"
grep -Fq 'QVOS_ISO_PROGRESS_PID=$!' \
  "$root/install/helpers/logging.sh" ||
  fail "qvOS target install progress process tracking"
grep -Fq 'kill -KILL "$QVOS_ISO_PROGRESS_PID"' \
  "$root/install/helpers/logging.sh" ||
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
  export OMARCHY_INSTALL_LOG_FILE="$test_root/target-install.log"
  # shellcheck disable=SC1091
  source "$root/install/helpers/logging.sh"
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

source_permissions="$root/qv/iso/source-permissions"
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

grep -Fq '(qvOS|Omarchy)([[:space:]]|$)' "$root/qv/boot/config-direct-boot" || fail "current and legacy EFI label detection"
grep -Fq -- '--label "qvOS"' "$root/qv/boot/config-direct-boot" || fail "qvOS EFI label"
grep -Fxq 'TARGET_OS_NAME="qvOS"' "$root/qv/boot/limine/default.conf" || fail "qvOS Limine OS name"
grep -Fxq 'interface_branding:' "$root/qv/boot/limine/limine.conf" || fail "qvOS Limine empty header"
grep -Fq -- '-name "omarchy*.efi"' "$root/qv/boot/config-direct-boot" || fail "inherited Omarchy UKI filename"
for retired_switcher in \
  bin/omarchy-branch-set \
  bin/omarchy-channel-set \
  bin/omarchy-update-branch; do
  [[ ! -e $root/$retired_switcher ]] ||
    fail "unsupported installed source switcher: $retired_switcher"
done
if rg -q 'omarchy-(branch-set|channel-set|update-branch)|Update channel' \
  "$root/bin/omarchy" "$root/bin/omarchy-menu" "$root/qv/menu"; then
  fail "unsupported installed source channel route"
fi
pass "visible system branding is qvOS while compatibility internals remain stable"

for retired_duplicate in \
  qv/diagnostics/debug \
  qv/share/notification \
  qv/menu/elephant/omarchy_background_selector.lua \
  qv/menu/elephant/omarchy_themes.lua; do
  [[ ! -e $root/$retired_duplicate ]] ||
    fail "duplicated Omarchy implementation remains: $retired_duplicate"
done
pass "debug, capture notifications, and inherited launcher providers stay Omarchy-owned"
[[ ! -e $root/qv/launcher ]] ||
  fail "redundant qvOS launcher domain"
if rg -q 'qv/launcher' "$root/qv" "$root/bin" "$root/install" "$root/migrations"; then
  fail "qvOS launcher ownership reference"
fi

if grep -Eq '^alias (c|cx|ic|ix|icx)=' "$root/qv/shell/aliases"; then
  fail "disabled AI aliases"
fi
pass "disabled AI aliases stay out of the default shell"

mapfile -t qvos_tests < <(
  find "$root/test/qvos" -maxdepth 1 -type f \
    \( -name '*-test.sh' -o -name 'run.sh' \) |
    sort
)
((${#qvos_tests[@]} > 0)) || fail "qvOS test entrypoint inventory"
for qvos_test in "${qvos_tests[@]}"; do
  [[ -x $qvos_test ]] || fail "$(basename "$qvos_test") executable mode"
done
pass "qvOS-owned test entrypoints are executable"

install -d \
  "$test_bin" \
  "$test_root/.config/omarchy/extensions" \
  "$test_root/.config/omarchy/themes"

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

install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-refresh-config" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-walker" <<'SCRIPT'
#!/bin/bash
{
  printf '%s\n' "$*"
  cat
} >>"$QVOS_TEST_MENU_LOG"
SCRIPT

printf '%s\n' 'show_about() { printf "personal menu\n"; }' \
  >"$test_root/.config/omarchy/extensions/menu.sh"
HOME="$test_root" OMARCHY_PATH="$root" "$root/qv/menu/install" --install
grep -Fqx 'show_about() { printf "personal menu\n"; }' \
  "$test_root/.config/omarchy/extensions/menu.sh" ||
  fail "personal Omarchy menu extension preservation"
cmp -s \
  "$root/qv/menu/extension.sh" \
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
' "$root/qv/waybar/overrides.jsonc" >/dev/null ||
  fail "Waybar network DNS route"
pass "network surfaces reuse their established owners"

set +e
share_output=$(
  QVOS_TEST_LOCALSEND=0 \
    OMARCHY_PATH="$root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/omarchy-qvos-share" clipboard 2>&1
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
cp -a "$root/qv/theme/yaqyn/." "$test_root/custom-theme/"
touch "$test_root/custom-theme/preview-unlock.png"
ln -s "$test_root/custom-theme" "$test_root/.config/omarchy/themes/custom"
HOME="$test_root" OMARCHY_PATH="$root" "$root/qv/theme/install" >/dev/null
compgen -G "$test_root/.local/state/qvos/theme-backups/yaqyn.*/personal-marker" >/dev/null ||
  fail "personal Yaqyn theme backup"

theme_list=$(HOME="$test_root" OMARCHY_PATH="$root" "$root/bin/omarchy-theme-list")
grep -Fqx 'Yaqyn' <<<"$theme_list" || fail "bundled qvOS Yaqyn theme"
grep -Fqx 'Custom' <<<"$theme_list" || fail "linked compatible user theme"
if grep -Fqx 'Tokyo Night' <<<"$theme_list"; then
  fail "retired inherited theme catalog"
fi
pass "Yaqyn is the only bundled theme while compatible user themes remain available"

HOME="$test_root" OMARCHY_PATH="$root" lua - "$root" <<'LUA' || fail "qvOS Style entries"
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
assert(yaqyn_theme.Actions.activate == "omarchy-theme-set 'yaqyn'")
assert(custom_theme)
assert(custom_theme.Preview:match("/%.config/omarchy/themes/custom/preview%.png$"))
assert(custom_theme.Actions.activate == "omarchy-theme-set 'custom'")

dofile(root .. "/qv/menu/elephant/omarchy_unlocks.lua")
local unlocks = GetEntries()
local yaqyn_unlock
local custom_unlock
for _, unlock in ipairs(unlocks) do
  if unlock.Text == "Yaqyn  " then yaqyn_unlock = unlock end
  if unlock.Text == "Custom  " then custom_unlock = unlock end
end
assert(yaqyn_unlock)
assert(yaqyn_unlock.Preview == root .. "/qv/boot/plymouth/preview-unlock.png")
assert(
  yaqyn_unlock.Actions.activate
    == "omarchy-launch-floating-terminal-with-presentation 'omarchy-plymouth-reset'"
)
assert(custom_unlock)
assert(custom_unlock.Preview:match("/%.config/omarchy/themes/custom/preview%-unlock%.png$"))
LUA
pass "dynamic Style catalogs expose Yaqyn and compatible user themes only"

grep -qx 'omarchy-theme-set "Yaqyn"' "$root/qv/theme/configure" || fail "fresh install theme"
if rg -q 'chmod[[:space:]]+a\\+rw' \
  "$root/qv/theme/configure" \
  "$root/bin/omarchy-install-browser"; then
  fail "world-writable browser policy setup"
fi
grep -Fq 'sudo install -d -o root -g root -m 0755 /etc/chromium/policies/managed' \
  "$root/qv/theme/configure" ||
  fail "root-owned Chromium policy directory"
grep -Fq 'sudo chown "$USER:$policy_group" /etc/chromium/policies/managed/color.json' \
  "$root/qv/theme/configure" ||
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
[[ -x $root/qv/install/helpers/error-title ]] ||
  fail "qvOS installer error-title owner mode"
[[ $("$root/qv/install/helpers/error-title") == "qvOS installation stopped!" ]] ||
  fail "qvOS installer error title"
grep -Fq 'qvos_owner="$OMARCHY_PATH/qv/install/helpers/error-title"' \
  "$root/install/helpers/errors.sh" ||
  fail "inherited installer error branding delegation"
grep -qx 'Name=Yaqyn' "$root/qv/boot/plymouth/omarchy.plymouth" || fail "Plymouth theme identity"
grep -qx 'ConsoleLogBackgroundColor=0x1a1b26' \
  "$root/qv/boot/plymouth/omarchy.plymouth" ||
  fail "Plymouth promoted live console background"
grep -qx 'Window.SetBackgroundTopColor(0.035, 0.035, 0.035);' \
  "$root/qv/boot/plymouth/omarchy.script" ||
  fail "Plymouth promoted live top background"
grep -qx 'Window.SetBackgroundBottomColor(0.035, 0.035, 0.035);' \
  "$root/qv/boot/plymouth/omarchy.script" ||
  fail "Plymouth promoted live bottom background"
command -v magick >/dev/null 2>&1 || fail "Plymouth asset color verifier"
[[ $(magick "$root/qv/boot/plymouth/bullet.png" -depth 8 -format '%[hex:p{7,7}]' info:) == "505050FF" ]] ||
  fail "Plymouth promoted live password accent"
[[ $(magick "$root/qv/boot/plymouth/progress_bar.png" -depth 8 -format '%[hex:p{150,5}]' info:) == "505050" ]] ||
  fail "Plymouth promoted live progress accent"
[[ $(magick "$root/qv/boot/plymouth/preview-unlock.png" -depth 8 -format '%[hex:p{0,0}]' info:) == "090909" ]] ||
  fail "Plymouth promoted live preview background"
[[ $(magick "$root/qv/boot/plymouth/preview-unlock.png" -depth 8 -format '%[hex:p{840,697}]' info:) == "505050" ]] ||
  fail "Plymouth promoted live preview accent"

limine_theme="$root/qv/boot/limine/limine.conf"
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
grep -qx 'Name=Yaqyn' "$root/qv/boot/sddm/metadata.desktop" || fail "SDDM theme identity"
pass "fresh theme policies are scoped to the desktop user and named Yaqyn"

if [[ -e $root/qv/theme/yaqyn/unlock.png || -e $root/qv/theme/yaqyn/preview-unlock.png ]]; then
  fail "theme-specific unlock variant"
fi
pass "the unlock catalog has no bundled variants"

vsix="$root/qv/theme/yaqyn/vscode/extension/yaqyn-theme-0.1.0.vsix"
vsix_manifest=$(unzip -p "$vsix" extension/package.json)
[[ $(jq -r '.name + "|" + .displayName + "|" + .contributes.themes[0].label' <<<"$vsix_manifest") == "yaqyn-theme|Yaqyn|Yaqyn" ]] || fail "Yaqyn VS Code package"
cmp -s \
  <(unzip -p "$vsix" extension/package.json) \
  "$root/qv/theme/yaqyn/vscode/extension/package.json" ||
  fail "Yaqyn VS Code package source drift"
vsix_metadata=$(unzip -p "$vsix" extension.vsixmanifest)
grep -Fq 'https://github.com/Yaqyn-qvOS/qvOS.git' <<<"$vsix_metadata" ||
  fail "Yaqyn VS Code package repository"
if grep -Fq 'github.com/yaqyn/qv' <<<"$vsix_metadata"; then
  fail "Yaqyn VS Code package stale repository"
fi
pass "the bundled VS Code theme is Yaqyn end to end"
