#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
export QVOS_POWER_TESTING=1
export QVOS_POWER_SYSTEM_ROOT="$test_root/system-root"
export QVOS_NETWORK_TESTING=1
export QVOS_NETWORK_SYSTEM_ROOT="$test_root/system-root"
export QVOS_SECURITY_TESTING=1
export QVOS_SECURITY_SYSTEM_ROOT="$test_root/system-root"
export QVOS_PRINTING_TESTING=1
export QVOS_PRINTING_SYSTEM_ROOT="$test_root/system-root"
export QVOS_PRINTING_SYSTEMCTL="$test_root/printing-bin/systemctl"
export QVOS_PRINTING_TEST_STATE="$test_root/printing-state"
export QVOS_PRINTING_TEST_LOG="$test_root/printing-actions.log"
export QVOS_CONTROLS_TESTING=1
export QVOS_CONTROLS_SYSTEM_ROOT="$test_root/system-root"
export QVOS_CONTROLS_DESKTOP_USER
QVOS_CONTROLS_DESKTOP_USER=$(id -un)
export XDG_STATE_HOME="$test_root/.local/state"

install -d \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc" \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/docker" \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/pam.d" \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/security" \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/sudoers.d" \
  "$QVOS_SECURITY_SYSTEM_ROOT/usr/lib/systemd/system" \
  "$QVOS_PRINTING_TEST_STATE/enabled" \
  "$QVOS_PRINTING_TEST_STATE/active" \
  "$test_root/printing-bin" \
  "$QVOS_SECURITY_SYSTEM_ROOT/run"
install -m 0644 /dev/stdin "$QVOS_SECURITY_SYSTEM_ROOT/etc/pam.d/sudo" <<'PAM'
auth include system-auth
account include system-auth
session include system-auth
PAM
install -m 0644 /dev/stdin \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/security/faillock.conf" <<'FAILLOCK'
# Package-provided faillock policy.
# deny = 3
# unlock_time = 600
FAILLOCK
install -m 0644 /dev/stdin "$QVOS_SECURITY_SYSTEM_ROOT/etc/pacman.conf" <<'PACMAN'
[core]
SigLevel = Required DatabaseOptional

[omarchy]
SigLevel = Optional TrustAll
Server = https://pkgs.omarchy.org/stable/$arch
PACMAN
install -m 0644 /dev/stdin "$QVOS_SECURITY_SYSTEM_ROOT/etc/docker/daemon.json" <<'DOCKER'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "dns": ["172.17.0.1"],
  "bip": "172.17.0.1/16"
}
DOCKER
install -m 0644 /dev/stdin "$QVOS_SECURITY_SYSTEM_ROOT/etc/fstab" <<'FSTAB'
UUID=TEST-BOOT /boot vfat defaults,fmask=0022,dmask=0022 0 2
FSTAB
for unit in \
  cups.service \
  cups.socket \
  cups.path \
  cups-browsed.service \
  avahi-daemon.service \
  avahi-daemon.socket \
  systemd-resolved.service; do
  install -m 0644 /dev/null \
    "$QVOS_PRINTING_SYSTEM_ROOT/usr/lib/systemd/system/$unit"
  printf 'disabled\n' >"$QVOS_PRINTING_TEST_STATE/enabled/$unit"
  printf 'inactive\n' >"$QVOS_PRINTING_TEST_STATE/active/$unit"
done
printf 'enabled\n' >"$QVOS_PRINTING_TEST_STATE/enabled/cups.socket"
printf 'enabled\n' >"$QVOS_PRINTING_TEST_STATE/enabled/cups.path"
printf 'active\n' >"$QVOS_PRINTING_TEST_STATE/active/cups.socket"
printf 'active\n' >"$QVOS_PRINTING_TEST_STATE/active/cups.path"
printf 'enabled\n' \
  >"$QVOS_PRINTING_TEST_STATE/enabled/systemd-resolved.service"
printf 'active\n' \
  >"$QVOS_PRINTING_TEST_STATE/active/systemd-resolved.service"
: >"$QVOS_PRINTING_TEST_LOG"
install -m 0755 /dev/stdin "$QVOS_PRINTING_SYSTEMCTL" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

state=${QVOS_PRINTING_TEST_STATE:?}
log=${QVOS_PRINTING_TEST_LOG:?}
action=$1
shift
printf '%s|%s\n' "$action" "$*" >>"$log"
case $action in
is-enabled) cat "$state/enabled/$1" ;;
is-active)
  [[ ${1:-} == "--quiet" ]] && shift
  [[ $(<"$state/active/$1") == "active" ]]
  ;;
enable | disable)
  value=disabled
  [[ $action == "enable" ]] && value=enabled
  for unit in "$@"; do printf '%s\n' "$value" >"$state/enabled/$unit"; done
  ;;
start | stop)
  value=inactive
  [[ $action == "start" ]] && value=active
  for unit in "$@"; do printf '%s\n' "$value" >"$state/active/$unit"; done
  ;;
restart)
  for unit in "$@"; do printf 'active\n' >"$state/active/$unit"; done
  ;;
*) exit 64 ;;
esac
SCRIPT

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

"$root/qvcore/tui/build" --check ||
  fail "base-owned Go toolchain is unavailable"
export GOCACHE=${GOCACHE:-$test_root/go-build-cache}
export GOMODCACHE=${GOMODCACHE:-$HOME/.cache/go-mod}

