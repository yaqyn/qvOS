#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
log="$test_root/commands.log"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -D -m 0755 /dev/null \
  "$test_root/.local/lib/qvos/waybar/session"
install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit "${QVOS_PGREP_STATUS:-1}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/setsid" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-launch-app" <<'SCRIPT'
#!/bin/bash
printf 'uwsm' >>"$QVOS_RESTART_TEST_LOG"
printf '|%s' "$@" >>"$QVOS_RESTART_TEST_LOG"
printf '\n' >>"$QVOS_RESTART_TEST_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl' >>"$QVOS_RESTART_TEST_LOG"
printf '|%s' "$@" >>"$QVOS_RESTART_TEST_LOG"
printf '\n' >>"$QVOS_RESTART_TEST_LOG"
if [[ $* == *'--property=Description'* ]]; then
  printf 'qvOS unit\n'
  exit 0
fi
if [[ $* == *'--property=LoadState'* ]]; then
  if [[ $* == *'qvos-waybar.scope'* || $* == *'qvos-monitor-watch.service'* ]]; then
    printf 'not-found\n'
  else
    printf 'loaded\n'
  fi
  exit 0
fi
if [[ $* == *'is-active pipewire-pulse.service'* ]]; then
  exit 0
fi
if [[ $* == *'is-enabled elephant.service'* ]]; then
  exit 1
fi
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
if [[ ${QVOS_FAIL_FIRST_BIND:-false} == "true" && $1 == "tee" && $2 == */bind && ! -e ${QVOS_BIND_FAILED_MARKER:-} ]]; then
  touch "$QVOS_BIND_FAILED_MARKER"
  cat >/dev/null
  exit 1
fi
exec "$@"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/makoctl" <<'SCRIPT'
#!/bin/bash
printf 'makoctl|%s\n' "$*" >>"$QVOS_RESTART_TEST_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf 'hyprctl|%s\n' "$*" >>"$QVOS_RESTART_TEST_LOG"
SCRIPT

run_owner() {
  HOME="$test_root" QVOS_RESTART_TEST_LOG="$log" PATH="$test_bin:/usr/bin" \
    "$root/qvcore/desktop/restart/$1" "${@:2}"
}

"$root/qvcore/desktop/check"
printf 'ok - native restart owners and adapters are singular\n'

