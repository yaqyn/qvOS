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

[[ ! -e $root/qv/install/packaging/base.packages &&
  ! -e $root/qv/install/packaging/other.packages ]] ||
  fail "copied Omarchy package manifest remains"
[[ -x $root/qv/install/packaging/resolve ]] ||
  fail "qvOS package resolver mode"
grep -qx 'localsend' "$base_packages" ||
  fail "inherited LocalSend package resolution"
pass "qvOS resolves small deltas over the original Omarchy manifests"

grep -qx 'chromium' "$base_packages" || fail "Chromium package contract"
grep -qx 'alacritty' "$base_packages" || fail "Alacritty package contract"
grep -qx 'neovim' "$base_packages" || fail "Neovim package contract"
grep -qx 'omarchy-nvim' "$base_packages" || fail "qvOS Neovim package contract"
grep -qx 'wtype' "$base_packages" || fail "Codex Wayland input contract"
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
install -d "$refresh_source/qv/config/files/qvos" "$refresh_home"
printf 'staged source\n' >"$refresh_source/qv/config/files/qvos/path.conf"
HOME="$refresh_home" OMARCHY_PATH="$refresh_source" \
  "$root/qv/config/refresh" qvos/path.conf
[[ $(<"$refresh_home/.config/qvos/path.conf") == "staged source" ]] ||
  fail "OMARCHY_PATH config refresh"
pass "config refreshes honor staged and installed Omarchy roots"

grep -Fqx 'xdg-settings set default-web-browser chromium.desktop' "$root/qv/install/config/mimetypes" || fail "browser default contract"
grep -Fqx 'editor_desktop=nvim.desktop' "$root/qv/install/config/mimetypes" || fail "text MIME default contract"
if grep -Eq 'editor_desktop=(code|code-oss)\.desktop|command -v (code|code-oss)' "$root/qv/install/config/mimetypes"; then
  fail "retired Code text MIME preference"
fi
pass "Chromium, Alacritty, and Neovim are the qvOS defaults"

for retired_file_manager_package in nautilus nautilus-python sushi; do
  grep -Fqx "$retired_file_manager_package" \
    "$root/qv/install/packaging/base.exclusions" ||
    fail "$retired_file_manager_package disabled base package"
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

if grep -Eq '^(7zip|act|age|clang|cloudflared|cmake|codex|codex-cli|dos2unix|gdb|git-lfs|gitleaks|go-yq|hurl|hyperfine|infisical|just|lldb|llvm|lsof|mkcert|ninja|osv-scanner|pacman-contrib|pass-cli|postgresql-libs|proton-drive-cli|proton-vpn-cli|proton-vpn-daemon|protonmail-bridge|protonmail-bridge-core|ruby|rust|semgrep|sentry-cli|shellcheck|shfmt|sops|steam|strace|supabase|time|tinyxxd|valgrind|zip)$' "$base_packages" "$other_packages" ||
  grep -RqsF '@openai/codex' "$root/qv/install"; then
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
grep -Fqx 'localsend' "$root/install/omarchy-base.packages" ||
  fail "Omarchy base LocalSend package"
grep -Fqx 'sudo ufw allow 53317/udp' "$root/install/first-run/firewall.sh" ||
  fail "Omarchy LocalSend UDP firewall ownership"
grep -Fqx 'sudo ufw allow 53317/tcp' "$root/install/first-run/firewall.sh" ||
  fail "Omarchy LocalSend TCP firewall ownership"
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
pass "LocalSend and its network policy remain Omarchy-owned"
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
grep -Fqx '  "$OMARCHY_PATH/qv/direct/tool" install codex' \
  "$root/qv/install/configure" ||
  fail "base Codex does not install through the direct-tool owner"
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
pass "qvCORE stays two-stack while Codex remains base direct software"

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
  'steam|package|steam|tui|true|tui|true|omarchy-install-gaming-steam|omarchy-remove-gaming-steam' \
  "$root/qv/menu/software-actions.psv" ||
  fail "Steam lifecycle bypasses Omarchy's owners"
grep -Fq 'show_software_menu gaming' <<<"$install_gaming_override" ||
  fail "Steam install bypasses Omarchy's owner"
grep -Fq 'show_software_menu gaming' <<<"$remove_gaming_override" ||
  fail "Steam removal bypasses Omarchy's owner"
grep -Fq '  Omarchy' "$root/bin/omarchy-menu" || fail "upstream Omarchy learning entry"
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
  "$root/qv/config/files/hypr/qv/bindings.conf" \
  "$root/qv/waybar/overrides.jsonc"; then
  fail "retired qvOS feature menu"
fi
grep -Fq '`qv/config/refresh-hyprland` is the authoritative inventory' \
  "$root/qv/config/AGENTS.md" ||
  fail "qvOS Hyprland source ownership instruction"