if HOME="$test_root/invalid-chroot-home" \
  QVOS_PATH="$root" \
  QVOS_CHROOT_INSTALL=invalid \
  bash "$root/install.sh" >"$test_root/invalid-chroot.log" 2>&1; then
  fail "invalid native chroot signal accepted"
fi
grep -Fqx 'Invalid qvOS chroot-install signal.' \
  "$test_root/invalid-chroot.log" || fail "invalid native chroot signal error"
pass "native installer rejects an invalid chroot signal before staging"

partial_root="$test_root/partial-source"
partial_home="$test_root/partial-home"
install -d \
  "$partial_root/qvcore/desktop" \
  "$partial_root/qvcore/hooks" \
  "$partial_root/qvcore/screensaver" \
  "$partial_root/qvcore/thunar" \
  "$partial_root/qvcore/waybar" \
  "$partial_home/.local/lib/qvos/desktop"
touch "$partial_home/.local/lib/qvos/desktop/keep-existing"

if HOME="$partial_home" QVOS_PATH="$partial_root" \
  bash -c 'source "$1"' _ "$root/qvcore/install/desktop" \
  >"$test_root/preflight.log" 2>&1; then
  fail "incomplete source preflight"
fi
grep -Fq 'Missing qvOS desktop feature source:' "$test_root/preflight.log" ||
  fail "incomplete source error"
[[ -e $partial_home/.local/lib/qvos/desktop/keep-existing ]] ||
  fail "incomplete source preserved payload"
pass "incomplete source cannot erase the installed desktop payload"

partial_file_root="$test_root/partial-file-source"
partial_file_home="$test_root/partial-file-home"
install -d "$partial_file_root/qvcore"
for feature in branding desktop direct hooks network power screensaver security shell thunar tmux tui waybar windows; do
  cp -a "$root/qvcore/$feature" "$partial_file_root/qvcore/$feature"
done
install -d "$partial_file_home/.local/lib/qvos/desktop"
touch "$partial_file_home/.local/lib/qvos/desktop/keep-existing"
unlink "$partial_file_root/qvcore/thunar/transcode"

if HOME="$partial_file_home" QVOS_PATH="$partial_file_root" \
  bash -c 'source "$1"' _ "$root/qvcore/install/desktop" \
  >"$test_root/preflight-file.log" 2>&1; then
  fail "incomplete source-file preflight"
fi
grep -Fq 'Missing qvOS desktop feature file:' \
  "$test_root/preflight-file.log" ||
  fail "incomplete source-file error"
[[ -e $partial_file_home/.local/lib/qvos/desktop/keep-existing ]] ||
  fail "incomplete source-file preserved payload"
pass "missing feature files cannot erase the installed desktop payload"

unsafe_screensaver_home="$test_root/unsafe-screensaver-home"
external_screensaver="$test_root/external-screensaver"
install -d \
  "$unsafe_screensaver_home/.local/lib/qvos" \
  "$external_screensaver"
touch "$external_screensaver/preserve"
ln -s \
  "$external_screensaver" \
  "$unsafe_screensaver_home/.local/lib/qvos/screensaver"
if HOME="$unsafe_screensaver_home" QVOS_PATH="$root" \
  "$root/qvcore/screensaver/install" >/dev/null 2>&1; then
  fail "symbolic-link screensaver runtime"
fi
[[ -e $external_screensaver/preserve &&
  ! -e $external_screensaver/alacritty.toml &&
  ! -e $external_screensaver/foot.ini &&
  ! -e $external_screensaver/ghostty.conf ]] ||
  fail "symbolic-link screensaver runtime preservation"
pass "screensaver installation refuses external runtime targets"

swap_failure_home="$test_root/swap-failure-home"
swap_failure_bin="$test_root/swap-failure-bin"
install -d \
  "$swap_failure_home/.local/lib/qvos/screensaver" \
  "$swap_failure_bin"
printf 'preserve old runtime\n' \
  >"$swap_failure_home/.local/lib/qvos/screensaver/preserve"
install -m 0755 /dev/stdin "$swap_failure_bin/mv" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

source_path=${2:-}
target_path=${3:-}
if [[ $source_path == */.screensaver.* && $target_path == */screensaver ]]; then
  exit 1
fi
exec /usr/bin/mv "$@"
SCRIPT
if HOME="$swap_failure_home" QVOS_PATH="$root" \
  PATH="$swap_failure_bin:/usr/bin" \
  "$root/qvcore/screensaver/install" >/dev/null 2>&1; then
  fail "screensaver runtime swap failure fixture"
fi
[[ $(<"$swap_failure_home/.local/lib/qvos/screensaver/preserve") == \
  "preserve old runtime" ]] || fail "screensaver runtime rollback"
[[ -z $(find "$swap_failure_home/.local/lib/qvos" -maxdepth 1 \
  -name '.screensaver*' -print -quit) ]] ||
  fail "screensaver runtime rollback residue"
pass "failed screensaver replacement restores the complete prior runtime"

downstream_failure_home="$test_root/downstream-failure-home"
power_blocker="$test_root/power-blocker"
install -d "$downstream_failure_home/.local/lib/qvos/screensaver"
printf 'stale config\n' \
  >"$downstream_failure_home/.local/lib/qvos/screensaver/alacritty.toml"
install -m 0644 /dev/null "$power_blocker"

if HOME="$downstream_failure_home" \
  QVOS_PATH="$root" \
  QVOS_POWER_SYSTEM_ROOT="$power_blocker" \
  bash -c 'source "$1"' _ "$root/qvcore/install/desktop" \
  >"$test_root/downstream-failure.log" 2>&1; then
  fail "downstream power failure fixture"
