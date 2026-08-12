#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
fixture="$test_root/source"
test_home="$test_root/home"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$fixture/qvcore/config/files/wireplumber/wireplumber.conf.d" \
  "$fixture/qvcore/config" \
  "$test_bin" \
  "$test_home"
install -m 0755 "$root/qvcore/config/wireplumber-policy" \
  "$fixture/qvcore/config/wireplumber-policy"
install -m 0644 \
  "$root/qvcore/config/files/xcompose" \
  "$fixture/qvcore/config/files/xcompose"
install -m 0644 \
  "$root/qvcore/config/files/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf" \
  "$fixture/qvcore/config/files/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf"
install -m 0644 \
  "$root/qvcore/config/files/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf" \
  "$fixture/qvcore/config/files/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf"

install -m 0755 /dev/stdin "$test_bin/qv-hw-asus-rog" <<'STUB'
#!/bin/bash
exit 0
STUB
install -m 0755 /dev/stdin "$test_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exit 0
STUB
: >"$action_log"

run_leaf() {
  HOME="$test_home" \
    QVOS_PATH="$fixture" \
    QVOS_USER_NAME='Abdulrahman "Q" Yaqyn' \
    QVOS_USER_EMAIL='Yaqyn\\test@pm.me' \
    QVOS_TEST_ACTION_LOG="$action_log" \
    PATH="$test_bin:/usr/bin" \
    bash -c 'set -euo pipefail; source "$1"' _ "$1"
}

git_leaf="$root/qvcore/install/config/git.sh"
HOME="$test_home" \
  XDG_CONFIG_HOME="$test_home/.config" \
  QVOS_USER_NAME='Abdulrahman M. Yaqyn' \
  QVOS_USER_EMAIL='Yaqyn@pm.me' \
  OMARCHY_USER_NAME='Retired Name' \
  OMARCHY_USER_EMAIL='retired@example.invalid' \
  bash -c 'set -euo pipefail; source "$1"' _ "$git_leaf"
[[ $(HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
  git config --global user.name) == "Abdulrahman M. Yaqyn" ]] ||
  fail "native Git user name input"
[[ $(HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
  git config --global user.email) == "Yaqyn@pm.me" ]] ||
  fail "native Git user email input"

legacy_git_home="$test_root/legacy-git-home"
install -d "$legacy_git_home"
HOME="$legacy_git_home" \
  XDG_CONFIG_HOME="$legacy_git_home/.config" \
  OMARCHY_USER_NAME='Retired Name' \
  OMARCHY_USER_EMAIL='retired@example.invalid' \
  bash -c 'set -euo pipefail; source "$1"' _ "$git_leaf"
if HOME="$legacy_git_home" XDG_CONFIG_HOME="$legacy_git_home/.config" \
  git config --global user.name >/dev/null 2>&1 ||
  HOME="$legacy_git_home" XDG_CONFIG_HOME="$legacy_git_home/.config" \
  git config --global user.email >/dev/null 2>&1; then
  fail "inherited Git identity input remains active"
fi

xcompose_leaf="$root/qvcore/install/config/xcompose.sh"
run_leaf "$xcompose_leaf"
xcompose="$test_home/.XCompose"
grep -Fqx 'include "%H/.local/share/qvos/qvcore/config/files/xcompose"' \
  "$xcompose" || fail "native XCompose include"
grep -Fqx '<Multi_key> <space> <n> : "Abdulrahman \"Q\" Yaqyn"' \
  "$xcompose" || fail "escaped XCompose name"
grep -Fqx '<Multi_key> <space> <e> : "Yaqyn\\\\test@pm.me"' \
  "$xcompose" || fail "escaped XCompose email"
[[ $(stat -c '%a' "$xcompose") == "644" ]] || fail "XCompose mode"

printf '%s\n' \
  'include "%H/custom/xcompose"' \
  '# custom composition' >"$xcompose"
run_leaf "$xcompose_leaf" >/dev/null
grep -Fqx 'include "%H/custom/xcompose"' \
  "$xcompose" || fail "custom XCompose include preservation"
grep -Fqx '# custom composition' "$xcompose" ||
  fail "custom XCompose content preservation"
mapfile -t xcompose_backups < <(
  find "$test_home" -maxdepth 1 -type f -name '.XCompose.qvos-backup.*' -print
)
((${#xcompose_backups[@]} == 0)) || fail "custom XCompose created a backup"

printf 'custom XCompose\n' >"$xcompose"
run_leaf "$xcompose_leaf" >/dev/null
grep -Fqx 'custom XCompose' "$xcompose" || fail "custom XCompose preservation"

xcompose_external="$test_root/xcompose-external"
printf 'external\n' >"$xcompose_external"
rm -- "$xcompose"
ln -s "$xcompose_external" "$xcompose"
if run_leaf "$xcompose_leaf" >/dev/null 2>&1; then
  fail "XCompose symbolic-link rejection"
fi
grep -Fqx 'external' "$xcompose_external" || fail "XCompose link target mutation"

retired_xcompose_restart='omarchy'"-restart-xcompose"
if rg -n 'local/share/(qvos|omarchy)/default/xcompose' "$xcompose_leaf" ||
  grep -Fn -- "$retired_xcompose_restart" "$xcompose_leaf"; then
  fail "retired XCompose convergence remains active"
fi

rm -f -- "$xcompose"
bluetooth_leaf="$root/qvcore/install/config/hardware/bluetooth.sh"
HOME="$test_home" \
  QVOS_PATH="$fixture" \
  bash -c '
    set -euo pipefail
    chrootable_systemctl_enable() { :; }
    source "$1"
  ' _ "$bluetooth_leaf"
bluetooth_policy="$test_home/.config/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf"
cmp -s \
  "$fixture/qvcore/config/files/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf" \
  "$bluetooth_policy" || fail "Bluetooth audio policy install"
printf 'custom Bluetooth policy\n' >"$bluetooth_policy"
HOME="$test_home" QVOS_PATH="$fixture" bash -c '
  set -euo pipefail
  chrootable_systemctl_enable() { :; }
  source "$1"
' _ "$bluetooth_leaf" >/dev/null
grep -Fqx 'custom Bluetooth policy' "$bluetooth_policy" ||
  fail "custom Bluetooth audio policy preservation"

rm -- "$bluetooth_policy"
bluetooth_external="$test_root/bluetooth-external"
printf 'external\n' >"$bluetooth_external"
ln -s "$bluetooth_external" "$bluetooth_policy"
if HOME="$test_home" QVOS_PATH="$fixture" bash -c '
  set -euo pipefail
  chrootable_systemctl_enable() { :; }
  source "$1"
' _ "$bluetooth_leaf" >/dev/null 2>&1; then
  fail "Bluetooth audio policy symbolic-link rejection"
fi
grep -Fqx 'external' "$bluetooth_external" ||
  fail "Bluetooth audio policy link target mutation"

rm -- "$bluetooth_policy"
asus_leaf="$root/qvcore/install/config/hardware/asus/fix-audio-mixer.sh"
HOME="$test_home" \
  QVOS_PATH="$fixture" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  bash -c 'set -euo pipefail; source "$1"' _ "$asus_leaf"
asus_policy="$test_home/.config/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf"
cmp -s \
  "$fixture/qvcore/config/files/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf" \
  "$asus_policy" || fail "ASUS audio policy install"

"$root/qvcore/config/check"
"$root/qvcore/hardware/check"
printf 'ok - native desktop configuration payloads are preserving and link-safe\n'
