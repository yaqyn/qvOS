#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d)
system_root="$test_root/system"
rules_dir="$system_root/etc/udev/rules.d"
profile_rule="$rules_dir/99-power-profile.rules"
wifi_rule="$rules_dir/99-wifi-powersave.rules"
power_root="$test_root/power-supply"
network_root="$test_root/network"
test_bin="$test_root/bin"
event_log="$test_root/events.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$rules_dir" \
  "$power_root/AC" \
  "$power_root/USB-C" \
  "$network_root/wlan0/wireless" \
  "$test_bin"
printf 'Mains\n' >"$power_root/AC/type"
printf '1\n' >"$power_root/AC/online"
printf 'USB_PD\n' >"$power_root/USB-C/type"
printf '0\n' >"$power_root/USB-C/online"

install -m 0755 /dev/stdin "$test_bin/udevadm" <<'SCRIPT'
#!/bin/bash
printf 'udevadm|%s\n' "$*" >>"$QVOS_TEST_POWER_EVENT_LOG"
[[ ${QVOS_TEST_UDEV_FAIL:-} != "${1:-}" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/powerprofilesctl" <<'SCRIPT'
#!/bin/bash
printf 'powerprofilesctl|path|%s\n' "$PATH" >>"$QVOS_TEST_POWER_EVENT_LOG"
case ${1:-} in
list)
  printf '  power-saver:\n* balanced:\n  performance:\n'
  ;;
set)
  printf 'powerprofilesctl|set|%s\n' "$2" >>"$QVOS_TEST_POWER_EVENT_LOG"
  ;;
*) exit 2 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/iw" <<'SCRIPT'
#!/bin/bash
printf 'iw|%s\n' "$*" >>"$QVOS_TEST_POWER_EVENT_LOG"
[[ ${QVOS_TEST_IW_FAIL:-} != "1" ]]
SCRIPT

run_event_owner() {
  QVOS_PATH="$root" \
  QVOS_POWER_TESTING=1 \
  QVOS_POWER_SYSTEM_ROOT="$system_root" \
  QVOS_POWER_PROFILE_RULE="$profile_rule" \
  QVOS_POWER_WIFI_RULE="$wifi_rule" \
  QVOS_UDEVADM="$test_bin/udevadm" \
  QVOS_TEST_POWER_EVENT_LOG="$event_log" \
  "$@"
}

run_event_owner "$root/qvcore/power/profile-rule" >/dev/null
run_event_owner "$root/qvcore/power/wifi-rule" >/dev/null

chroot_system_root="$test_root/chroot-system"
chroot_rules_dir="$chroot_system_root/etc/udev/rules.d"
chroot_profile_rule="$chroot_rules_dir/99-power-profile.rules"
chroot_wifi_rule="$chroot_rules_dir/99-wifi-powersave.rules"
install -d "$chroot_rules_dir"
: >"$event_log"
for chroot_rule in profile wifi; do
  QVOS_PATH="$root" \
  QVOS_CHROOT_INSTALL=1 \
  QVOS_POWER_TESTING=1 \
  QVOS_POWER_SYSTEM_ROOT="$chroot_system_root" \
  QVOS_POWER_PROFILE_RULE="$chroot_profile_rule" \
  QVOS_POWER_WIFI_RULE="$chroot_wifi_rule" \
  QVOS_UDEVADM="$test_bin/udevadm" \
  QVOS_TEST_POWER_EVENT_LOG="$event_log" \
    "$root/qvcore/power/$chroot_rule-rule" >/dev/null
done
[[ -f $chroot_profile_rule && -f $chroot_wifi_rule ]] ||
  fail "target-chroot AC-event rule publication"
[[ ! -s $event_log ]] ||
  fail "target-chroot AC-event owner contacted the build host's udev manager"
if QVOS_PATH="$root" \
  QVOS_CHROOT_INSTALL=invalid \
  QVOS_POWER_TESTING=1 \
  QVOS_POWER_SYSTEM_ROOT="$test_root/invalid-chroot" \
  QVOS_UDEVADM="$test_bin/udevadm" \
  QVOS_TEST_POWER_EVENT_LOG="$event_log" \
  "$root/qvcore/power/profile-rule" >/dev/null 2>&1; then
  fail "invalid target-chroot signal was accepted by the AC-event owner"