fi
for config_name in alacritty.toml foot.ini ghostty.conf; do
  cmp -s \
    "$root/qvcore/screensaver/$config_name" \
    "$downstream_failure_home/.local/lib/qvos/screensaver/$config_name" || {
    sed -n '1,160p' "$test_root/downstream-failure.log" >&2
    fail "downstream failure removed the screensaver config: $config_name"
  }
done
for command_name in \
  qvos-launch-screensaver \
  qvos-screensaver; do
  cmp -s \
    "$root/qvcore/screensaver/$command_name" \
    "$downstream_failure_home/.local/lib/qvos/bin/$command_name" ||
    fail "downstream failure left an incomplete $command_name"
done
for alias_entry in \
  qv-launch-screensaver:qvos-launch-screensaver \
  qv-screensaver:qvos-screensaver; do
  alias_name=${alias_entry%%:*}
  owner_name=${alias_entry#*:}
  [[ $(readlink "$downstream_failure_home/.local/bin/$alias_name") == \
    "$downstream_failure_home/.local/lib/qvos/bin/$owner_name" ]] ||
    fail "downstream failure left an incomplete $alias_name"
done
for retired_alias in omarchy-launch-screensaver omarchy-screensaver; do
  [[ ! -e $downstream_failure_home/.local/bin/$retired_alias &&
    ! -L $downstream_failure_home/.local/bin/$retired_alias ]] ||
    fail "downstream failure restored retired $retired_alias"
done
pass "later privileged failures cannot break the screensaver runtime"

install -d \
  "$test_root/.config/qvos/hooks" \
  "$test_root/.config/systemd/user" \
  "$test_root/.local/share/dbus-1/services" \
  "$test_root/.local/share/applications" \
  "$test_root/.local/bin" \
  "$test_root/.local/lib/qvos/bin" \
  "$test_root/.local/lib/qvos/desktop/context" \
  "$test_root/.local/lib/qvos/screensaver" \
  "$test_root/.local/lib/qvos/thunar" \
  "$test_root/.local/lib/qvos/tmux" \
  "$test_root/.local/lib/qvos/waybar"
touch \
  "$test_root/.local/lib/qvos/desktop/context/removed-helper" \
  "$test_root/.local/lib/qvos/screensaver/removed-launcher" \
  "$test_root/.local/lib/qvos/thunar/removed-feature" \
  "$test_root/.local/lib/qvos/tmux/removed-feature" \
  "$test_root/.local/lib/qvos/waybar/removed-feature"
install -m 0755 /dev/null "$test_root/.local/lib/qvos/waybar/prayer-data.sh"
install -m 0644 /dev/stdin "$test_root/.bashrc" <<'BASHRC'
source "$HOME/.local/lib/qvos/shell/aliases"
source "$HOME/.local/lib/qvos/shell/aliases"
export PERSONAL_SHELL_VALUE=preserve
BASHRC
HOME="$test_root" QVOS_PATH="$root" OMARCHY_PATH="$test_root/stale-source" \
  bash -c 'source "$1"' _ "$root/qvcore/install/desktop"

for menu_owner in base menu routes; do
  [[ -f $root/qvcore/menu/$menu_owner ]] ||
    fail "native qvOS menu owner: $menu_owner"
done
cmp -s "$root/qvcore/config/files/qvos/extensions/menu.sh" \
  "$test_root/.config/qvos/extensions/menu.sh" ||
  fail "fresh native personal menu extension"
[[ ! -e $test_root/.config/omarchy/extensions/menu.sh &&
  ! -L $test_root/.config/omarchy/extensions/menu.sh &&
  ! -e $test_root/.config/omarchy/extensions/qvos-menu.sh &&
  ! -L $test_root/.config/omarchy/extensions/qvos-menu.sh ]] ||
  fail "fresh install generated an inherited menu extension"
pass "fresh qvOS uses only its native personal menu extension"

for provider in \
  qvos_background_selector.lua \
  qvos_menu.lua \
  qvos_themes.lua \
  qvos_unlocks.lua; do
  runtime_provider="$test_root/.local/lib/qvos/menu/elephant/$provider"
  cmp -s "$root/qvcore/menu/elephant/$provider" "$runtime_provider" ||
    fail "$provider native runtime"
  [[ $(readlink "$test_root/.config/elephant/menus/$provider") == "$runtime_provider" ]] ||
    fail "$provider native runtime link"
done
[[ $(find "$test_root/.local/lib/qvos/menu/elephant" -maxdepth 1 -type f -printf '%f\n' | sort) == $'qvos_background_selector.lua\nqvos_menu.lua\nqvos_themes.lua\nqvos_unlocks.lua' ]] ||
  fail "qvOS menu provider runtime inventory"
if find "$test_root/.config/elephant/menus" -maxdepth 1 \
  -name 'omarchy_*.lua' -print -quit | grep -q .; then
  fail "retired Elephant provider link"
fi
pass "menu uses only native qvOS providers"

HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/hooks/reconcile" --check >/dev/null ||
  fail "native custom hook reconciliation"
if find "$test_root/.config/qvos/hooks" -type f \
  \( -name qvos-base -o -name qvos-direct-tools -o -name qvos-waybar-overrides \) \
  -print -quit | grep -q .; then
  fail "qvOS system jobs leaked into the custom hook tree"
fi
pass "custom hooks contain samples without duplicate qvOS system jobs"

[[ ! -e $test_root/.local/lib/qvos/desktop/context/removed-helper ]] || fail "stale desktop helper cleanup"
[[ ! -e $test_root/.local/lib/qvos/screensaver/removed-launcher ]] || fail "stale screensaver cleanup"
[[ ! -e $test_root/.local/lib/qvos/thunar/removed-feature ]] ||
  fail "stale Thunar feature cleanup"
[[ ! -e $test_root/.local/lib/qvos/tmux/removed-feature ]] || fail "stale tmux feature cleanup"
[[ ! -e $test_root/.local/lib/qvos/waybar/removed-feature ]] || fail "stale Waybar feature cleanup"
pass "stale helper payloads are removed"

[[ -L $test_root/.local/bin/thunar &&
  $(readlink -- "$test_root/.local/bin/thunar") == \
    "$test_root/.local/lib/qvos/thunar/launch" ]] ||
  fail "native qvOS Thunar command route"
grep -Fqx 'ExecStart=%h/.local/lib/qvos/thunar/launch --daemon' \
  "$test_root/.config/systemd/user/thunar.service.d/qvos.conf" ||
  fail "native qvOS Thunar service route"
pass "retired Thunar launch state converges on its native runtime owner"

[[ ! -e $root/qvcore/scripts ]] || fail "orphaned generic script namespace"
pass "every private helper has a feature owner"

for feature in direct tmux; do
  expected_feature="$(
    sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' \
      "$root/qvcore/$feature/runtime-paths"
  )"
  installed_feature="$(find "$test_root/.local/lib/qvos/$feature" -type f -printf '%P\n' | sort)"
  [[ $installed_feature == "$expected_feature" ]] || fail "$feature feature inventory"
