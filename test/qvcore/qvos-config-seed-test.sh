#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
config_owner="$root/qvcore/config/seed"
shell_owner="$root/qvcore/shell/seed"
shell_reset_owner="$root/qvcore/shell/reset"
refresh_owner="$root/qvcore/config/refresh"
manifest="$root/qvcore/config/seed-files"
test_root=$(mktemp -d)

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_config_seed() {
  HOME=$1 QVOS_PATH="$root" "$config_owner"
}

run_shell_seed() {
  HOME=$1 QVOS_PATH="$root" "$shell_owner"
}

fresh_home="$test_root/fresh-home"
install -d -m 0700 "$fresh_home"
run_config_seed "$fresh_home"
while IFS= read -r relative; do
  cmp -s "$root/qvcore/config/files/$relative" \
    "$fresh_home/.config/$relative" || fail "fresh base seed: $relative"
done <"$manifest"
for feature_owned in \
  autostart/walker.desktop \
  elephant/calc.toml \
  qvos/extensions/menu.sh \
  systemd/user/qvos-battery-monitor.service \
  systemd/user/qvos-swayosd-server.service \
  walker/config.toml \
  wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf \
  xcompose; do
  [[ ! -e $fresh_home/.config/$feature_owned &&
    ! -L $fresh_home/.config/$feature_owned ]] ||
    fail "feature-owned config leaked into base seed: $feature_owned"
done
[[ ! -d $fresh_home/.config/chromium ]] ||
  fail "base seed pre-created a Chromium profile"
printf 'ok - base config seeds only its explicit native inventory\n'

custom="$fresh_home/.config/hypr/bindings.lua"
printf 'custom bindings\n' >"$custom"
snapshot=$(find "$fresh_home/.config" -type f -printf '%P|%i|%T@\n' | sort)
run_config_seed "$fresh_home"
grep -Fqx 'custom bindings' "$custom" || fail "custom config preservation"
[[ $(find "$fresh_home/.config" -type f -printf '%P|%i|%T@\n' | sort) == \
  "$snapshot" ]] || fail "idempotent base config seed"
printf 'ok - config seed preserves existing files and exact reruns\n'

unsafe_home="$test_root/unsafe-home"
outside="$test_root/outside-config"
install -d -m 0700 "$unsafe_home/.config/btop"
printf 'outside\n' >"$outside"
ln -s "$outside" "$unsafe_home/.config/btop/btop.conf"
if run_config_seed "$unsafe_home" >/dev/null 2>&1; then
  fail "config seed accepted a linked target"
fi
grep -Fqx outside "$outside" || fail "config seed followed a linked target"
[[ ! -e $unsafe_home/.config/Thunar/accels.scm ]] ||
  fail "config seed mutated before completing preflight"

rm -- "$unsafe_home/.config/btop/btop.conf"
install -m 0666 /dev/null "$unsafe_home/.config/btop/btop.conf"
if run_config_seed "$unsafe_home" >/dev/null 2>&1; then
  fail "config seed accepted a writable target"
fi

linked_parent_home="$test_root/linked-parent-home"
linked_parent_outside="$test_root/linked-parent-outside"
install -d -m 0700 "$linked_parent_home/.config" "$linked_parent_outside"
ln -s "$linked_parent_outside" "$linked_parent_home/.config/hypr"
if run_config_seed "$linked_parent_home" >/dev/null 2>&1; then
  fail "config seed accepted a linked parent"
fi
[[ -z $(find "$linked_parent_outside" -mindepth 1 -print -quit) ]] ||
  fail "config seed wrote through a linked parent"
[[ ! -e $linked_parent_home/.config/Thunar/accels.scm ]] ||
  fail "config seed did not preflight all parent paths"
printf 'ok - config seed fails closed before unsafe path mutation\n'

concurrent_home="$test_root/concurrent-home"
install -d -m 0700 "$concurrent_home"
for _ in {1..10}; do
  run_config_seed "$concurrent_home" &
done
wait
while IFS= read -r relative; do
  cmp -s "$root/qvcore/config/files/$relative" \
    "$concurrent_home/.config/$relative" ||
    fail "concurrent base seed: $relative"
done <"$manifest"
if find "$concurrent_home" -name '.qvos-config-seed.*' -print -quit | grep -q .; then
  fail "config seed left staging residue"
fi
printf 'ok - config seed serializes concurrent publication\n'

shell_home="$test_root/shell-home"
install -d -m 0700 "$shell_home"
for _ in {1..8}; do
  run_shell_seed "$shell_home" &
done
wait
cmp -s "$root/qvcore/shell/files/bashrc" "$shell_home/.bashrc" ||
  fail "fresh Bash seed"
bash_inode=$(stat -c '%i' "$shell_home/.bashrc")
run_shell_seed "$shell_home"
[[ $(stat -c '%i' "$shell_home/.bashrc") == "$bash_inode" ]] ||
  fail "exact Bash seed was replaced"
printf 'custom Bash\n' >"$shell_home/.bashrc"
run_shell_seed "$shell_home"
grep -Fqx 'custom Bash' "$shell_home/.bashrc" ||
  fail "custom Bash seed was overwritten"