fi
printf 'ok - target-chroot AC-event installation never touches host udev\n'

stage_root="$test_root/stage-root"
stage_bin="$stage_root/bin"
stage_log="$test_root/profile-stage.log"
install -d "$stage_bin" "$stage_root/qvcore/power"
install -m 0755 /dev/stdin "$stage_bin/qv-battery-present" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$stage_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo|%s\n' "$*" >>"$QVOS_TEST_PROFILE_STAGE_LOG"
SCRIPT
install -m 0755 /dev/stdin "$stage_root/qvcore/power/profile-rule" <<'SCRIPT'
#!/bin/bash
printf 'profile-rule\n' >>"$QVOS_TEST_PROFILE_STAGE_LOG"
SCRIPT

run_profile_stage() {
  QVOS_PATH="$stage_root" \
  QVOS_TEST_PROFILE_STAGE_LOG="$stage_log" \
  PATH="$stage_bin:/usr/bin" \
    bash -c 'source "$1"' _ \
    "$root/qvcore/install/config/powerprofilesctl-rules.sh"
}

: >"$stage_log"
QVOS_CHROOT_INSTALL=1 run_profile_stage
grep -Fqx 'profile-rule' "$stage_log" ||
  fail "target-chroot profile stage omitted rule publication"
grep -Fqx 'sudo|systemctl enable power-profiles-daemon' "$stage_log" ||
  fail "target-chroot profile stage omitted installed service enablement"
if grep -Fq 'udevadm' "$stage_log"; then
  fail "target-chroot profile stage triggered build-host hardware"
fi
: >"$stage_log"
run_profile_stage
grep -Fqx 'sudo|udevadm trigger --subsystem-match=power_supply' "$stage_log" ||
  fail "live profile stage omitted initial power-supply activation"
printf 'ok - profile-stage activation is isolated from target chroots\n'

helper_root="$system_root/usr/lib/qvos/power"
for helper in profiles-command profiles-set supply-lib wifi-powersave; do
  mode=755
  [[ $helper != "profiles-command" && $helper != "supply-lib" ]] || mode=644
  [[ -f $helper_root/$helper && ! -L $helper_root/$helper ]] ||
    fail "root-owned power helper type: $helper"
  [[ $(stat -c '%u:%g:%a' -- "$helper_root/$helper") == \
    "$(id -u):$(id -g):$mode" ]] || fail "root-owned power helper mode: $helper"
  cmp -s "$root/qvcore/power/$helper" "$helper_root/$helper" ||
    fail "root-owned power helper payload: $helper"
done

sleep_dir="$system_root/usr/lib/systemd/system-sleep"
sleep_hook="$sleep_dir/qvos-unmount-fuse"
[[ -f $sleep_hook && ! -L $sleep_hook ]] ||
  fail "root-owned FUSE sleep hook type"
[[ $(stat -c '%u:%g:%a' -- "$sleep_hook") == \
  "$(id -u):$(id -g):755" ]] || fail "root-owned FUSE sleep hook mode"
cmp -s "$root/qvcore/power/unmount-fuse" "$sleep_hook" ||
  fail "root-owned FUSE sleep hook payload"

printf 'foreign sleep hook\n' >"$sleep_dir/unmount-fuse"
chmod 0755 "$sleep_dir/unmount-fuse"
run_event_owner "$root/qvcore/power/root-install" >/dev/null
[[ $(<"$sleep_dir/unmount-fuse") == "foreign sleep hook" ]] ||
  fail "foreign sleep hook preservation"

grep -Fq "$helper_root/profiles-set autodetect" "$profile_rule" ||
  fail "power-profile rule root helper"
grep -Fq 'ATTR{type}=="USB*"' "$profile_rule" ||
  fail "power-profile USB-C event"
grep -Fq 'ATTR{type}=="Wireless"' "$profile_rule" ||
  fail "power-profile wireless event"
grep -Fq "$helper_root/wifi-powersave auto" "$wifi_rule" ||
  fail "Wi-Fi rule root helper"