done
[[ ! -e $test_root/.local/lib/qvos/direct/runtime-paths ]] ||
  fail "source-only direct-tool manifest leaked into runtime"
expected_waybar=$(
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' \
    "$root/qvcore/waybar/runtime-paths"
)
installed_waybar=$(
  find "$test_root/.local/lib/qvos/waybar" -type f -printf '%P\n' | sort
)
[[ $installed_waybar == "$expected_waybar" ]] || fail "Waybar runtime inventory"
expected_desktop=$(
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$root/qvcore/desktop/runtime-paths"
)
installed_desktop=$(
  find "$test_root/.local/lib/qvos/desktop" -type f -printf '%P\n' | sort
)
[[ $installed_desktop == "$expected_desktop" ]] || fail "desktop feature inventory"
[[ ! -e $test_root/.local/lib/qvos/windows ]] || fail "unused Windows runtime inventory"
installed_thunar_inventory="$(
  find "$test_root/.local/lib/qvos/thunar" -type f -printf '%P\n' | sort
)"
[[ $installed_thunar_inventory == $'actions.sh\ninstall\nlaunch\nopen-here\nreconcile-default-actions\nset-background\nshare\ntranscode' ]] ||
  fail "default Thunar feature inventory"
for optional_thunar_feature in codex proton-drive-upload; do
  [[ ! -e $test_root/.local/lib/qvos/thunar/$optional_thunar_feature ]] ||
    fail "optional Thunar $optional_thunar_feature base payload"
done
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-localsend-share'])" \
  "$test_root/.config/Thunar/uca.xml") == "1" ]] ||
  fail "base LocalSend Thunar action"
pass "installed feature payloads match tracked source"

for optional_thunar_feature in codex proton-drive-upload; do
  printf 'stale optional integration\n' \
    >"$test_root/.local/lib/qvos/thunar/$optional_thunar_feature"
done
install -m 0755 /dev/null "$test_root/.local/lib/qvos/tui/.qvos-tui.STALE1"
touch -d '2 hours ago' "$test_root/.local/lib/qvos/tui/.qvos-tui.STALE1"
install -m 0755 /dev/null "$test_root/.local/lib/qvos/tui/.qvos-tui.ACTIVE"
install -d "$test_root/.local/share/nautilus-python/extensions/__pycache__"
printf 'personal LocalSend extension\n' \
  >"$test_root/.local/share/nautilus-python/extensions/localsend.py"
printf 'personal bytecode\n' \
  >"$test_root/.local/share/nautilus-python/extensions/__pycache__/localsend.cpython-314.pyc"
install -m 0644 /dev/stdin \
  "$test_root/.local/share/applications/thunar.desktop" <<EOF
[Desktop Entry]
Exec=$test_root/.local/share/qvos/defaults/qvos-launch-thunar %U
[Desktop Action Custom]
Exec=/usr/bin/custom-file-manager
EOF
install -m 0644 /dev/stdin \
  "$test_root/.config/systemd/user/thunar.service" <<EOF
[Unit]
Description=Thunar file manager
[Service]
Type=dbus
ExecStart=$test_root/.local/share/qvos/defaults/qvos-launch-thunar --daemon
Environment=USER_CUSTOM=1
BusName=org.xfce.FileManager
KillMode=process
EOF
power_helper_state_before=$(find "$QVOS_POWER_SYSTEM_ROOT/usr/lib/qvos" \
  -type f -printf '%P|%u:%g:%m|%i|%T@\n' | sort)
install -d -m 0700 \
  "$test_root/.local/state/qvos/services" \
  "$test_root/.local/state/qvos/development"
install -m 0600 /dev/null \
  "$test_root/.local/state/qvos/services/proton"
install -m 0600 /dev/null \
  "$test_root/.local/state/qvos/development/devel"