grep -Fq 'otherwise update the' "$root/qv/config/AGENTS.md" ||
  fail "qvOS Hyprland top-level source instruction"
grep -Fq 'owned top-level source' "$root/qv/config/AGENTS.md" ||
  fail "qvOS Hyprland top-level source instruction"
[[ -x $root/qv/config/refresh-hyprland ]] ||
  fail "qvOS Hyprland config reconciler"
grep -Fqx '"$OMARCHY_PATH/qv/config/refresh-hyprland"' \
  "$root/bin/omarchy-refresh-hyprland" ||
  fail "Omarchy Hyprland refresh does not delegate to the config owner"
[[ ! -e $root/qv/hyprland ]] ||
  fail "redundant qvOS Hyprland domain remains"
grep -Fq 'three rings are system-critical or high-impact operations' \
  "$root/qv/tui/AGENTS.md" ||
  fail "qvOS TUI three-ring model role"
grep -Fq 'one ring is an ordinary safe task or' "$root/qv/tui/AGENTS.md" ||
  fail "qvOS TUI one-ring model role"
grep -Fq 'Important two- or three-ring loading and mutation flows never bind' \
  "$root/qv/tui/AGENTS.md" ||
  fail "qvOS TUI interruption confirmation rule"
grep -Fq 'One-ring actions are information surfaces' \
  "$root/qv/tui/AGENTS.md" ||
  fail "qvOS one-ring information contract"
grep -Fq 'Canceled results must say canceled' "$root/qv/tui/AGENTS.md" ||
  fail "qvOS TUI cancellation result rule"
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
grep -Fq 'bash "$OMARCHY_PATH/qv/install/first-run/apply"' \
  "$root/bin/omarchy-first-run" ||
  fail "qvOS first-run integration seam"
elephant_line=$(grep -nF 'bash "$OMARCHY_PATH/install/first-run/elephant.sh"' \
  "$root/bin/omarchy-first-run" | cut -d: -f1)
qvos_first_run_line=$(grep -nF 'bash "$OMARCHY_PATH/qv/install/first-run/apply"' \
  "$root/bin/omarchy-first-run" | cut -d: -f1)
((qvos_first_run_line > elephant_line)) ||
  fail "qvOS first-run overlay runs before inherited configuration is complete"
grep -Fqx '"$OMARCHY_PATH/qv/menu/install" --install' \
  "$root/qv/install/first-run/apply" ||
  fail "qvOS first-run menu reconciliation"
grep -Fq 'output="qvOS ${output#Omarchy }"' \
  "$root/qv/update/update-available" || fail "qvOS update status"
grep -Fq 'Update Omarchy' "$root/bin/omarchy-update-git" ||
  fail "original Omarchy update progress"
grep -Fq '# omarchy:summary=Safely update qvOS through the original Omarchy updater' \
  "$root/bin/omarchy-qvos-update" || fail "qvOS update help"
grep -Fq 'powers the Omarchy Menu' "$root/bin/omarchy-refresh-walker" ||
  fail "original Omarchy menu help"
grep -Fq 'Omarchy command center' "$root/bin/omarchy" ||
  fail "original Omarchy CLI heading"
grep -Fq 'GROUP_DESCRIPTIONS[restart]="Restart Omarchy components"' \
  "$root/bin/omarchy" || fail "original Omarchy restart help"
grep -Fq 'GROUP_DESCRIPTIONS[toggle]="Toggle Omarchy features"' \
  "$root/bin/omarchy" || fail "original Omarchy toggle help"
grep -Fq 'Name=qvOS (Hyprland uwsm)' "$root/qv/boot/wayland-sessions/omarchy.desktop" || fail "qvOS login session label"
grep -Fq 'NamePretty = "qvOS Unlocks"' "$root/qv/menu/elephant/omarchy_unlocks.lua" || fail "qvOS unlock provider label"
grep -Fq 'dofile(omarchy_path .. "/default/elephant/omarchy_unlocks.lua")' \
  "$root/qv/menu/elephant/omarchy_unlocks.lua" ||
  fail "qvOS unlock provider inherits Omarchy"
grep -Fq -- '--app-id=org.omarchy.terminal' "$root/qv/presentation/run" ||
  fail "inherited terminal app ID"
grep -Fq -- '--title=qvOS' "$root/qv/presentation/run" ||
  fail "qvOS terminal title"
