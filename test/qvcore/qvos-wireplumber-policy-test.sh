#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
policy_root="$test_home/.config/wireplumber/wireplumber.conf.d"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

run_owner() {
  HOME="$test_home" QVOS_PATH="$root" \
    "$root/qvcore/config/wireplumber-policy" "$@"
}

install -d -m 0700 "$test_home"
for _ in {1..10}; do
  run_owner bluetooth-a2dp &
done
wait
bluetooth_policy="$policy_root/bluetooth-a2dp-autoconnect.conf"
cmp -s \
  "$root/qvcore/config/files/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf" \
  "$bluetooth_policy" || fail "concurrent Bluetooth policy publication"
if find "$policy_root" -name '.qvos-wireplumber.*' -print -quit | grep -q .; then
  fail "WirePlumber owner left staging files"
fi
inode=$(stat -c '%i' "$bluetooth_policy")
run_owner bluetooth-a2dp
[[ $(stat -c '%i' "$bluetooth_policy") == "$inode" ]] ||
  fail "exact Bluetooth policy was replaced"
pass "native WirePlumber policy is concurrent and idempotent"

printf 'custom Bluetooth policy\n' >"$bluetooth_policy"
run_owner bluetooth-a2dp >/dev/null
grep -Fqx 'custom Bluetooth policy' "$bluetooth_policy" ||
  fail "custom Bluetooth policy was overwritten"
pass "custom regular policy remains user-owned"

chmod 0666 "$bluetooth_policy"
if run_owner bluetooth-a2dp >/dev/null 2>&1; then
  fail "writable policy target was accepted"
fi
grep -Fqx 'custom Bluetooth policy' "$bluetooth_policy" ||
  fail "writable policy target was changed"
chmod 0644 "$bluetooth_policy"

rm -- "$bluetooth_policy"
outside="$test_root/outside-policy"
printf 'outside\n' >"$outside"
ln -s -- "$outside" "$bluetooth_policy"
if run_owner bluetooth-a2dp >/dev/null 2>&1; then
  fail "linked policy target was accepted"
fi
grep -Fqx 'outside' "$outside" || fail "linked policy target was changed"
rm -- "$bluetooth_policy"

rm -rf -- "$test_home/.config/wireplumber"
outside_dir="$test_root/outside-dir"
install -d "$outside_dir"
ln -s -- "$outside_dir" "$test_home/.config/wireplumber"
if run_owner asus-soft-mixer >/dev/null 2>&1; then
  fail "linked WirePlumber parent was accepted"
fi
[[ -z $(find "$outside_dir" -mindepth 1 -print -quit) ]] ||
  fail "linked WirePlumber parent received policy"
pass "linked policy and parent paths fail closed"

rm -- "$test_home/.config/wireplumber"
install -d "$test_home/.config/wireplumber"
chmod 0775 "$test_home/.config/wireplumber"
if run_owner asus-soft-mixer >/dev/null 2>&1; then
  fail "writable WirePlumber parent was accepted"
fi
chmod 0755 "$test_home/.config/wireplumber"

install -d "$policy_root"
run_owner asus-soft-mixer
cmp -s \
  "$root/qvcore/config/files/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf" \
  "$policy_root/alsa-soft-mixer.conf" ||
  fail "ASUS soft-mixer policy install"
pass "ASUS soft-mixer policy uses the shared owner"

if run_owner unknown >/dev/null 2>&1; then
  fail "unknown WirePlumber policy was accepted"
fi
if run_owner bluetooth-a2dp extra >/dev/null 2>&1; then
  fail "WirePlumber policy accepted extra arguments"
fi
pass "WirePlumber policy inventory is bounded"
