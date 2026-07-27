#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
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

grep -qx 'chromium' "$root/qv/install/packaging/base.packages" || fail "Chromium package contract"
grep -qx 'alacritty' "$root/qv/install/packaging/base.packages" || fail "Alacritty package contract"
grep -qx 'neovim' "$root/qv/install/packaging/base.packages" || fail "Neovim package contract"
grep -qx 'omarchy-nvim' "$root/qv/install/packaging/base.packages" || fail "qvOS Neovim package contract"

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
  grep -Fqx "# $retired_file_manager_package" \
    "$root/qv/install/packaging/base.packages" ||
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

grep -qx 'gnome-keyring' "$root/qv/install/packaging/base.packages" || fail "desktop keyring package contract"
grep -Fqx 'run_logged $OMARCHY_INSTALL/login/default-keyring.sh' "$root/install/login/all.sh" || fail "default keyring setup contract"
grep -Fq "pam_gnome_keyring\\.so/d" "$root/install/login/sddm.sh" || fail "SDDM keyring setup contract"
if grep -RqsE 'omarchy-pkg-drop[[:space:]]+gnome-keyring' "$root/migrations"; then
  fail "retired keyring removal migration"
fi

[[ ! -e $root/install/packaging/warp.sh ]] || fail "WARP fresh-install stage"
grep -Fqx '    omarchy-pkg-aur-add cloudflare-warp-nox-bin || return 1' \
  "$root/qv/network/setup-dns" || fail "on-demand WARP package contract"
pass "WARP stays optional and installs only when selected"