grep -Fq 'Description=qvOS Battery Monitor Check' "$root/qv/config/files/systemd/user/omarchy-battery-monitor.service" || fail "qvOS battery service label"
grep -Fq 'Description=qvOS Battery Monitor Timer' "$root/qv/config/files/systemd/user/omarchy-battery-monitor.timer" || fail "qvOS battery timer label"
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
grep -Fq 'for attempt in 1 2 3' "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO bounded package download retries"
grep -Fq '/omarchy/qv/install/packaging/resolve' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO package resolution"
grep -Fq 'QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-installer' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO configurator integration"
grep -Fq 'QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-progress' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO progress fullscreen contract"
grep -Fq 'install -Dm755 /usr/local/bin/qvos-tui /mnt/usr/local/bin/qvos-tui' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS installed-system TUI payload"
grep -Fq 'mount --bind /var/log/omarchy-install.log /mnt/var/log/omarchy-install.log' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS continuous boot-install log"
grep -Fq 'QVOS_ISO_PROGRESS_PID="${qvos_iso_progress_pid:-}"' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS continuous boot-install TUI ownership"
grep -Fq 'if [[ -z ${QVOS_ISO_PROGRESS_PID:-} ]]; then' \
  "$root/qv/install/helpers/logging" ||
  fail "qvOS external install progress suppresses inherited monitor"

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
grep -Fq -- '-name "omarchy*.efi"' "$root/qv/boot/config-direct-boot" || fail "inherited Omarchy UKI filename"
grep -Fq 'GROUP_DESCRIPTIONS[branch]="Omarchy git branch management"' "$root/bin/omarchy" || fail "upstream branch identity"
pass "visible system branding is qvOS without renaming Omarchy internals"

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

install -d "$test_root/.config/omarchy/themes/yaqyn"
printf 'personal theme\n' >"$test_root/.config/omarchy/themes/yaqyn/personal-marker"
HOME="$test_root" OMARCHY_PATH="$root" "$root/qv/theme/install" >/dev/null
compgen -G "$test_root/.config/omarchy/themes/yaqyn.bak.*/personal-marker" >/dev/null ||
  fail "personal Yaqyn theme backup"

theme_list=$(HOME="$test_root" OMARCHY_PATH="$root" "$root/bin/omarchy-theme-list")
grep -Fqx 'Yaqyn' <<<"$theme_list" || fail "qvOS Yaqyn theme overlay"
grep -Fqx 'Tokyo Night' <<<"$theme_list" || fail "inherited Omarchy themes"
pass "Yaqyn is layered over the complete Omarchy theme catalog"

HOME="$test_root" OMARCHY_PATH="$root" lua - "$root" <<'LUA' || fail "qvOS Style entries"
local root = arg[1]

dofile(root .. "/default/elephant/omarchy_themes.lua")
local themes = GetEntries()
assert(#themes > 1)
local yaqyn_theme
for _, theme in ipairs(themes) do
  if theme.Text == "Yaqyn  " then yaqyn_theme = theme end
end
assert(yaqyn_theme)
assert(yaqyn_theme.Preview:match("/%.config/omarchy/themes/yaqyn/preview%.png$"))
assert(yaqyn_theme.Actions.activate == "omarchy-theme-set yaqyn")

dofile(root .. "/qv/menu/elephant/omarchy_unlocks.lua")
local unlocks = GetEntries()
local yaqyn_unlock
for _, unlock in ipairs(unlocks) do
  if unlock.Text == "Yaqyn  " then yaqyn_unlock = unlock end
end
assert(yaqyn_unlock)
assert(yaqyn_unlock.Preview == root .. "/qv/boot/plymouth/preview-unlock.png")
assert(
  yaqyn_unlock.Actions.activate
    == "omarchy-launch-floating-terminal-with-presentation 'omarchy-plymouth-reset'"
)
LUA
pass "dynamic Style catalogs preserve Omarchy themes and add Yaqyn"

grep -qx 'omarchy-theme-set "Yaqyn"' "$root/qv/install/config/theme" || fail "fresh install theme"
if rg -q 'chmod[[:space:]]+a\\+rw' \
  "$root/qv/install/config/theme" \
  "$root/bin/omarchy-install-browser"; then
  fail "world-writable browser policy setup"
fi
grep -Fq 'sudo install -d -o root -g root -m 0755 /etc/chromium/policies/managed' \
  "$root/qv/install/config/theme" ||
  fail "root-owned Chromium policy directory"
grep -Fq 'sudo chown "$USER:$policy_group" /etc/chromium/policies/managed/color.json' \
  "$root/qv/install/config/theme" ||
  fail "user-owned Chromium theme policy"
if rg -q 'chmod[[:space:]]+666' "$root/qv/install/helpers/logging"; then
  fail "world-writable install log"
fi
grep -Fq 'sudo chown "$USER:$install_group" "$OMARCHY_INSTALL_LOG_FILE"' \
  "$root/qv/install/helpers/logging" ||
  fail "desktop-owned install log"
grep -Fq 'sudo chmod 0640 "$OMARCHY_INSTALL_LOG_FILE"' \
  "$root/qv/install/helpers/logging" ||
  fail "restricted install log"
grep -qx 'Name=Yaqyn' "$root/qv/boot/plymouth/omarchy.plymouth" || fail "Plymouth theme identity"
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