HOME="$test_root" QVOS_PATH="$root" OMARCHY_PATH="$test_root/stale-source" \
  bash -c 'source "$1"' _ "$root/qvcore/install/desktop"
[[ $(find "$QVOS_POWER_SYSTEM_ROOT/usr/lib/qvos" \
  -type f -printf '%P|%u:%g:%m|%i|%T@\n' | sort) == \
  "$power_helper_state_before" ]] ||
  fail "desktop refresh rewrote an exact privileged power helper"
grep -Fq 'Exec=/usr/bin/custom-file-manager' \
  "$test_root/.local/share/applications/thunar.desktop" ||
  fail "custom Thunar desktop override preservation"
grep -Fq 'Environment=USER_CUSTOM=1' \
  "$test_root/.config/systemd/user/thunar.service" ||
  fail "custom Thunar service preservation"
[[ ! -e $test_root/.local/lib/qvos/tui/.qvos-tui.STALE1 ]] ||
  fail "stale TUI build cleanup"
[[ ! -e $test_root/.local/lib/qvos/tui/.qvos-tui.ACTIVE ]] ||
  fail "untracked TUI build residue"
grep -Fqx 'personal LocalSend extension' \
  "$test_root/.local/share/nautilus-python/extensions/localsend.py" ||
  fail "modified Nautilus extension preservation"
grep -Fqx 'personal bytecode' \
  "$test_root/.local/share/nautilus-python/extensions/__pycache__/localsend.cpython-314.pyc" ||
  fail "modified Nautilus bytecode preservation"
for optional_thunar_feature in codex proton-drive-upload; do
  cmp -s \
    "$root/qvcore/thunar/$optional_thunar_feature" \
    "$test_root/.local/lib/qvos/thunar/$optional_thunar_feature" ||
    fail "enabled Thunar $optional_thunar_feature preservation"
done
cmp -s \
  "$root/services/proton/skill/SKILL.md" \
  "$test_root/.codex/skills/proton-cli/SKILL.md" ||
  fail "enabled Proton Codex integration reconciliation"
pass "desktop refresh reconciles enrolled integrations without reinstalling stacks"
pass "modified Nautilus extensions and bytecode remain untouched"

waybar_source_inventory="$(find "$root/qvcore/waybar" -maxdepth 1 -type f -printf '%f\n' | sort)"
[[ $waybar_source_inventory == $'AGENTS.md\ncheck\nclock.sh\nidle-status\ninstall\nnative-paths\nnotification-status\npost-update-hook\nprayer-data.sh\nprayerbar.sh\nrefresh\nretired-paths\nruntime-paths\nsession\ntoggle\nworkspace-state' ]] ||
  fail "focused Waybar feature inventory"
pass "retired Waybar helpers stay removed"

screensaver_files="$(find "$test_root/.local/lib/qvos/screensaver" -maxdepth 1 -type f -printf '%f\n' | sort)"
[[ $screensaver_files == $'alacritty.toml\nfoot.ini\nghostty.conf' ]] ||
  fail "screensaver config inventory"
for config_name in alacritty.toml foot.ini ghostty.conf; do
  [[ $(stat -c '%a' "$test_root/.local/lib/qvos/screensaver/$config_name") == \
    "644" ]] || fail "screensaver config mode: $config_name"
done
pass "screensaver configuration is complete and non-executable"

for command_name in qvos-launch-screensaver qvos-screensaver; do
  installed_command="$test_root/.local/lib/qvos/bin/$command_name"
  [[ -x $installed_command ]] || fail "$command_name installation"
  [[ "$(readlink "$test_root/.local/bin/$command_name")" == "$installed_command" ]] || fail "$command_name link"