bash -s "$root/qvcore/desktop/restart/process-lib" <<'SCRIPT'
set -euo pipefail
source "$1"
sleep 30 &
target_pid=$!
cleanup_process() {
  kill -KILL "$target_pid" 2>/dev/null || true
}
trap cleanup_process EXIT
pgrep() {
  printf '%s\n%s\n' "$$" "$target_pid"
}
mapfile -t matched_pids < <(qvos_process_exact_pids sleep)
((${#matched_pids[@]} == 1))
[[ ${matched_pids[0]} == "$target_pid" ]]
qvos_process_signal_exact sleep TERM
set +e
wait "$target_pid"
target_status=$?
set -e
((target_status == 143))
trap - EXIT
SCRIPT
printf 'ok - exact process signaling excludes its own owner and validates targets\n'

if run_owner app; then
  fail "restart app accepted a missing application name"
fi
: >"$log"
run_owner app hypridle --mode 'value with space'
for _ in {1..20}; do
  grep -Fq 'uwsm|--|hypridle|--mode|value with space' "$log" && break
  sleep 0.05
done
grep -Fqx 'uwsm|--|hypridle|--mode|value with space' "$log" ||
  fail "restart app argument boundaries"
printf 'ok - application restart is bounded and argument-safe\n'

: >"$log"
run_owner btop
run_owner helix
run_owner mako
run_owner hyprctl
grep -Fqx 'makoctl|reload' "$log" || fail "Mako reload"
grep -Fqx 'hyprctl|reload' "$log" || fail "Hyprland reload"
printf 'ok - reload owners tolerate absent optional processes and propagate tools\n'

: >"$log"
run_owner waybar
for _ in {1..20}; do
  grep -Fq "uwsm|--|$test_root/.local/lib/qvos/waybar/session" "$log" && break
  sleep 0.05
done
grep -Fqx "uwsm|-u|qvos-waybar.scope|-d|qvOS Waybar|-S|both|--|$test_root/.local/lib/qvos/waybar/session" "$log" ||
  fail "Waybar relaunch"
printf 'ok - Waybar restart survives its matching owner basename\n'

: >"$log"
run_owner monitor-watch
for _ in {1..20}; do
  grep -Fq 'uwsm|-t|service|-u|qvos-monitor-watch.service' "$log" && break
  sleep 0.05
done
grep -Fqx 'uwsm|-t|service|-u|qvos-monitor-watch.service|-d|qvOS monitor watcher|-p|Restart=on-failure|-S|both|--|qv-hyprland-monitor-watch' "$log" ||
  fail "native monitor-watch relaunch"
printf 'ok - monitor watching uses one restartable qvOS service\n'

if rg -n 'list-units|app-\*-|legacy_patterns|legacy_pattern' \
  "$root/qvcore/desktop/restart/waybar" \
  "$root/qvcore/desktop/restart/monitor-watch" \
  "$root/qvcore/desktop/restart/user-unit-lib"; then
  fail "desktop restarts retain inherited transient-unit discovery"
fi

: >"$log"
run_owner pipewire
grep -Fqx 'systemctl|--user|restart|wireplumber.service|pipewire.service' "$log" ||
  fail "PipeWire base services"
grep -Fqx 'systemctl|--user|restart|pipewire-pulse.service' "$log" ||
  fail "active PipeWire Pulse service"
printf 'ok - audio restart covers the active service set\n'

driver_root="$test_root/i2c_hid_acpi"
module_root="$test_root/modules"
install -d "$driver_root" "$module_root"
: >"$driver_root/i2c-test"
: >"$driver_root/unbind"
: >"$driver_root/bind"
QVOS_RESTART_TEST_LOG="$log" \
QVOS_I2C_HID_DRIVER_ROOT="$driver_root" \
QVOS_MODULE_ROOT="$module_root" \
PATH="$test_bin:/usr/bin" \
  "$root/qvcore/desktop/restart/trackpad"
grep -Fqx 'i2c-test' "$driver_root/unbind" || fail "trackpad unbind"
grep -Fqx 'i2c-test' "$driver_root/bind" || fail "trackpad bind"

: >"$driver_root/bind"
failed_marker="$test_root/bind-failed"
if QVOS_RESTART_TEST_LOG="$log" \
  QVOS_I2C_HID_DRIVER_ROOT="$driver_root" \
  QVOS_MODULE_ROOT="$module_root" \
  QVOS_FAIL_FIRST_BIND=true \
  QVOS_BIND_FAILED_MARKER="$failed_marker" \
  PATH="$test_bin:/usr/bin" \
    "$root/qvcore/desktop/restart/trackpad"; then
  fail "trackpad reset hid a failed bind"
fi
grep -Fqx 'i2c-test' "$driver_root/bind" || fail "failed trackpad reset restoration"
printf 'ok - trackpad reset restores an unbound device after failure\n'

: >"$log"
run_owner walker
grep -Fqx 'systemctl|--user|restart|app-walker@autostart.service' "$log" ||
  fail "Walker service restart"
if grep -Fq 'restart|elephant.service' "$log"; then
  fail "disabled Elephant service was restarted"
fi
if rg -n 'systemd-run|bash[[:space:]]+-c|declare[[:space:]]+-f' \
  "$root/qvcore/desktop/restart/walker"; then
  fail "Walker restart retained a root-to-user shell bridge"
fi
grep -Fq 'Walker must be restarted from the active desktop user session.' \
  "$root/qvcore/desktop/restart/walker" ||
  fail "Walker restart lacks a root refusal"
printf 'ok - Walker restart stays in the active user service set\n'

: >"$log"
QVOS_PATH="$root" QVOS_RESTART_TEST_LOG="$log" PATH="$test_bin:/usr/bin" \
  "$root/bin/omarchy-restart-btop"
"$root/bin/qv" restart waybar --help | grep -F 'qv-restart-waybar' >/dev/null ||
  fail "native restart CLI route"
printf 'ok - restart compatibility and native CLI routes share one owner\n'
