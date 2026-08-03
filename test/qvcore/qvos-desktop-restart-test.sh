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
install -m 0755 /dev/stdin "$test_bin/pkill" <<'SCRIPT'
#!/bin/bash
printf 'pkill' >>"$QVOS_RESTART_TEST_LOG"
printf '|%s' "$@" >>"$QVOS_RESTART_TEST_LOG"
printf '\n' >>"$QVOS_RESTART_TEST_LOG"
exit "${QVOS_PKILL_STATUS:-1}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit "${QVOS_PGREP_STATUS:-1}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/setsid" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/uwsm-app" <<'SCRIPT'
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
  QVOS_RESTART_TEST_LOG="$log" PATH="$test_bin:/usr/bin" \
    "$root/qvcore/desktop/restart/$1" "${@:2}"
}

"$root/qvcore/desktop/check"
printf 'ok - native restart owners and adapters are singular\n'

if run_owner app; then
  fail "restart app accepted a missing application name"
fi
: >"$log"
run_owner app hypridle --mode 'value with space'
for _ in {1..20}; do
  grep -Fq 'uwsm|--|hypridle|--mode|value with space' "$log" && break
  sleep 0.05
done
grep -Fqx 'pkill|-x|--|hypridle' "$log" || fail "restart app exact termination"
grep -Fqx 'uwsm|--|hypridle|--mode|value with space' "$log" ||
  fail "restart app argument boundaries"
printf 'ok - application restart is bounded and argument-safe\n'

: >"$log"
run_owner btop
run_owner helix
run_owner opencode
run_owner mako
run_owner hyprctl
grep -Fqx 'pkill|-SIGUSR2|-x|--|btop' "$log" || fail "btop signal"
grep -Fqx 'pkill|-USR1|-x|--|helix' "$log" || fail "Helix signal"
grep -Fqx 'pkill|-SIGUSR2|-x|--|opencode' "$log" || fail "OpenCode signal"
grep -Fqx 'makoctl|reload' "$log" || fail "Mako reload"
grep -Fqx 'hyprctl|reload' "$log" || fail "Hyprland reload"
printf 'ok - reload owners tolerate absent optional processes and propagate tools\n'

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
printf 'ok - Walker restart stays in the active user service set\n'

: >"$log"
QVOS_PATH="$root" QVOS_RESTART_TEST_LOG="$log" PATH="$test_bin:/usr/bin" \
  "$root/bin/omarchy-restart-btop"
grep -Fqx 'pkill|-SIGUSR2|-x|--|btop' "$log" || fail "compatibility adapter"
"$root/bin/qv" restart waybar --help | grep -Fq 'qv-restart-waybar' ||
  fail "native restart CLI route"
printf 'ok - restart compatibility and native CLI routes share one owner\n'
