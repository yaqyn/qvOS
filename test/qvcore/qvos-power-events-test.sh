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

legacy_profile="${root%/*}/omarchy/bin/omarchy-powerprofiles-set"
printf 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service %s"\n' \
  "$legacy_profile" >"$profile_rule"
printf 'SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service %s"\n' \
  "$legacy_profile" >>"$profile_rule"

legacy_wifi="$root/bin/omarchy-wifi-powersave"
printf 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-on %s on"\n' \
  "$legacy_wifi" >"$wifi_rule"
printf 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-off %s off"\n' \
  "$legacy_wifi" >>"$wifi_rule"
legacy_wifi_content=$(<"$wifi_rule")

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

helper_root="$system_root/usr/lib/qvos/power"
for helper in profiles-set supply-lib wifi-powersave; do
  mode=755
  [[ $helper != "supply-lib" ]] || mode=644
  [[ -f $helper_root/$helper && ! -L $helper_root/$helper ]] ||
    fail "root-owned power helper type: $helper"
  [[ $(stat -c '%u:%g:%a' -- "$helper_root/$helper") == \
    "$(id -u):$(id -g):$mode" ]] || fail "root-owned power helper mode: $helper"
  cmp -s "$root/qvcore/power/$helper" "$helper_root/$helper" ||
    fail "root-owned power helper payload: $helper"
done

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
[[ $(find "$rules_dir" -maxdepth 1 -name '*.qvos-backup.*' | wc -l) == "2" ]] ||
  fail "known AC-event rule backups"

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
printf '%s\n' "$legacy_wifi_content" >"$rollback_rule"
rollback_before=$(<"$rollback_rule")
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
[[ $(<"$rollback_rule") == "$rollback_before" ]] ||
  fail "Wi-Fi rule activation rollback"

outside="$test_root/outside-helper"
printf 'outside\n' >"$outside"
rm -f -- "$helper_root/wifi-powersave"
ln -s "$outside" "$helper_root/wifi-powersave"
if run_event_owner "$root/qvcore/power/root-install" >/dev/null 2>&1; then
  fail "linked root helper target was replaced"
fi
[[ $(<"$outside") == "outside" ]] || fail "linked helper target preservation"

printf 'ok - AC events execute only root-owned qvOS power helpers with rollback\n'