done
for alias_entry in \
  qv-launch-screensaver:qvos-launch-screensaver \
  qv-screensaver:qvos-screensaver; do
  alias_name=${alias_entry%%:*}
  owner_name=${alias_entry#*:}
  [[ $(readlink "$test_root/.local/bin/$alias_name") == \
    "$test_root/.local/lib/qvos/bin/$owner_name" ]] ||
    fail "$alias_name runtime owner"
done
for retired_alias in omarchy-launch-screensaver omarchy-screensaver; do
  [[ ! -e $test_root/.local/bin/$retired_alias &&
    ! -L $test_root/.local/bin/$retired_alias ]] ||
    fail "$retired_alias runtime alias creation"
done
[[ ! -e $test_root/.local/lib/qvos/bin/omarchy-launch-screensaver &&
  ! -L $test_root/.local/lib/qvos/bin/omarchy-launch-screensaver ]] ||
  fail "retired copied screensaver adapter creation"
pass "screensaver commands and user links are installed"

for command_name in \
  qv-system-inhibit-sleep \
  qv-system-suspend-if-safe; do
  command_path="$test_root/.local/lib/qvos/bin/$command_name"
  [[ -L $command_path && -x $command_path ]] ||
    fail "$command_name runtime link installation"
  owner=${command_name#omarchy-system-}
  owner=${owner#qv-system-}
  [[ $(readlink -- "$command_path") == "../power/$owner" ]] ||
    fail "$command_name runtime owner"
done
for retired_command in \
  omarchy-system-inhibit-sleep \
  omarchy-system-suspend-if-safe; do
  [[ ! -e $test_root/.local/lib/qvos/bin/$retired_command &&
    ! -L $test_root/.local/lib/qvos/bin/$retired_command ]] ||
    fail "retired power runtime link cleanup: $retired_command"
done
pass "native power guards have one installed runtime owner"

for runtime_file in \
  battery-protection \
  battery-protection-backend \
  battery-protection-lib \
  inhibit-sleep \
  suspend-if-safe; do
  if ! cmp -s \
    "$root/qvcore/power/$runtime_file" \
    "$test_root/.local/lib/qvos/power/$runtime_file"; then
    diff -u \
      "$root/qvcore/power/$runtime_file" \
      "$test_root/.local/lib/qvos/power/$runtime_file" >&2 || true
    fail "Battery Protection $runtime_file runtime"
  fi
done
cmp -s \
  "$root/qvcore/power/qvos-battery-full-charge-once.service" \
  "$test_root/.config/systemd/user/qvos-battery-full-charge-once.service" ||
  fail "dormant Battery Protection user unit"
cmp -s \
  "$root/qvcore/power/battery-protection-hwdb" \
  "$QVOS_POWER_SYSTEM_ROOT/usr/lib/qvos/battery-protection-hwdb" ||
  fail "root-owned Battery Protection helper payload"
for helper in profiles-command profiles-set supply-lib wifi-powersave; do
  mode=755
  [[ $helper != "profiles-command" && $helper != "supply-lib" ]] || mode=644
  target="$QVOS_POWER_SYSTEM_ROOT/usr/lib/qvos/power/$helper"
  cmp -s "$root/qvcore/power/$helper" "$target" ||
    fail "root-owned AC-event helper payload: $helper"
  [[ $(stat -c '%a' -- "$target") == "$mode" ]] ||
    fail "root-owned AC-event helper mode: $helper"
done
for payload in hibernation:root keyboard-backlight:keyboard-backlight; do
  target_name=${payload%%:*}
  source_name=${payload#*:}
  target="$QVOS_POWER_SYSTEM_ROOT/usr/lib/qvos/power/$target_name"
  cmp -s "$root/qvcore/power/hibernation/$source_name" "$target" ||
    fail "root-owned hibernation helper payload: $target_name"
  [[ $(stat -c '%a' -- "$target") == "755" ]] ||
    fail "root-owned hibernation helper mode: $target_name"
done
[[ ! -e $QVOS_POWER_SYSTEM_ROOT/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb ]] ||
  fail "desktop install must not enable Battery Protection"
[[ ! -e $test_root/.local/state/qvos/battery-protection ]] ||
  fail "desktop install must not create Battery Protection intent"
pass "Battery Protection installs dormant without touching charging state"

cmp -s \
  "$root/qvcore/controls/brightness/apple-display-helper" \
  "$QVOS_CONTROLS_SYSTEM_ROOT/usr/lib/qvos/controls/apple-display-brightness" ||
  fail "root-owned Apple display helper payload"
grep -Fqx \
  "$QVOS_CONTROLS_DESKTOP_USER ALL=(root) NOPASSWD: /usr/lib/qvos/controls/apple-display-brightness" \
  "$QVOS_CONTROLS_SYSTEM_ROOT/etc/sudoers.d/asdcontrol" ||
  fail "bounded Apple display privilege policy"
pass "Apple display brightness exposes only its bounded root helper"

cmp -s \
  "$root/qvcore/security/60-qvos-security.conf" \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/sysctl.d/60-qvos-security.conf" ||
  fail "qvOS security baseline payload"
grep -Fqx 'SigLevel = Required DatabaseOptional' \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/pacman.conf" ||
  fail "Omarchy repository package signature policy"
cmp -s \
  "$root/qvcore/security/dev-share-firewall" \
  "$QVOS_SECURITY_SYSTEM_ROOT/usr/lib/qvos/dev-share-firewall" ||
  fail "LAN preview root helper payload"
cmp -s \
  "$root/qvcore/security/retire-passwordless-sudo" \
  "$QVOS_SECURITY_SYSTEM_ROOT/usr/lib/qvos/retire-passwordless-sudo" ||
  fail "passwordless-sudo retirement root helper payload"
cmp -s \
  "$root/qvcore/security/auth-policy" \
  "$QVOS_SECURITY_SYSTEM_ROOT/usr/lib/qvos/security/auth-policy" ||
  fail "authentication policy root helper payload"
cmp -s \
  "$root/qvcore/security/login-policy" \
  "$QVOS_SECURITY_SYSTEM_ROOT/usr/lib/qvos/security/login-policy" ||
  fail "login policy root helper payload"
grep -Fqx 'deny = 10' \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/security/faillock.conf" ||
  fail "login faillock threshold"
grep -Fqx 'unlock_time = 120' \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/security/faillock.conf" ||
  fail "login recovery threshold"
grep -Fqx 'Defaults passwd_tries=10' \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/sudoers.d/50-qvos-password-attempts" ||
  fail "sudo password-attempt policy"
cmp -s \
  "$root/qvcore/install/system/printing-resolver.conf" \
  "$QVOS_PRINTING_SYSTEM_ROOT/etc/systemd/resolved.conf.d/50-qvos-local-discovery.conf" ||
  fail "printing resolver policy payload"
cmp -s \
  "$root/qvcore/network/dns-policy" \
  "$QVOS_NETWORK_SYSTEM_ROOT/usr/lib/qvos/network/dns-policy" ||
  fail "DNS policy root helper payload"
jq -e '
  .ip == "127.0.0.1" and
  .["default-network-opts"].bridge[
    "com.docker.network.bridge.host_binding_ipv4"
  ] == "127.0.0.1"
' "$QVOS_SECURITY_SYSTEM_ROOT/etc/docker/daemon.json" >/dev/null ||
  fail "Docker loopback publishing policy"
cmp -s \
  "$root/qvcore/security/docker-resolved.conf" \
  "$QVOS_SECURITY_SYSTEM_ROOT/etc/systemd/resolved.conf.d/50-qvos-docker.conf" ||
  fail "Docker resolver policy payload"
pass "security baseline protects package trust without restricting desktop capabilities"

tui_binary="$test_root/.local/lib/qvos/tui/qvos-tui"
[[ -x $tui_binary && ! -L $tui_binary ]] ||
  fail "qvOS TUI managed binary"
[[ $(readlink "$test_root/.local/bin/qvos-tui") == "$tui_binary" ]] ||
  fail "qvOS TUI command link"
for runtime_file in \
  launch \
  success-guidance.psv \
  action/choices.psv \
  action/forms.psv \
  action/post-actions.psv \
  action/post-run \
  action/font-launch \
  action/font-run \
  action/launch \
  action/rollbacks.psv \
  action/rollback-owner \
  action/run \
  action/run-installer \
  bin/qvos-build \
  task/actions.psv \
  task/launch \
  task/run \
  task/selectable-owner \
  task/selections.psv \
  update/launch \
  update/run; do
  cmp -s \
    "$root/qvcore/tui/$runtime_file" \
    "$test_root/.local/lib/qvos/tui/$runtime_file" ||
    fail "qvOS TUI $runtime_file runtime"
done
while IFS= read -r presenter; do
  relative_presenter=${presenter#"$root/qvcore/tui/"}
  cmp -s \
    "$presenter" \
    "$test_root/.local/lib/qvos/tui/$relative_presenter" ||
    fail "qvOS TUI $relative_presenter runtime"
done < <(find "$root/qvcore/tui/task/presenters" -type f | sort)
HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/tui/install" --status ||
  fail "qvOS TUI source parity"

no_go_tui_source="$test_root/no-go-tui-source"
install -d "$no_go_tui_source/qvcore"
cp -a "$root/qvcore/tui" "$no_go_tui_source/qvcore/tui"
sed -i \
  's#^go_binary=/usr/lib/go/bin/go$#go_binary=/qvos-test-missing-go#' \
  "$no_go_tui_source/qvcore/tui/build"
rm -- "$test_root/.local/bin/qvos-tui"
tui_runtime_before=$(
  find "$test_root/.local/lib/qvos/tui" -type f -printf '%P\0' |
    sort -z |
    xargs -0 -I '{}' sha256sum \
      "$test_root/.local/lib/qvos/tui/{}"
)
tui_publish_bin="$test_root/tui-publish-bin"
install -d "$tui_publish_bin"
install -m 0755 /dev/stdin "$tui_publish_bin/ln" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
if HOME="$test_root" QVOS_PATH="$no_go_tui_source" \
  PATH="$tui_publish_bin:/usr/bin" \
  "$no_go_tui_source/qvcore/tui/install" --build-if-available \
  >/dev/null 2>&1; then
  fail "TUI publication ignored a failed command link"
fi
tui_runtime_after=$(
  find "$test_root/.local/lib/qvos/tui" -type f -printf '%P\0' |
    sort -z |
    xargs -0 -I '{}' sha256sum \
      "$test_root/.local/lib/qvos/tui/{}"
)
[[ $tui_runtime_after == "$tui_runtime_before" ]] ||
  fail "failed TUI command link did not restore the prior runtime"
[[ ! -e $test_root/.local/bin/qvos-tui &&
  ! -L $test_root/.local/bin/qvos-tui ]] ||
  fail "failed TUI command link left a partial link"
rm -- "$tui_publish_bin/ln"
HOME="$test_root" QVOS_PATH="$no_go_tui_source" \
  "$no_go_tui_source/qvcore/tui/install" --build-if-available
HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/tui/install" --status ||
  fail "valid managed TUI could not recover its command link without Go"
pass "TUI publication atomically rolls back and reuses a valid binary"

mkfifo "$test_root/.local/lib/qvos/tui/.untracked-fifo"
if HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/tui/install" --status; then
  fail "TUI status accepted an untracked special file"
fi
HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/tui/install" --build-if-available
[[ ! -e $test_root/.local/lib/qvos/tui/.untracked-fifo ]] ||
  fail "TUI reconciliation retained an untracked special file"
pass "TUI runtime inventory rejects and removes untracked objects"

stale_tui_source="$test_root/stale-tui-source"
install -d "$stale_tui_source/qvcore"
cp -a "$root/qvcore/tui" "$stale_tui_source/qvcore/tui"
printf '\n// qvOS stale-source transaction fixture.\n' \
  >>"$stale_tui_source/qvcore/tui/main.go"
sed -i \
  's#^go_binary=/usr/lib/go/bin/go$#go_binary=/qvos-test-missing-go#' \
  "$stale_tui_source/qvcore/tui/build"
tui_runtime_before=$(
  find "$test_root/.local/lib/qvos/tui" -type f -printf '%P\0' |
    sort -z |
    xargs -0 -I '{}' sha256sum \
      "$test_root/.local/lib/qvos/tui/{}"
)
if HOME="$test_root" QVOS_PATH="$stale_tui_source" \
  "$stale_tui_source/qvcore/tui/install" --build-if-available \
  >/dev/null 2>&1; then
  fail "stale TUI source succeeded without its base build dependency"
fi
tui_runtime_after=$(
  find "$test_root/.local/lib/qvos/tui" -type f -printf '%P\0' |
    sort -z |
    xargs -0 -I '{}' sha256sum \
      "$test_root/.local/lib/qvos/tui/{}"
)
[[ $tui_runtime_after == "$tui_runtime_before" ]] ||
  fail "failed TUI build changed the published runtime"
HOME="$test_root" QVOS_PATH="$root" \
  "$root/qvcore/tui/install" --status ||
  fail "failed TUI build did not preserve source parity"
pass "TUI publication is atomic across a missing build dependency"

cancel_test_bin="$test_root/tui-cancel-bin"
install -d "$cancel_test_bin"
install -m 0755 /dev/stdin "$cancel_test_bin/pacman" <<'SCRIPT'
#!/bin/bash
[[ $* == "-Qq" ]] || exit 2
SCRIPT
cancel_status=$(
  HOME="$test_root" \
    QVOS_PATH="$root" \
    PATH="$cancel_test_bin:/usr/bin" \
    QVOS_ACTION_SLUG=emacs \
    QVOS_ACTION_OPERATION=install \
    "$test_root/.local/lib/qvos/tui/action/run-installer" \
    --cancel-status
)
[[ $cancel_status == "target-not-detected" ]] ||
  fail "installed TUI cancellation result probe"
pass "qvOS TUI binary and cancellation adapters install as one runtime"

cmp -s \
  "$root/qvcore/shell/aliases" \
  "$test_root/.local/lib/qvos/shell/aliases" ||
  fail "runtime shell overlay"
# shellcheck disable=SC2016
grep -Fqx \
  'source "$HOME/.local/lib/qvos/shell/aliases"' \
  "$test_root/.bashrc" ||
  fail "runtime shell source line"
# shellcheck disable=SC2016
[[ $(grep -Fxc 'source "$HOME/.local/lib/qvos/shell/aliases"' \
  "$test_root/.bashrc") == "1" ]] ||
  fail "duplicate runtime shell source line"
grep -Fqx 'export PERSONAL_SHELL_VALUE=preserve' "$test_root/.bashrc" ||
  fail "personal Bash content preservation"
grep -Fqx 'alias hx=helix' "$test_root/.local/lib/qvos/shell/aliases" ||
  fail "runtime Helix alias"
shell_backup_root="$test_root/.local/state/qvos/shell-backups"
[[ -d $shell_backup_root && ! -L $shell_backup_root &&
  $(stat -c '%a' "$shell_backup_root") == "700" ]] ||
  fail "private Bash configuration backup directory"
[[ $(find "$shell_backup_root" -maxdepth 1 -type f -name 'bashrc.*' | wc -l) == "1" ]] ||
  fail "private Bash configuration backup"
if compgen -G "$test_root/.bashrc.bak.*" >/dev/null; then
  fail "Bash configuration backup leaked beside active configuration"
fi
pass "Bash loads the source-independent qvOS shell overlay"

[[ "$(stat -c '%a' "$test_root/.local/lib/qvos/waybar/prayer-data.sh")" == "644" ]] || fail "data script mode"
[[ -x $test_root/.local/lib/qvos/waybar/prayerbar.sh ]] || fail "Waybar command mode"
[[ -x $test_root/.local/lib/qvos/waybar/session &&
  -x $test_root/.local/lib/qvos/waybar/workspace-state ]] ||
  fail "Waybar session and workspace-state command modes"
for source_only_path in \
  AGENTS.md \
  check \
  idle-status \
  install \
  native-paths \
  notification-status \
  post-update-hook \
  refresh \
  retired-paths \
  runtime-paths; do
  [[ ! -e $test_root/.local/lib/qvos/waybar/$source_only_path ]] ||
    fail "source-only Waybar payload leaked into runtime: $source_only_path"
done
[[ -x $test_root/.local/lib/qvos/tmux/qvos-tmux ]] || fail "tmux command mode"
[[ $(find "$test_root/.local/lib/qvos/tmux" -type f -printf '%P\n' | sort) == \
  "qvos-tmux" ]] || fail "Tmux runtime inventory"
for source_only_path in AGENTS.md native-paths refresh runtime-paths; do
  [[ ! -e $test_root/.local/lib/qvos/tmux/$source_only_path ]] ||
    fail "source-only Tmux payload leaked into runtime: $source_only_path"
done
while IFS= read -r helper; do
  [[ -x $helper ]] || fail "desktop helper mode"
done < <(find "$test_root/.local/lib/qvos/desktop" -type f)
while IFS= read -r runtime_path; do
  [[ $runtime_path == \#* || -z $runtime_path ]] && continue
  [[ -x $test_root/.local/lib/qvos/desktop/$runtime_path ]] ||
    fail "desktop runtime inventory"
done <"$root/qvcore/desktop/runtime-paths"
for source_only_path in AGENTS.md check native-paths runtime-paths restart; do
  [[ ! -e $test_root/.local/lib/qvos/desktop/$source_only_path ]] ||
    fail "source-only desktop payload leaked into runtime"
done
[[ ! -e $test_root/.local/lib/qvos/windows ]] ||
  fail "unused Windows source tree leaked into runtime"
pass "runtime payload excludes policy, checks, inventories, and source-only owners"
[[ ! -x $test_root/.local/lib/qvos/thunar/actions.sh ]] ||
  fail "Thunar action library mode"
for feature in \
  launch \
  open-here \
  reconcile-default-actions \
  set-background \
  share \
  transcode; do
  [[ -x $test_root/.local/lib/qvos/thunar/$feature ]] ||
    fail "Thunar $feature mode"
done
pass "tracked script and data modes are preserved"