grep -Fq 'ATTR{type}=="USB*"' "$wifi_rule" || fail "Wi-Fi USB-C event"
grep -Fq 'ATTR{type}=="Wireless"' "$wifi_rule" || fail "Wi-Fi wireless event"
for property in \
  CapabilityBoundingSet= \
  NoNewPrivileges=yes \
  PrivateTmp=yes \
  ProtectHome=yes \
  ProtectSystem=strict; do
  grep -Fq "$property" "$profile_rule" ||
    fail "power-profile service hardening: $property"
done
for property in \
  CapabilityBoundingSet=CAP_NET_ADMIN \
  NoNewPrivileges=yes \
  PrivateTmp=yes \
  ProtectHome=yes \
  ProtectSystem=strict; do
  grep -Fq "$property" "$wifi_rule" || fail "Wi-Fi service hardening: $property"
done
if rg -q '/home/|\.local/share/(qvos|omarchy)|omarchy-' \
  "$profile_rule" "$wifi_rule"; then
  fail "root event rule retains a user-writable or inherited command"
fi
/usr/bin/udevadm verify --resolve-names=never --no-summary --no-style \
  "$profile_rule" "$wifi_rule" >/dev/null || fail "generated udev rule syntax"
[[ $(find "$rules_dir" -maxdepth 1 -name '*.qvos-backup.*' | wc -l) == "0" ]] ||
  fail "fresh AC-event rule backup side effect"

: >"$event_log"
QVOS_POWER_TESTING=1 \
QVOS_POWER_SUPPLY_ROOT="$power_root" \
QVOS_TEST_POWER_EVENT_LOG="$event_log" \
PATH="$test_bin:/usr/bin" \
  "$helper_root/profiles-set" autodetect
grep -Fqx 'powerprofilesctl|set|performance' "$event_log" ||
  fail "root-owned profile AC policy"
QVOS_POWER_TESTING=1 \
QVOS_POWER_SUPPLY_ROOT="$power_root" \
QVOS_POWER_NETWORK_ROOT="$network_root" \
QVOS_IW="$test_bin/iw" \
QVOS_TEST_POWER_EVENT_LOG="$event_log" \
  "$helper_root/wifi-powersave" auto
grep -Fqx 'iw|dev wlan0 set power_save off' "$event_log" ||
  fail "root-owned Wi-Fi AC policy"

printf '0\n' >"$power_root/AC/online"
: >"$event_log"
printf '1\n' >"$power_root/USB-C/online"
QVOS_POWER_TESTING=1 \
QVOS_POWER_SUPPLY_ROOT="$power_root" \
QVOS_TEST_POWER_EVENT_LOG="$event_log" \
PATH="$test_bin:/usr/bin" \
  "$helper_root/profiles-set" autodetect
grep -Fqx 'powerprofilesctl|set|performance' "$event_log" ||
  fail "root-owned profile USB-C policy"
QVOS_POWER_TESTING=1 \
QVOS_POWER_SUPPLY_ROOT="$power_root" \
QVOS_POWER_NETWORK_ROOT="$network_root" \
QVOS_IW="$test_bin/iw" \
QVOS_TEST_POWER_EVENT_LOG="$event_log" \
  "$helper_root/wifi-powersave" auto
grep -Fqx 'iw|dev wlan0 set power_save off' "$event_log" ||
  fail "root-owned Wi-Fi USB-C policy"

printf '0\n' >"$power_root/USB-C/online"
: >"$event_log"
QVOS_POWER_TESTING=1 \
QVOS_POWER_SUPPLY_ROOT="$power_root" \
QVOS_TEST_POWER_EVENT_LOG="$event_log" \
PATH="$test_bin:/usr/bin" \
  "$helper_root/profiles-set" autodetect
grep -Fqx 'powerprofilesctl|set|balanced' "$event_log" ||
  fail "root-owned profile battery policy"
if grep '^powerprofilesctl|path|' "$event_log" |
  grep -Fvx 'powerprofilesctl|path|/usr/bin:/bin' >/dev/null; then
  fail "root power profile event inherited a user Python path"