if grep -Eq '^(act|age|brave-origin-beta-bin|cloudflare-warp-nox-bin|cloudflared|codex|codex-cli|gitleaks|hurl|infisical|localsend|mkcert|osv-scanner|pass-cli|proton-drive-cli|proton-vpn-cli|proton-vpn-daemon|protonmail-bridge|protonmail-bridge-core|semgrep|sentry-cli|sops|steam|supabase)$' "$root"/qv/install/packaging/*.packages ||
  grep -RqsF '@openai/codex' "$root/qv/install"; then
  fail "qvCORE application leaked into the base installation"
fi
expected_qvcore_catalog=$'# type\tcomponent\tlabel\ticon\nsetup\twarp\tWARP\t󰖂\napp\tbrave-origin\tBrave\t󰖟\nsetup\tshare\tShare\t\napp\tdev\tDevel\t󰵮\napp\tcodex\tCodex\t󱚤\nsetup\tproton\tProton\t󰌾\nsetup\tsteam\tGaming Dependencies\t\napp\tmedia\tMedia\t󰕧'
[[ $(<"$root/qv/core/catalog.tsv") == "$expected_qvcore_catalog" ]] ||
  fail "qvCORE catalog classification"
[[ $(sed '/^#/d;/^$/d' "$root/qv/maintenance/protected-user-bin") == "qv" ]] ||
  fail "qvOS regular user command protection inventory"
[[ $(sed '/^#/d;/^$/d' "$root/qv/core/software-removal-groups") == \
  $'brave-origin\tbrowser profile and personal data are preserved\nproton\tcloud data and saved authentication are preserved\nsteam\tgame libraries, configuration, and shared gaming dependencies are preserved' ]] ||
  fail "qvCORE coordinated software-removal inventory"
while IFS=$'\t' read -r type component _; do
  [[ $type == "setup" ]] || continue
  ownership_count=$(
    awk -F '\t' -v component="$component" '
      $1 == component { count++ }
      END { print count + 0 }
    ' "$root/qv/core/software-ownership.tsv"
  )
  if ((ownership_count > 1)) &&
    ! grep -q "^${component}"$'\t' "$root/qv/core/software-removal-groups"; then
    fail "multi-artifact setup lacks coordinated removal: $component"
  fi
done <"$root/qv/core/catalog.tsv"
while IFS=$'\t' read -r component _; do
  [[ -n $component && $component != "#"* ]] || continue
  [[ -x $root/qv/core/$component.sh ]] ||
    fail "coordinated removal owner is unavailable: $component"
  grep -Fq -- '--remove [--check|--yes]' "$root/qv/core/$component.sh" ||
    fail "coordinated removal owner lacks preflight and confirmation: $component"
done <"$root/qv/core/software-removal-groups"
grep -Fq 'qvcore-setup' "$root/qv/maintenance/personal-software" ||
  fail "multi-artifact qvCORE setup removal grouping"
grep -Fq '"$qvcore_owner_dir/$component.sh" --remove --check' \
  "$root/qv/maintenance/personal-software" ||
  fail "grouped qvCORE removal owner preflight"
grep -Fqx '  install_group app' "$root/qv/core/install" ||
  fail "qvCORE application install group"
grep -Fqx '  install_group setup' "$root/qv/core/install" ||
  fail "qvCORE managed setup install group"
grep -Fqx 'omarchy-install-gaming-steam' "$root/qv/core/steam.sh" || fail "qvCORE Steam delegates to Omarchy"
grep -Fq 'state_file="$HOME/.local/state/qvos/qvcore/steam"' \
  "$root/qv/core/steam.sh" ||
  fail "qvCORE Steam explicit ownership state"
grep -Fq 'echo "available"' "$root/qv/core/steam.sh" ||
  fail "independent Steam availability state"
grep -Fqx '# qvcore:managed-setup=1' "$root/qv/core/warp.sh" ||
  fail "qvCORE WARP managed setup"
grep -Fqx '# qvcore:app-integration=1' "$root/qv/core/codex.sh" ||
  fail "qvCORE Codex app integration"
grep -Fqx '    [[ $type == "setup" ]] || continue' "$root/qv/core/health.sh" ||
  fail "qvCORE setup-only health catalog"
if grep -Eq 'dev|codex|media|brave-origin' \
  <(sed -n '/^setup_components=/,/^declare -A/p' "$root/qv/core/health.sh"); then
  fail "qvCORE app hard-coded into setup health"
fi
grep -Fqx '# omarchy:group=qvcore' "$root/bin/omarchy-qvcore-status" ||
  fail "qvCORE command group"
[[ -x $root/bin/omarchy-qvcore-status &&
  -x $root/bin/omarchy-qvcore-repair &&
  -x $root/bin/omarchy-qvcore-remove ]] ||
  fail "qvCORE health commands"
[[ -x $root/bin/omarchy-qvos-health ]] ||
  fail "qvOS base health command"
[[ -x $root/bin/omarchy-qvos-system &&
  -x $root/qv/maintenance/qvos-system ]] ||
  fail "qvOS unified system hub"
[[ -x $root/qv/maintenance/qv ]] ||
  fail "qvOS TTY recovery front door"
grep -Fqx '  runtime_repair="$HOME/.local/share/qvos/maintenance/qvos-repair"' \
  "$root/qv/maintenance/qv" ||
  fail "qv repair runtime location"
grep -Fqx '  exec "$runtime_repair" "$@"' \
  "$root/qv/maintenance/qv" ||
  fail "qv repair runtime delegation"
grep -Fqx '  runtime_system="$HOME/.local/share/qvos/maintenance/qvos-system"' \
  "$root/qv/maintenance/qv" ||
  fail "qv system runtime location"
grep -Fqx '  exec "$runtime_system" "$@"' \
  "$root/qv/maintenance/qv" ||
  fail "qv system runtime delegation"
if grep -Eq "^alias qv=" "$root/qv/shell/aliases"; then
  fail "fragile qv alias remains"
fi
grep -Fqx 'xdg-desktop-portal-hyprland' \
  "$root/qv/maintenance/essential-packages" ||
  fail "qvOS recovery essential policy"
pass "qvCORE apps stay personal while managed setups own lifecycle health"

grep -Fqx 'qmk-hid' "$root/qv/install/packaging/other.packages" || fail "Framework 16 offline package contract"
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

grep -Fq '󱅾  qvOS' "$root/qv/menu/extension.sh" ||
  fail "qvOS update menu icon"
grep -Fq '*qvOS*) present_terminal omarchy-qvos-update ;;' \
  "$root/qv/menu/extension.sh" ||
  fail "qvOS update menu route"
grep -Fq '*System*) present_terminal omarchy-qvos-system ;;' \
  "$root/qv/menu/extension.sh" ||
  fail "qvOS unified system menu route"
if grep -Fq 'omarchy-qvos-system --software' "$root/qv/menu/extension.sh" ||
  grep -Fq 'qvOS System' <(
    sed -n '/^show_update_menu()/,/^}/p' "$root/qv/menu/extension.sh"
  ); then
  fail "software or maintenance action appears in a competing menu domain"
fi
install_gaming_override=$(
  sed -n '/^show_install_gaming_menu()/,/^}/p' "$root/qv/menu/extension.sh"
)
remove_gaming_override=$(
  sed -n '/^show_remove_gaming_menu()/,/^}/p' "$root/qv/menu/extension.sh"
)
grep -Fq '*Steam*) present_terminal "omarchy-install-qvcore steam" ;;' \
  <<<"$install_gaming_override" ||
  fail "Steam install bypasses its qvCORE owner"
grep -Fq '/qv/core/steam.sh --remove" ;;' <<<"$remove_gaming_override" ||
  fail "Steam removal bypasses its preservation-safe qvCORE owner"
if grep -Fq 'omarchy-remove-gaming-steam' <<<"$remove_gaming_override"; then
  fail "qvOS menu exposes destructive inherited Steam removal"
fi
grep -Fq '  Omarchy' "$root/bin/omarchy-menu" || fail "upstream Omarchy learning entry"
grep -Fq '"01", "REPAIR", "Repair qvOS"' "$root/qv/tui/main.go" || fail "qvOS repair identity"
grep -Fq '"format": "󱅾"' "$root/qv/waybar/overrides.jsonc" ||
  fail "qvOS Waybar noodle icon"
if grep -Fq '' "$root/qv/menu/extension.sh"; then
  fail "retired Omarchy menu glyph"
fi
grep -Fq 'qvOS menu, exec, omarchy-menu qvos' \
  "$root/qv/config/files/hypr/qv/bindings.conf" ||
  fail "qvOS binding description"
grep -Fq 'bash "$OMARCHY_PATH/qv/install/first-run/apply"' \
  "$root/bin/omarchy-first-run" ||
  fail "qvOS first-run integration seam"
elephant_line=$(grep -nF 'bash "$OMARCHY_PATH/install/first-run/elephant.sh"' \
  "$root/bin/omarchy-first-run" | cut -d: -f1)
qvos_first_run_line=$(grep -nF 'bash "$OMARCHY_PATH/qv/install/first-run/apply"' \
  "$root/bin/omarchy-first-run" | cut -d: -f1)
((qvos_first_run_line > elephant_line)) ||
  fail "qvOS first-run overlay runs before inherited configuration is complete"
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
grep -Fq 'NamePretty = "qvOS Themes"' "$root/qv/launcher/elephant/omarchy_themes.lua" || fail "qvOS theme provider label"
grep -Fq 'NamePretty = "qvOS Unlocks"' "$root/qv/launcher/elephant/omarchy_unlocks.lua" || fail "qvOS unlock provider label"
grep -Fq 'NamePretty = "qvOS Background Selector"' "$root/qv/launcher/elephant/omarchy_background_selector.lua" || fail "qvOS background provider label"
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
grep -Fq 'qvOS ISO recovery stage retained:' "$iso_build" ||
  fail "qvOS ISO publish failure recovery"
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
grep -Fq '/omarchy/qv/install/packaging/base.packages' \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch" ||
  fail "qvOS ISO base package ownership"
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

grep -Fq 'ping -c 1 9.9.9.9' "$root/qv/diagnostics/debug" || fail "Quad9 diagnostic probe"
pass "diagnostics follow the qvOS Quad9 policy"

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
HOME="$test_root" OMARCHY_PATH="$root" "$root/qv/menu/install" --repair
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

for capture_command in \
  "$root/bin/omarchy-capture-screenshot" \
  "$root/bin/omarchy-capture-screenrecording"; do
  grep -Fq '"$OMARCHY_PATH/qv/share/notification"' "$capture_command" ||
    fail "$(basename "$capture_command") qvOS notification seam"
done
grep -Fq '"$OMARCHY_PATH/qv/share/notification"' "$root/bin/omarchy-transcode" ||
  fail "transcode qvOS notification seam"
grep -Fq 'notification_args+=("${share_action[@]}")' \
  "$root/qv/share/notification" ||
  fail "shared notification Share action"
grep -Fq 'omarchy-menu-share file "$path"' "$root/qv/share/notification" ||
  fail "shared notification delegation"
jq -e '
  ."network"."on-click-right"
    == "omarchy-launch-floating-terminal-with-presentation omarchy-qvos-setup-dns"
' "$root/qv/waybar/overrides.jsonc" >/dev/null ||
  fail "Waybar network DNS route"
pass "capture, transcode, and network surfaces reuse their established owners"

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

dofile(root .. "/qv/launcher/elephant/omarchy_themes.lua")
local themes = GetEntries()
assert(#themes > 1)
local yaqyn_theme
for _, theme in ipairs(themes) do
  if theme.Text == "Yaqyn  " then yaqyn_theme = theme end
end
assert(yaqyn_theme)
assert(yaqyn_theme.Preview:match("/%.config/omarchy/themes/yaqyn/preview%.png$"))
assert(yaqyn_theme.Actions.activate == "omarchy-theme-set yaqyn")

dofile(root .. "/qv/launcher/elephant/omarchy_unlocks.lua")
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
