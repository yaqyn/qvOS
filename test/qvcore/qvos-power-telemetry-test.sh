#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d)
test_bin="$test_root/bin"
upower_log="$test_root/upower.log"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/upower" <<'SCRIPT'
#!/bin/bash
if [[ $1 == "-e" ]]; then
  case ${QVOS_UPOWER_MODE:-normal} in
  no-battery) printf '/org/freedesktop/UPower/devices/line_power_AC\n' ;;
  fallback) printf '/org/freedesktop/UPower/devices/battery_BAT0\n' ;;
  *)
    printf '/org/freedesktop/UPower/devices/battery_BAT0\n'
    printf '/org/freedesktop/UPower/devices/DisplayDevice\n'
    ;;
  esac
  exit
fi
[[ $1 == "-i" && $2 == /org/freedesktop/UPower/devices/* ]] || exit 2
printf '%s\n' "$2" >>"$QVOS_UPOWER_LOG"
if [[ ${QVOS_UPOWER_MODE:-normal} == "malformed" ]]; then
  cat <<'INFO'
  state:               charging
  percentage:          120%
INFO
else
  cat <<'INFO'
  state:               discharging
  energy-rate:         12.04 W
  energy-full:         47.6 Wh
  time to empty:       1.5 hours
  percentage:          57.4%
INFO
fi
SCRIPT

power_root="$test_root/power-supply"
install -d "$power_root/BAT0" "$power_root/USB0" "$power_root/AC"
printf 'Battery\n' >"$power_root/BAT0/type"
printf '1\n' >"$power_root/BAT0/present"
printf 'USB_PD\n' >"$power_root/USB0/type"
printf '1\n' >"$power_root/USB0/online"
printf 'Mains\n' >"$power_root/AC/type"
printf '0\n' >"$power_root/AC/online"

QVOS_POWER_TESTING=1 QVOS_POWER_SUPPLY_ROOT="$power_root" \
  "$root/qvcore/power/supply-status" battery
QVOS_POWER_TESTING=1 QVOS_POWER_SUPPLY_ROOT="$power_root" \
  "$root/qvcore/power/supply-status" ac
printf '0\n' >"$power_root/USB0/online"
if QVOS_POWER_TESTING=1 QVOS_POWER_SUPPLY_ROOT="$power_root" \
  "$root/qvcore/power/supply-status" ac; then
  fail "offline external supplies were reported online"
fi
printf 'invalid\n' >"$power_root/BAT0/present"
if QVOS_POWER_TESTING=1 QVOS_POWER_SUPPLY_ROOT="$power_root" \
  "$root/qvcore/power/supply-status" battery; then
  fail "invalid battery presence was accepted"
fi
printf '1\n' >"$power_root/BAT0/present"
printf 'ok - power-supply detection covers USB-C and validates presence state\n'

legacy_home="$test_root/legacy-home"
legacy_bin="$legacy_home/.local/lib/qvos/bin"
install -d "$legacy_bin"
sed 's/Usage: qv system/Usage: omarchy system/g' \
  "$root/qvcore/power/inhibit-sleep" \
  >"$legacy_bin/omarchy-system-inhibit-sleep"
sed \
  -e 's/Usage: qv system/Usage: omarchy system/g' \
  -e 's/qv-toggle-enabled/omarchy-toggle-enabled/g' \
  "$root/qvcore/power/suspend-if-safe" \
  >"$legacy_bin/omarchy-system-suspend-if-safe"
chmod 0755 "$legacy_bin"/omarchy-system-*
[[ $(sha256sum "$legacy_bin/omarchy-system-inhibit-sleep" | cut -d ' ' -f 1) == \
  "3a6afde2549cd64888507c5d5ad534e368b29711a9cde1d916199d3c137715b5" ]] ||
  fail "legacy inhibit owner fixture"
[[ $(sha256sum "$legacy_bin/omarchy-system-suspend-if-safe" | cut -d ' ' -f 1) == \
  "2e11eb00125215d89cfd545af7d3974e45b6e70bc9e27d9806e145bf26b16e88" ]] ||
  fail "legacy suspend owner fixture"
HOME="$legacy_home" \
QVOS_PATH="$root" \
OMARCHY_PATH="$test_root/stale-source" \
QVOS_POWER_TESTING=1 \
QVOS_POWER_SYSTEM_ROOT="$test_root/legacy-system" \
  "$root/qvcore/power/install"
for command_name in \
  omarchy-system-inhibit-sleep \
  omarchy-system-suspend-if-safe \
  qv-system-inhibit-sleep \
  qv-system-suspend-if-safe; do
  [[ -L $legacy_bin/$command_name ]] ||
    fail "legacy sleep owner conversion: $command_name"
done

modified_home="$test_root/modified-home"
modified_command="$modified_home/.local/lib/qvos/bin/qv-system-inhibit-sleep"
install -D -m 0755 /dev/stdin "$modified_command" <<'SCRIPT'
#!/bin/bash
echo "user-owned sleep wrapper"
SCRIPT
if HOME="$modified_home" \
  QVOS_PATH="$root" \
  OMARCHY_PATH="$test_root/stale-source" \
  QVOS_POWER_TESTING=1 \
  QVOS_POWER_SYSTEM_ROOT="$test_root/modified-system" \
  "$root/qvcore/power/install" >/dev/null 2>&1; then
  fail "modified sleep owner was replaced"
fi
grep -Fq 'user-owned sleep wrapper' "$modified_command" ||
  fail "modified sleep owner was not preserved"
printf 'ok - sleep runtime migration converts exact owners and preserves modifications\n'

run_info() {
  QVOS_UPOWER_LOG="$upower_log" \
  QVOS_UPOWER_MODE="${QVOS_UPOWER_MODE:-normal}" \
  PATH="$test_bin:/usr/bin" \
    "$root/qvcore/power/battery-info" "$@"
}

: >"$upower_log"
[[ $(run_info capacity) == "48" ]] || fail "rounded battery capacity"
[[ $(run_info remaining) == "57" ]] || fail "battery percentage"
[[ $(run_info remaining-time) == "1h 30m" ]] || fail "battery time remaining"
[[ $(run_info sample) == $'57\tdischarging' ]] || fail "battery monitor sample"
status=$(run_info status)
[[ $status == *"Battery 57%"* && $status == *"1h 30m left"* &&
  $status == *" 12W / 48Wh"* ]] || fail "battery status presentation"
[[ $(wc -l <"$upower_log") == "5" ]] || fail "one UPower query per telemetry request"

runtime_dir="$test_root/runtime"
install -d "$runtime_dir"
install -m 0600 /dev/null "$runtime_dir/qvos-battery-notified"
before_monitor_queries=$(wc -l <"$upower_log")
QVOS_UPOWER_LOG="$upower_log" \
PATH="$test_bin:/usr/bin" \
XDG_RUNTIME_DIR="$runtime_dir" \
  "$root/qvcore/config/battery-monitor"
[[ ! -e $runtime_dir/qvos-battery-notified ]] ||
  fail "recovered battery notification state"
[[ $(wc -l <"$upower_log") == "$((before_monitor_queries + 1))" ]] ||
  fail "battery monitor repeated its UPower query"
printf 'ok - low-battery monitoring reuses one aggregate telemetry sample\n'

QVOS_UPOWER_MODE=fallback run_info remaining >/dev/null
if QVOS_UPOWER_MODE=malformed run_info remaining >/dev/null 2>&1; then
  fail "malformed UPower percentage was accepted"
fi
if QVOS_UPOWER_MODE=no-battery run_info status >/dev/null 2>&1; then
  fail "missing UPower battery was accepted"
fi
printf 'ok - aggregate UPower telemetry is bounded, compact, and query-efficient\n'

"$root/qvcore/power/check"
QVOS_PATH="$root" QVOS_POWER_TESTING=1 QVOS_POWER_SUPPLY_ROOT="$power_root" \
  "$root/bin/omarchy-battery-present" || fail "battery compatibility adapter"
"$root/bin/qv" battery status --help | grep -F 'qv-battery-status' >/dev/null ||
  fail "native battery CLI route"
"$root/bin/qv" system inhibit sleep --help | grep -F 'qv-system-inhibit-sleep' >/dev/null ||
  fail "native sleep-inhibit CLI route"
printf 'ok - native power CLI and exact compatibility routes share one owner\n'
