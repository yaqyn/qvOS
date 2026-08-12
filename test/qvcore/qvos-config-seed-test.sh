#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
config_owner="$root/qvcore/config/seed"
shell_owner="$root/qvcore/shell/seed"
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

"$root/qvcore/config/check"
"$root/qvcore/shell/check"