unsafe_shell_home="$test_root/unsafe-shell-home"
unsafe_shell_outside="$test_root/unsafe-shell-outside"
install -d -m 0700 "$unsafe_shell_home"
printf 'outside Bash\n' >"$unsafe_shell_outside"
ln -s "$unsafe_shell_outside" "$unsafe_shell_home/.bashrc"
if run_shell_seed "$unsafe_shell_home" >/dev/null 2>&1; then
  fail "Bash seed accepted a linked target"
fi
grep -Fqx 'outside Bash' "$unsafe_shell_outside" ||
  fail "Bash seed followed a linked target"
printf 'ok - Bash seed is missing-only, concurrent, and link-safe\n'

refresh_home="$test_root/refresh-home"
install -d -m 0700 "$refresh_home/.config/btop"
printf 'custom btop\n' >"$refresh_home/.config/btop/btop.conf"
refresh_snapshot=$(find "$refresh_home" -printf '%P|%m|%i|%T@\n' | sort)
HOME="$refresh_home" QVOS_PATH="$root" \
  "$refresh_owner" --preflight btop/btop.conf
[[ $(find "$refresh_home" -printf '%P|%m|%i|%T@\n' | sort) == \
  "$refresh_snapshot" ]] || fail "config refresh preflight mutated state"
HOME="$refresh_home" QVOS_PATH="$root" \
  "$refresh_owner" btop/btop.conf
cmp -s "$root/qvcore/config/files/btop/btop.conf" \
  "$refresh_home/.config/btop/btop.conf" || fail "config refresh value"
mapfile -t refresh_backups < <(
  find "$refresh_home/.local/state/qvos/config-backups/refresh" \
    -mindepth 2 -maxdepth 2 -type f -name value -print
)
(( ${#refresh_backups[@]} == 1 )) || fail "one private config refresh backup"
grep -Fqx 'custom btop' "${refresh_backups[0]}" ||
  fail "config refresh backup value"

unsafe_refresh_home="$test_root/unsafe-refresh-home"
unsafe_refresh_outside="$test_root/unsafe-refresh-outside"
install -d -m 0700 "$unsafe_refresh_home/.config" "$unsafe_refresh_outside"
ln -s "$unsafe_refresh_outside" "$unsafe_refresh_home/.config/btop"
if HOME="$unsafe_refresh_home" QVOS_PATH="$root" \
  "$refresh_owner" --preflight btop/btop.conf >/dev/null 2>&1; then
  fail "config refresh accepted a linked target parent"
fi
[[ -z $(find "$unsafe_refresh_outside" -mindepth 1 -print -quit) &&
  ! -e $unsafe_refresh_home/.local && ! -L $unsafe_refresh_home/.local ]] ||
  fail "config refresh preflight changed unsafe state"
printf 'ok - config refresh preflights privately and rejects unsafe ancestors\n'

reset_home="$test_root/reset-home"
install -d -m 0700 "$reset_home"
printf 'custom Bash\n' >"$reset_home/.bashrc"
printf 'custom login shell\n' >"$reset_home/.bash_profile"
reset_snapshot=$(find "$reset_home" -printf '%P|%m|%i|%T@\n' | sort)
HOME="$reset_home" QVOS_PATH="$root" "$shell_reset_owner" --preflight
[[ $(find "$reset_home" -printf '%P|%m|%i|%T@\n' | sort) == \
  "$reset_snapshot" ]] || fail "Bash reset preflight mutated state"
HOME="$reset_home" QVOS_PATH="$root" "$shell_reset_owner"
cmp -s "$root/qvcore/shell/files/bashrc" "$reset_home/.bashrc" ||
  fail "explicit Bash reset"
grep -Fqx 'custom login shell' "$reset_home/.bash_profile" ||
  fail "Bash reset changed login-shell state"
mapfile -t reset_backups < <(
  find "$reset_home/.local/state/qvos/shell-backups" \
    -maxdepth 1 -type f -name 'bashrc-reset.*' -print
)
(( ${#reset_backups[@]} == 1 )) || fail "one private Bash reset backup"
grep -Fqx 'custom Bash' "${reset_backups[0]}" || fail "Bash reset backup value"
bash_reset_inode=$(stat -c '%i' "$reset_home/.bashrc")
login_reset_hash=$(sha256sum "$reset_home/.bash_profile")
HOME="$reset_home" QVOS_PATH="$root" "$shell_reset_owner"
mapfile -t exact_reset_backups < <(
  find "$reset_home/.local/state/qvos/shell-backups" \
    -maxdepth 1 -type f -name 'bashrc-reset.*' -print
)
[[ $(stat -c '%i' "$reset_home/.bashrc") == "$bash_reset_inode" &&
  $(sha256sum "$reset_home/.bash_profile") == "$login_reset_hash" &&
  ${#exact_reset_backups[@]} == 1 ]] ||
  fail "exact Bash reset was not idempotent"
printf 'ok - explicit Bash reset is private, preserving, and idempotent\n'

"$root/qvcore/config/check"
"$root/qvcore/shell/check"