fi
QVOS_POWER_TESTING=1 \
QVOS_POWER_SUPPLY_ROOT="$power_root" \
QVOS_POWER_NETWORK_ROOT="$network_root" \
QVOS_IW="$test_bin/iw" \
QVOS_TEST_POWER_EVENT_LOG="$event_log" \
  "$helper_root/wifi-powersave" auto
grep -Fqx 'iw|dev wlan0 set power_save on' "$event_log" ||
  fail "root-owned Wi-Fi battery policy"
event_snapshot=$(<"$event_log")
if QVOS_POWER_TESTING=1 \
  QVOS_POWER_SUPPLY_ROOT="$power_root" \
  QVOS_POWER_NETWORK_ROOT="$network_root" \
  QVOS_IW="$test_bin/iw" \
  QVOS_TEST_POWER_EVENT_LOG="$event_log" \
  "$helper_root/wifi-powersave" invalid >/dev/null 2>&1; then
  fail "invalid Wi-Fi power mode was accepted"
fi
[[ $(<"$event_log") == "$event_snapshot" ]] ||
  fail "invalid Wi-Fi power mode mutated an interface"
if QVOS_POWER_TESTING=1 \
  QVOS_POWER_SUPPLY_ROOT="$power_root" \
  QVOS_POWER_NETWORK_ROOT="$network_root" \
  QVOS_IW="$test_bin/iw" \
  QVOS_TEST_IW_FAIL=1 \
  QVOS_TEST_POWER_EVENT_LOG="$event_log" \
  "$helper_root/wifi-powersave" on >/dev/null 2>&1; then
  fail "Wi-Fi interface failure was hidden"
fi

state_before=$(find "$system_root" -type f -printf '%P|%m|%i|%T@\n' | sort)
run_event_owner "$root/qvcore/power/profile-rule" >/dev/null
run_event_owner "$root/qvcore/power/wifi-rule" >/dev/null
[[ $(find "$system_root" -type f -printf '%P|%m|%i|%T@\n' | sort) == \
  "$state_before" ]] || fail "idempotent root event installation"

root_install_source=$(<"$root/qvcore/power/root-install")
[[ $root_install_source == *'system_helpers_ready && exit'* ]] ||
  fail "exact root helpers do not avoid repeated sudo"

unknown_rule="$rules_dir/unknown-wifi.rules"
printf 'foreign Wi-Fi rule\n' >"$unknown_rule"
if QVOS_PATH="$root" \
  QVOS_POWER_TESTING=1 \
  QVOS_POWER_SYSTEM_ROOT="$system_root" \
  QVOS_POWER_WIFI_RULE="$unknown_rule" \
  QVOS_UDEVADM="$test_bin/udevadm" \
  QVOS_TEST_POWER_EVENT_LOG="$event_log" \
  "$root/qvcore/power/wifi-rule" >/dev/null 2>&1; then
  fail "foreign Wi-Fi rule was overwritten"
fi
[[ $(<"$unknown_rule") == "foreign Wi-Fi rule" ]] ||
  fail "foreign Wi-Fi rule preservation"

rollback_rule="$rules_dir/rollback-wifi.rules"
if QVOS_PATH="$root" \
  QVOS_POWER_TESTING=1 \
  QVOS_POWER_SYSTEM_ROOT="$system_root" \
  QVOS_POWER_WIFI_RULE="$rollback_rule" \
  QVOS_UDEVADM="$test_bin/udevadm" \
  QVOS_TEST_UDEV_FAIL=trigger \
  QVOS_TEST_POWER_EVENT_LOG="$event_log" \
  "$root/qvcore/power/wifi-rule" >/dev/null 2>&1; then
  fail "Wi-Fi trigger failure was hidden"
fi
[[ ! -e $rollback_rule && ! -L $rollback_rule ]] ||
  fail "new Wi-Fi rule activation rollback"

outside="$test_root/outside-helper"
printf 'outside\n' >"$outside"
rm -f -- "$helper_root/wifi-powersave"
ln -s "$outside" "$helper_root/wifi-powersave"
if run_event_owner "$root/qvcore/power/root-install" >/dev/null 2>&1; then
  fail "linked root helper target was replaced"
fi
[[ $(<"$outside") == "outside" ]] || fail "linked helper target preservation"

printf 'ok - AC events execute only root-owned qvOS power helpers with rollback\n'
