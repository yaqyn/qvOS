#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
fixture="$test_root/fixture"
sysfs_root="$test_root/sys"
state_root="$test_root/state"
runtime_root="$test_root/runtime"
system_root="$test_root/system"
test_bin="$test_root/bin"
backend="$test_bin/power-backend"
systemctl_log="$test_root/systemctl.log"
power="$root/qv/power/battery-protection"
helper="$root/qv/power/battery-protection-hwdb"

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

install -d "$test_bin" "$runtime_root"

install -m 0755 /dev/stdin "$backend" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

fixture=$QVOS_TEST_FIXTURE

property_file() {
  printf '%s/%s.properties\n' "$fixture" "${1##*/}"
}

get_property() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); found = 1 } END { exit !found }' "$file"
}

set_property() {
  local file="$1"
  local key="$2"
  local value="$3"
  local temporary="$file.tmp"

  awk -F= -v key="$key" -v value="$value" '
    $1 == key { print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$file" >"$temporary"
  mv "$temporary" "$file"
}

case ${1:-} in
enumerate)
  [[ ! -e $fixture/upower-absent ]] || exit 1
  cat "$fixture/devices"
  ;;
get)
  get_property "$(property_file "$2")" "$3"
  ;;
set)
  [[ ! -e $fixture/polkit-deny ]] || exit 1
  file=$(property_file "$2")
  name=${2##*/}
  enabled=$3
  set_property "$file" ChargeThresholdEnabled "$enabled"
  mask=$(get_property "$file" ChargeThresholdSettingsSupported)
  path="$QVOS_POWER_SYSFS_ROOT/devices/${name#battery_}"

  if [[ $enabled == "false" ]]; then
    [[ ! -e $path/charge_types ]] ||
      printf 'Fast [Standard] Long_Life\n' >"$path/charge_types"
    [[ ! -e $path/charge_control_start_threshold ]] ||
      printf '0\n' >"$path/charge_control_start_threshold"
    [[ ! -e $path/charge_control_end_threshold ]] ||
      printf '100\n' >"$path/charge_control_end_threshold"
    exit 0
  fi

  if [[ -e $fixture/partial-write && $name == "battery_BAT1" ]]; then
    exit 1
  fi
  if [[ -e $fixture/wrong-readback ]]; then
    exit 0
  fi
  case $mask in
  4)
    printf 'Fast Standard [Long_Life]\n' >"$path/charge_types"
    ;;
  3)
    get_property "$file" ChargeStartThreshold >"$path/charge_control_start_threshold"
    get_property "$file" ChargeEndThreshold >"$path/charge_control_end_threshold"
    ;;
  2)
    get_property "$file" ChargeEndThreshold >"$path/charge_control_end_threshold"
    ;;
  esac
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemd-hwdb" <<'SCRIPT'
#!/bin/bash
[[ ! -e $QVOS_TEST_FIXTURE/hwdb-fail ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/udevadm" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

[[ ! -e $QVOS_TEST_FIXTURE/udev-fail ]] || exit 1
hwdb="$QVOS_POWER_HELPER_TEST_ROOT/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb"
[[ -f $hwdb ]] || exit 0
limit=$(awk -F= '/^ CHARGE_LIMIT=/{print $2}' "$hwdb")
start=${limit%,*}
end=${limit#*,}

while IFS= read -r object; do
  [[ $object == *"/battery_"* ]] || continue
  file="$QVOS_TEST_FIXTURE/${object##*/}.properties"
  [[ -f $file ]] || continue
  temporary="$file.tmp"
  awk -F= -v start="$start" -v end="$end" '
    $1 == "ChargeStartThreshold" && start != "_" {
      print "ChargeStartThreshold=" start
      next
    }
    $1 == "ChargeEndThreshold" {
      print "ChargeEndThreshold=" end
      next
    }
    { print }
  ' "$file" >"$temporary"
  mv "$temporary" "$file"
done <"$QVOS_TEST_FIXTURE/devices"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/pkexec" <<'SCRIPT'
#!/bin/bash
[[ ! -e $QVOS_TEST_FIXTURE/pkexec-deny ]] || exit 1
export QVOS_POWER_TESTING=1
export QVOS_POWER_HELPER_TEST_ROOT=$QVOS_POWER_SYSTEM_ROOT
export QVOS_POWER_HELPER_TEST_BIN=$QVOS_TEST_BIN
exec "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
if [[ $* == "is-active --quiet tlp.service" &&
  -e $QVOS_TEST_FIXTURE/conflict-tlp ]]; then
  exit 0
fi
if [[ $* == "--user is-enabled --quiet qvos-battery-full-charge-once.service" &&
  -e $QVOS_TEST_FIXTURE/service-disabled ]]; then
  exit 1
fi
if [[ $1 == "--user" ]]; then
  printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
  [[ ! -e $QVOS_TEST_FIXTURE/systemctl-fail ]]
  exit
fi
exit 1
SCRIPT

export QVOS_POWER_TESTING=1
export QVOS_POWER_BACKEND="$backend"
export QVOS_POWER_ROOT_HELPER="$helper"
export QVOS_POWER_PKEXEC="$test_bin/pkexec"
export QVOS_POWER_SYSTEMCTL="$test_bin/systemctl"
export QVOS_POWER_SYSFS_ROOT="$sysfs_root"
export QVOS_POWER_STATE_ROOT="$state_root"
export QVOS_POWER_SYSTEM_ROOT="$system_root"
export QVOS_POWER_VERIFY_ATTEMPTS=1
export QVOS_POWER_CONFIRM=yes
export QVOS_TEST_FIXTURE="$fixture"
export QVOS_TEST_BIN="$test_bin"
export QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log"
export XDG_RUNTIME_DIR="$runtime_root"

set_property() {
  local file="$1"
  local key="$2"
  local value="$3"
  local temporary="$file.tmp"

  awk -F= -v key="$key" -v value="$value" '
    $1 == key { print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$file" >"$temporary"
  mv "$temporary" "$file"
}

reset_fixture() {
  rm -rf "$fixture" "$sysfs_root" "$state_root" "$system_root"
  install -d \
    "$fixture" \
    "$sysfs_root/class/power_supply" \
    "$sysfs_root/devices" \
    "$system_root" \
    "$runtime_root"
  : >"$fixture/devices"
  : >"$systemctl_log"

  cat >"$fixture/line_power_AC.properties" <<'PROPS'
Type=1
PowerSupply=true
Online=true
PROPS
  printf '%s\n' \
    /org/freedesktop/UPower/devices/line_power_AC \
    >>"$fixture/devices"

  cat >"$fixture/DisplayDevice.properties" <<'PROPS'
Type=2
PowerSupply=true
Online=false
IsPresent=true
IsRechargeable=false
NativePath=
ChargeThresholdSupported=false
ChargeThresholdSettingsSupported=0
ChargeThresholdEnabled=false
ChargeStartThreshold=0
ChargeEndThreshold=0
State=1
Percentage=50
PROPS
  printf '%s\n' \
    /org/freedesktop/UPower/devices/DisplayDevice \
    >>"$fixture/devices"
}

add_battery() {
  local name="$1"
  local mask="$2"
  local enabled="${3:-false}"
  local start=75
  local end=80
  local path="$sysfs_root/devices/$name"
  local active=Standard

  install -d "$path"
  printf 'Battery\n' >"$path/type"
  printf '1\n' >"$path/present"
  ln -s "$path" "$sysfs_root/class/power_supply/$name"

  case $mask in
  2)
    start=0
    printf '%s\n' "$([[ $enabled == "true" ]] && printf '%s' "$end" || printf '100')" \
      >"$path/charge_control_end_threshold"
    ;;
  3)
    printf '%s\n' "$([[ $enabled == "true" ]] && printf '%s' "$start" || printf '0')" \
      >"$path/charge_control_start_threshold"
    printf '%s\n' "$([[ $enabled == "true" ]] && printf '%s' "$end" || printf '100')" \
      >"$path/charge_control_end_threshold"
    ;;
  4 | 6 | 7)
    [[ $enabled == "false" ]] || active=Long_Life
    if [[ $active == "Standard" ]]; then
      printf 'Fast [Standard] Long_Life\n' >"$path/charge_types"
    else
      printf 'Fast Standard [Long_Life]\n' >"$path/charge_types"
    fi
    ;;
  esac

  cat >"$fixture/battery_$name.properties" <<PROPS
Type=2
PowerSupply=true
Online=false
IsPresent=true
IsRechargeable=true
NativePath=$name
ChargeThresholdSupported=$([[ $mask == "0" ]] && printf false || printf true)
ChargeThresholdSettingsSupported=$mask
ChargeThresholdEnabled=$enabled
ChargeStartThreshold=$start
ChargeEndThreshold=$end
State=1
Percentage=50
PROPS
  printf '%s\n' \
    "/org/freedesktop/UPower/devices/battery_$name" \
    >>"$fixture/devices"
}

run_power() {
  "$power" "$@"
}

capture_power() {
  local output_file="$1"
  shift
  set +e
  run_power "$@" >"$output_file" 2>&1
  CAPTURE_STATUS=$?
  set -e
}

for mask in 0 1 5 6 7; do
  reset_fixture
  add_battery BAT0 "$mask"
  capture_power "$test_root/mask-$mask.log" status
  ((CAPTURE_STATUS != 0)) || fail "unsupported UPower mask $mask"
  grep -Fq 'Battery Protection: Unsupported' "$test_root/mask-$mask.log" ||
    fail "unsupported mask $mask status"
done
pass "unsupported, start-only, and conflicting UPower masks are refused"

for mask in 2 3 4; do
  reset_fixture
  add_battery BAT0 "$mask"
  capture_power "$test_root/mask-$mask.log" status
  ((CAPTURE_STATUS == 0)) || fail "supported UPower mask $mask"
  grep -Fq 'Battery Protection: Unmanaged' "$test_root/mask-$mask.log" ||
    fail "supported mask $mask status"
done
grep -Fq 'restart remains firmware-controlled' "$test_root/mask-2.log" ||
  fail "end-only restart disclosure"
pass "end-only, adjustable, and firmware-only capability shapes are truthful"

reset_fixture
add_battery BAT0 4
report=$(run_power report)
[[ $report == *"Batteries: 1"* ]] || fail "DisplayDevice filtering"
[[ $report != *"$sysfs_root"* && $report != *"Serial"* && $report != *"DMI="* ]] ||
  fail "report redaction"
pass "reports filter DisplayDevice and omit private identifiers and paths"

reset_fixture
add_battery BAT0 3
add_battery BAT1 3
[[ $(run_power report) == *"Batteries: 2"* ]] || fail "multiple matching batteries"
reset_fixture
add_battery BAT0 3
add_battery BAT1 2
capture_power "$test_root/mixed.log" status
((CAPTURE_STATUS != 0)) || fail "mixed capability batteries"
reset_fixture
add_battery BAT0 3
add_battery BAT1 0
capture_power "$test_root/unsupported-member.log" status
((CAPTURE_STATUS != 0)) || fail "unsupported battery member"
pass "every real battery must share the same safe capability"

reset_fixture
add_battery BAT0 4
touch "$fixture/upower-absent"
capture_power "$test_root/upower-absent.log" status
((CAPTURE_STATUS != 0)) || fail "absent UPower"
grep -Fq 'UPower is unavailable' "$test_root/upower-absent.log" ||
  fail "absent UPower reason"
pass "UPower absence is an inspection failure without mutation"

reset_fixture
add_battery BAT0 4
touch "$fixture/conflict-tlp"
capture_power "$test_root/conflict.log" enable plugged-in
((CAPTURE_STATUS != 0)) || fail "active TLP conflict"
[[ ! -e $state_root ]] || fail "conflicting manager state mutation"
grep -Fq 'tlp is active' "$test_root/conflict.log" ||
  fail "conflicting manager disclosure"
pass "known charging managers block mutation without being disabled"

reset_fixture
add_battery BAT0 4
export QVOS_POWER_CONFIRM=no
capture_power "$test_root/cancel.log" enable plugged-in
((CAPTURE_STATUS == 130)) || fail "interactive cancellation status"
[[ ! -e $state_root ]] || fail "cancellation state mutation"
export QVOS_POWER_CONFIRM=yes
capture_power "$test_root/malformed.log" enable maximum
((CAPTURE_STATUS == 2)) || fail "malformed preset status"
[[ ! -e $state_root ]] || fail "malformed preset mutation"
pass "cancellation and malformed input leave no state"

reset_fixture
add_battery BAT0 4
install -d -m 0700 "$state_root"
printf 'not qvOS state\n' >"$test_root/foreign-intent"
ln -s "$test_root/foreign-intent" "$state_root/intent"
capture_power "$test_root/symlinked-state.log" enable plugged-in
((CAPTURE_STATUS != 0)) || fail "symlinked intent mutation"
[[ $(<"$sysfs_root/devices/BAT0/charge_types") == *"[Standard]"* ]] ||
  fail "symlinked intent hardware mutation"
grep -Fq 'malformed or has unsafe permissions' "$test_root/symlinked-state.log" ||
  fail "symlinked intent disclosure"
pass "mutations refuse unsafe state files before touching hardware"

reset_fixture
add_battery BAT0 4
exec 8>"$runtime_root/qvos-battery-protection.lock"
flock 8
capture_power "$test_root/concurrent.log" enable plugged-in
((CAPTURE_STATUS != 0)) || fail "concurrent mutation"
grep -Fq 'already running' "$test_root/concurrent.log" ||
  fail "concurrency disclosure"
flock -u 8
exec 8>&-
pass "mutations serialize on one runtime lock"

reset_fixture
add_battery BAT0 4
touch "$fixture/polkit-deny"
capture_power "$test_root/polkit.log" enable plugged-in
((CAPTURE_STATUS != 0)) || fail "UPower authorization denial"
[[ ! -e $state_root/intent ]] || fail "denied UPower intent"
[[ $(<"$sysfs_root/devices/BAT0/charge_types") == *"[Standard]"* ]] ||
  fail "denied UPower kernel state"
pass "UPower denial cannot create managed intent"

reset_fixture
add_battery BAT0 4
touch "$fixture/wrong-readback"
capture_power "$test_root/wrong-readback.log" enable plugged-in
((CAPTURE_STATUS != 0)) || fail "D-Bus success with wrong kernel readback"
[[ ! -e $state_root/intent ]] || fail "wrong-readback intent"
grep -Fq 'did not pass kernel readback' "$test_root/wrong-readback.log" ||
  fail "wrong-readback disclosure"
pass "D-Bus success is insufficient without kernel agreement"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
[[ $(stat -c '%a' "$state_root") == "700" ]] ||
  fail "state directory permissions"
[[ $(stat -c '%a' "$state_root/intent") == "600" ]] ||
  fail "intent permissions"
[[ -z $(find "$state_root" -maxdepth 1 -name '.intent.*' -print -quit) ]] ||
  fail "atomic intent residue"
grep -Fqx '1|enabled|plugged-in|firmware' "$state_root/intent" ||
  fail "managed firmware intent"
pass "managed intent is atomic and private"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
touch "$fixture/pkexec-deny"
run_power disable >/dev/null
grep -Fqx '1|disabled|-|-' "$state_root/intent" ||
  fail "firmware disable intent"
[[ $(<"$sysfs_root/devices/BAT0/charge_types") == *"[Standard]"* ]] ||
  fail "firmware disable Standard state"
pass "firmware-only disable needs no unnecessary root helper"

reset_fixture
add_battery BAT0 3
run_power enable balanced >/dev/null
grep -Fq 'CHARGE_LIMIT=75,80' \
  "$system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb" ||
  fail "balanced hwdb preset"
[[ $(<"$sysfs_root/devices/BAT0/charge_control_start_threshold") == "75" &&
  $(<"$sysfs_root/devices/BAT0/charge_control_end_threshold") == "80" ]] ||
  fail "adjustable kernel readback"
run_power disable >/dev/null
[[ ! -e $system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb ]] ||
  fail "complete disable hwdb cleanup"
grep -Fqx '1|disabled|-|-' "$state_root/intent" ||
  fail "explicit disabled intent"
[[ $(<"$sysfs_root/devices/BAT0/charge_control_start_threshold") == "0" &&
  $(<"$sysfs_root/devices/BAT0/charge_control_end_threshold") == "100" ]] ||
  fail "complete disable unlimited readback"
pass "adjustable enable and complete disable use fixed hwdb ownership"

reset_fixture
add_battery BAT0 2
run_power enable plugged-in >/dev/null
grep -Fq 'CHARGE_LIMIT=_,60' \
  "$system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb" ||
  fail "end-only hwdb preset"
[[ $(<"$sysfs_root/devices/BAT0/charge_control_end_threshold") == "60" ]] ||
  fail "end-only exact threshold"
pass "end-only presets never invent a restart threshold"

reset_fixture
add_battery BAT0 3
install -D -m 0644 /dev/stdin \
  "$system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb" <<'FOREIGN'
# foreign battery manager
FOREIGN
capture_power "$test_root/hwdb-conflict.log" enable balanced
((CAPTURE_STATUS != 0)) || fail "foreign hwdb conflict"
grep -Fq 'foreign or unsafe' "$test_root/hwdb-conflict.log" ||
  fail "foreign hwdb disclosure"
pass "foreign hwdb content is never overwritten"

reset_fixture
add_battery BAT0 3
install -D -m 0644 /dev/stdin \
  "$system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb" <<'EDITED'
# qvOS Battery Protection - managed file
# Generated from fixed qvOS presets; do not edit.
battery:*:*:dmi:*
 CHARGE_LIMIT=75,80
 MALICIOUS_PROPERTY=1
EDITED
capture_power "$test_root/edited-hwdb.log" enable balanced
((CAPTURE_STATUS != 0)) || fail "edited qvOS hwdb content"
grep -Fq 'foreign or unsafe' "$test_root/edited-hwdb.log" ||
  fail "edited qvOS hwdb disclosure"
pass "only an exact fixed qvOS hwdb preset is trusted"

reset_fixture
add_battery BAT0 3
touch "$fixture/hwdb-fail"
capture_power "$test_root/hwdb-fail.log" enable balanced
((CAPTURE_STATUS != 0)) || fail "hwdb reload failure"
[[ ! -e $system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb ]] ||
  fail "hwdb reload rollback"
[[ -d $system_root/run/qvos-battery-protection-hwdb ]] ||
  fail "failed rollback recovery transaction"
[[ $(<"$sysfs_root/devices/BAT0/charge_control_end_threshold") == "100" ]] ||
  fail "hwdb failure safe unlimited fallback"
reset_fixture
add_battery BAT0 3
touch "$fixture/udev-fail"
capture_power "$test_root/udev-fail.log" enable balanced
((CAPTURE_STATUS != 0)) || fail "udev trigger failure"
[[ ! -e $system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb ]] ||
  fail "udev trigger rollback"
[[ -d $system_root/run/qvos-battery-protection-hwdb ]] ||
  fail "failed udev rollback recovery transaction"
pass "hwdb update and udev failures roll back to unlimited charging"

reset_fixture
add_battery BAT0 3
install -D -m 0644 /dev/stdin \
  "$system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb" <<'PREVIOUS'
# qvOS Battery Protection - managed file
# Generated from fixed qvOS presets; do not edit.
battery:*:*:dmi:*
 CHARGE_LIMIT=55,60
PREVIOUS
touch "$fixture/hwdb-fail"
capture_power "$test_root/previous-rollback.log" enable balanced
((CAPTURE_STATUS != 0)) || fail "previous qvOS hwdb rollback failure"
grep -Fq 'CHARGE_LIMIT=55,60' \
  "$system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb" ||
  fail "previous qvOS hwdb restoration"
[[ $(<"$sysfs_root/devices/BAT0/charge_control_end_threshold") == "100" ]] ||
  fail "previous configuration failure safe fallback"
pass "failed reconfiguration restores the previous qvOS-owned hwdb file"

reset_fixture
add_battery BAT0 4
install -D -m 0644 /dev/stdin \
  "$system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb" <<'STALE'
# qvOS Battery Protection - managed file
# Generated from fixed qvOS presets; do not edit.
battery:*:*:dmi:*
 CHARGE_LIMIT=75,80
STALE
[[ $(run_power status) == *"Requested but drifted"* ]] ||
  fail "stale qvOS hwdb drift status"
run_power enable plugged-in >/dev/null
[[ ! -e $system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb ]] ||
  fail "firmware enable stale hwdb cleanup"
pass "firmware-only enable removes a stale qvOS adjustable override"

reset_fixture
add_battery BAT0 3
add_battery BAT1 3
touch "$fixture/partial-write"
capture_power "$test_root/partial.log" enable balanced
((CAPTURE_STATUS != 0)) || fail "partial UPower write"
for battery in BAT0 BAT1; do
  [[ $(<"$sysfs_root/devices/$battery/charge_control_end_threshold") == "100" ]] ||
    fail "partial write fallback for $battery"
done
[[ ! -e $state_root/intent ]] || fail "partial write intent"
pass "partial multi-battery writes fall back to unlimited charging"

reset_fixture
add_battery BAT0 4 true
external=$(run_power status)
[[ $external == *"External or unmanaged enablement"* ]] ||
  fail "external enablement classification"
[[ ! -e $state_root ]] || fail "external state adoption"
printf 'Fast [Standard] Long_Life\n' >"$sysfs_root/devices/BAT0/charge_types"
drift=$(run_power status)
[[ $drift == *"Requested but drifted"* ]] || fail "drift classification"
[[ ! -e $state_root ]] || fail "drift auto-repair"
pass "external state and readback drift are reported without adoption or repair"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
run_power full-charge-once >/dev/null
[[ $(run_power status) == *"Temporary full-charge override"* ]] ||
  fail "temporary override status"
grep -Fq '|firmware|' "$state_root/override" || fail "override recovery state"
[[ $(<"$sysfs_root/devices/BAT0/charge_types") == *"[Standard]"* ]] ||
  fail "temporary full-charge Standard state"
grep -Fq -- '--user enable qvos-battery-full-charge-once.service' "$systemctl_log" ||
  fail "override service enable"
set_property "$fixture/line_power_AC.properties" Online false
QVOS_POWER_SERVICE=1 run_power override-watch
[[ ! -e $state_root/override ]] || fail "AC disconnect override cleanup"
[[ $(<"$sysfs_root/devices/BAT0/charge_types") == *"[Long_Life]"* ]] ||
  fail "AC disconnect restoration"
pass "Full Charge Once restores on AC disconnect and cleans recovery state"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
run_power full-charge-once >/dev/null
touch "$fixture/service-disabled"
[[ $(run_power status) == *"Requested but drifted"* ]] ||
  fail "disabled recovery service drift"
rm "$fixture/service-disabled"
awk -F'|' 'BEGIN{OFS="|"} {$2="balanced"; print}' "$state_root/override" \
  >"$state_root/override.tmp"
mv "$state_root/override.tmp" "$state_root/override"
chmod 0600 "$state_root/override"
[[ $(run_power status) == *"Requested but drifted"* ]] ||
  fail "mismatched recovery state drift"
pass "temporary override status requires intact enabled recovery"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
run_power full-charge-once >/dev/null
awk -F'|' 'BEGIN{OFS="|"} {$4=1; print}' "$state_root/override" \
  >"$state_root/override.tmp"
mv "$state_root/override.tmp" "$state_root/override"
chmod 0600 "$state_root/override"
[[ $(run_power status) == *"Requested but drifted"* ]] ||
  fail "expired recovery deadline drift"
pass "an overdue temporary override is reported as drift"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
run_power full-charge-once >/dev/null
set_property "$fixture/battery_BAT0.properties" State 4
QVOS_POWER_SERVICE=1 run_power override-watch
[[ ! -e $state_root/override ]] || fail "full battery override cleanup"
pass "Full Charge Once restores when every battery is full"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
run_power full-charge-once >/dev/null
awk -F'|' 'BEGIN{OFS="|"} {$4=1; print}' "$state_root/override" \
  >"$state_root/override.tmp"
mv "$state_root/override.tmp" "$state_root/override"
chmod 0600 "$state_root/override"
QVOS_POWER_SERVICE=1 run_power override-watch
[[ ! -e $state_root/override ]] || fail "timeout override cleanup"
pass "Full Charge Once has a 24-hour safety restoration path"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
run_power full-charge-once >/dev/null
set_property "$fixture/line_power_AC.properties" Online false
touch "$fixture/polkit-deny"
export QVOS_POWER_SERVICE=1
capture_power "$test_root/transient.log" override-watch
unset QVOS_POWER_SERVICE
((CAPTURE_STATUS != 0)) || fail "transient restore failure"
[[ -e $state_root/override ]] || fail "transient failure recovery state"
rm "$fixture/polkit-deny"
QVOS_POWER_SERVICE=1 run_power override-watch
[[ ! -e $state_root/override ]] || fail "transient retry cleanup"
pass "transient UPower restoration failures retain state for retry"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
run_power full-charge-once >/dev/null
set_property "$fixture/line_power_AC.properties" Online false
touch "$fixture/conflict-tlp"
export QVOS_POWER_SERVICE=1
capture_power "$test_root/restore-conflict.log" override-watch
unset QVOS_POWER_SERVICE
((CAPTURE_STATUS != 0)) || fail "conflicting manager restoration"
[[ -e $state_root/override ]] || fail "conflict recovery state"
[[ $(<"$sysfs_root/devices/BAT0/charge_types") == *"[Standard]"* ]] ||
  fail "conflict hardware mutation"
grep -Fq 'restoration is waiting while tlp is active' \
  "$test_root/restore-conflict.log" ||
  fail "restoration conflict disclosure"
rm "$fixture/conflict-tlp"
QVOS_POWER_SERVICE=1 run_power override-watch
[[ ! -e $state_root/override ]] || fail "post-conflict retry cleanup"
pass "automatic restoration never fights another charging manager"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
run_power full-charge-once >/dev/null
run_power disable >/dev/null
[[ ! -e $state_root/override ]] || fail "explicit disable override cleanup"
grep -Fqx '1|disabled|-|-' "$state_root/intent" ||
  fail "explicit disable intent after override"
[[ $(<"$sysfs_root/devices/BAT0/charge_types") == *"[Standard]"* ]] ||
  fail "explicit disable Standard state"
pass "explicit Disable cancels Full Charge Once and remains disabled"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
run_power full-charge-once >/dev/null
run_power enable plugged-in >/dev/null
[[ ! -e $state_root/override ]] || fail "explicit enable override cleanup"
[[ $(<"$sysfs_root/devices/BAT0/charge_types") == *"[Long_Life]"* ]] ||
  fail "explicit enable Long_Life restoration"
pass "explicit Enable cancels Full Charge Once only after verified restoration"

reset_fixture
add_battery BAT0 4
set_property "$fixture/line_power_AC.properties" Online false
run_power enable plugged-in >/dev/null
capture_power "$test_root/ac-required.log" full-charge-once
((CAPTURE_STATUS != 0)) || fail "Full Charge Once without AC"
[[ ! -e $state_root/override ]] || fail "offline Full Charge Once state"
pass "Full Charge Once requires online AC power"

reset_fixture
add_battery BAT0 4
run_power enable plugged-in >/dev/null
chmod 0644 "$state_root/intent"
capture_power "$test_root/unsafe-state.log" status
((CAPTURE_STATUS != 0)) || fail "unsafe state permissions"
grep -Fq 'unsafe permissions' "$test_root/unsafe-state.log" ||
  fail "unsafe state disclosure"
pass "unsafe or malformed state is never trusted"

reset_fixture
add_battery BAT0 3
install -d "$system_root/etc/udev/hwdb.d"
ln -s "$test_root/foreign" \
  "$system_root/etc/udev/hwdb.d/61-qvos-battery-protection.hwdb"
capture_power "$test_root/helper-symlink.log" enable balanced
((CAPTURE_STATUS != 0)) || fail "symlinked hwdb path"
pass "the root helper refuses symlinked ownership targets"

grep -Fq 'Environment=QVOS_POWER_SERVICE=1' \
  "$root/qv/power/qvos-battery-full-charge-once.service" ||
  fail "override unit service-only guard"
grep -Fq 'Restart=on-failure' \
  "$root/qv/power/qvos-battery-full-charge-once.service" ||
  fail "override unit retry"
grep -Fq 'WantedBy=default.target' \
  "$root/qv/power/qvos-battery-full-charge-once.service" ||
  fail "override unit reboot recovery"
for hardening in \
  'NoNewPrivileges=yes' \
  'PrivateDevices=yes' \
  'ProtectHome=read-only' \
  'ProtectSystem=strict' \
  'RestrictAddressFamilies=AF_UNIX' \
  'UMask=0077'; do
  grep -Fqx "$hardening" \
    "$root/qv/power/qvos-battery-full-charge-once.service" ||
    fail "override unit hardening: $hardening"
done
if rg -q 'EnableChargeThreshold|charge_control_(start|end)_threshold.*>|>.*charge_control_(start|end)_threshold|conservation_mode.*>' \
  "$root/qv/power/install" \
  "$root/qv/install/desktop" \
  "$root/qv/power/qvos-battery-full-charge-once.service"; then
  fail "install path touches charge control"
fi
pass "fresh install and update wiring keep the override service dormant"
