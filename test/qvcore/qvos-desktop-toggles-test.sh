#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
command_log="$test_root/commands.log"
mako_state="$test_root/mako-dnd"
hyprsunset_state="$test_root/hyprsunset-temperature"
idle_pid_file="$test_root/hypridle.pid"
waybar_pid_file="$test_root/waybar.pid"

cleanup() {
  local pid
  local pid_file

  for pid_file in "$idle_pid_file" "$waybar_pid_file"; do
    [[ -f $pid_file ]] || continue
    pid=$(<"$pid_file")
    [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -KILL "$pid" 2>/dev/null || true
  done
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$test_home/.config/waybar" \
  "$test_home/.local/state/qvos/toggles"
: >"$command_log"
printf '6000\n' >"$hyprsunset_state"

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
name=${*: -1}
case $name in
hypridle)
  pid_file=$QVOS_TEST_IDLE_PID_FILE
  ;;
waybar)
  pid_file=$QVOS_TEST_WAYBAR_PID_FILE
  ;;
*) exit 1 ;;
esac
[[ -f $pid_file ]] || exit 1
pid=$(<"$pid_file")
[[ $pid =~ ^[1-9][0-9]*$ ]] || exit 1
kill -0 "$pid" 2>/dev/null || exit 1
printf '%s\n' "$pid"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/setsid" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
if [[ $* == *'list-units'* ]]; then
  exit 0
fi
if [[ $* == *'--property=LoadState'* ]]; then
  if [[ -f $QVOS_TEST_WAYBAR_PID_FILE ]]; then
    printf 'loaded\n'
  else
    printf 'not-found\n'
  fi
  exit 0
fi
if [[ $* == *'is-active'* ]]; then
  [[ -f $QVOS_TEST_WAYBAR_PID_FILE ]] || exit 1
  pid=$(<"$QVOS_TEST_WAYBAR_PID_FILE")
  kill -0 "$pid" 2>/dev/null
  exit
fi
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/uwsm-app" <<'SCRIPT'
#!/bin/bash
printf 'uwsm|%s\n' "$*" >>"$QVOS_TEST_COMMAND_LOG"
while (($# > 0)) && [[ $1 != "--" ]]; do
  shift
done
[[ ${1:-} == "--" ]] || exit 0
shift
app=${1:-}
[[ ${QVOS_TEST_UWSM_FAIL:-} != "$app" ]] || exit 1
case $app in
hypridle)
  pid_file=$QVOS_TEST_IDLE_PID_FILE
  ;;
waybar)
  pid_file=$QVOS_TEST_WAYBAR_PID_FILE
  ;;
*) exit 0 ;;
esac
"$QVOS_TEST_HELPER_BIN/$app" 30 &
printf '%s\n' "$!" >"$pid_file"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
printf 'notify|%s\n' "$*" >>"$QVOS_TEST_COMMAND_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
if [[ $* == "hyprsunset temperature" ]]; then
  cat "$QVOS_TEST_HYPRSUNSET_STATE"
elif [[ $1 == "hyprsunset" && $2 == "temperature" && $# == 3 ]]; then
  printf 'hyprctl|%s\n' "$*" >>"$QVOS_TEST_COMMAND_LOG"
  [[ ${QVOS_TEST_HYPRSUNSET_STUCK:-false} == "true" ]] ||
    printf '%s\n' "$3" >"$QVOS_TEST_HYPRSUNSET_STATE"
else
  printf 'hyprctl|%s\n' "$*" >>"$QVOS_TEST_COMMAND_LOG"
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/makoctl" <<'SCRIPT'
#!/bin/bash
if [[ $* == "mode" ]]; then
  printf 'default\n'
  [[ ! -f $QVOS_TEST_MAKO_STATE ]] || printf 'do-not-disturb\n'
elif [[ $* == "mode -t do-not-disturb" ]]; then
  [[ ${QVOS_TEST_MAKO_STUCK:-false} != "true" ]] || exit 0
  if [[ -f $QVOS_TEST_MAKO_STATE ]]; then
    rm -f -- "$QVOS_TEST_MAKO_STATE"
  else
    : >"$QVOS_TEST_MAKO_STATE"
  fi
else
  exit 2
fi
SCRIPT
cp /usr/bin/sleep "$test_bin/hypridle"
cp /usr/bin/sleep "$test_bin/waybar"

run_owner() {
  HOME="$test_home" \
  QVOS_PATH="$root" \
  QVOS_TEST_COMMAND_LOG="$command_log" \
  QVOS_TEST_HELPER_BIN="$test_bin" \
  QVOS_TEST_IDLE_PID_FILE="$idle_pid_file" \
  QVOS_TEST_HYPRSUNSET_STATE="$hyprsunset_state" \
  QVOS_TEST_HYPRSUNSET_STUCK="${QVOS_TEST_HYPRSUNSET_STUCK:-false}" \
  QVOS_TEST_MAKO_STATE="$mako_state" \
  QVOS_TEST_MAKO_STUCK="${QVOS_TEST_MAKO_STUCK:-false}" \
  QVOS_TEST_UWSM_FAIL="${QVOS_TEST_UWSM_FAIL:-}" \
  QVOS_TEST_WAYBAR_PID_FILE="$waybar_pid_file" \
  PATH="$test_bin:/usr/bin" \
    "$@"
}

run_owner "$root/qvcore/screensaver/toggle"
[[ -f $test_home/.local/state/qvos/toggles/screensaver-off ]] ||
  fail "screensaver toggle did not create its private flag"
run_owner "$root/qvcore/screensaver/toggle"
[[ ! -e $test_home/.local/state/qvos/toggles/screensaver-off ]] ||
  fail "screensaver toggle did not remove its private flag"

run_owner "$root/qvcore/power/toggle-suspend"
[[ -f $test_home/.local/state/qvos/toggles/suspend-off ]] ||
  fail "suspend toggle did not create its private flag"
run_owner "$root/qvcore/power/toggle-suspend"
[[ ! -e $test_home/.local/state/qvos/toggles/suspend-off ]] ||
  fail "suspend toggle did not remove its private flag"
printf 'ok - screensaver and suspend toggles share private native state\n'

run_owner "$root/qvcore/desktop/session/toggle-idle"
for _ in {1..20}; do
  grep -Fqx 'uwsm|-- hypridle' "$command_log" && break
  sleep 0.05
done
grep -Fqx 'uwsm|-- hypridle' "$command_log" ||
  fail "idle toggle did not start Hypridle through UWSM"

idle_pid=$(<"$idle_pid_file")
run_owner "$root/qvcore/desktop/session/toggle-idle"
if kill -0 "$idle_pid" 2>/dev/null; then
  fail "idle toggle did not stop the exact Hypridle fixture"
fi
rm -f -- "$idle_pid_file"
printf 'ok - idle locking toggles through exact process ownership\n'

run_owner "$root/qvcore/desktop/session/toggle-nightlight"
grep -Fqx 'hyprctl|hyprsunset temperature 4000' "$command_log" ||
  fail "Nightlight did not apply its bounded warm temperature"
[[ $(<"$hyprsunset_state") == "4000" ]] ||
  fail "Nightlight did not verify its applied temperature"
if QVOS_TEST_HYPRSUNSET_STUCK=true \
  run_owner "$root/qvcore/desktop/session/toggle-nightlight" >/dev/null 2>&1; then
  fail "Nightlight accepted a temperature that did not apply"
fi
[[ $(<"$hyprsunset_state") == "4000" ]] ||
  fail "failed Nightlight verification did not preserve its prior temperature"
if run_owner "$root/qvcore/desktop/session/toggle-nightlight" unexpected >/dev/null 2>&1; then
  fail "Nightlight accepted unexpected input"
fi
printf 'ok - Nightlight validates and applies one native temperature\n'

run_owner "$root/qvcore/controls/notification/toggle-silencing"
[[ -f $mako_state ]] || fail "notification silencing did not enable DND"
run_owner "$root/qvcore/controls/notification/toggle-silencing"
[[ ! -e $mako_state ]] || fail "notification silencing did not disable DND"
if QVOS_TEST_MAKO_STUCK=true \
  run_owner "$root/qvcore/controls/notification/toggle-silencing" >/dev/null 2>&1; then
  fail "notification silencing accepted an unchanged Mako state"
fi
[[ ! -e $mako_state ]] ||
  fail "failed notification silencing did not preserve its prior state"
printf 'ok - notification silencing verifies the opposite Mako state\n'

run_owner "$root/qvcore/waybar/toggle"
for _ in {1..20}; do
  grep -Fqx 'uwsm|-u qvos-waybar.scope -d qvOS Waybar -S both -- waybar' \
    "$command_log" && break
  sleep 0.05
done
grep -Fqx 'uwsm|-u qvos-waybar.scope -d qvOS Waybar -S both -- waybar' \
  "$command_log" ||
  fail "Waybar toggle did not start through its native restart owner"

waybar_pid=$(<"$waybar_pid_file")
run_owner "$root/qvcore/waybar/toggle"
[[ -f $test_home/.local/state/qvos/toggles/waybar-off ]] ||
  fail "Waybar toggle did not persist hidden state"
if kill -0 "$waybar_pid" 2>/dev/null; then
  fail "Waybar toggle did not stop the exact Waybar fixture"
fi
rm -f -- "$waybar_pid_file"
if QVOS_TEST_UWSM_FAIL=waybar \
  run_owner "$root/qvcore/waybar/toggle" >/dev/null 2>&1; then
  fail "Waybar toggle accepted a failed start"
fi
[[ -f $test_home/.local/state/qvos/toggles/waybar-off ]] ||
  fail "failed Waybar start did not restore hidden startup state"
run_owner "$root/qvcore/waybar/toggle"
[[ ! -e $test_home/.local/state/qvos/toggles/waybar-off ]] ||
  fail "Waybar toggle did not restore visible startup state"
printf 'ok - Waybar visibility is exact and rollback-aware\n'

for route in idle nightlight notification-silencing screensaver suspend waybar; do
  [[ -x $root/bin/qv-toggle-$route && -x $root/bin/omarchy-toggle-$route ]] ||
    fail "toggle adapter mode: $route"
  rg -q '^# qv:summary=' "$root/bin/qv-toggle-$route" ||
    fail "native toggle metadata: $route"
  ! rg -q '^# (qv|omarchy):' "$root/bin/omarchy-toggle-$route" ||
    fail "compatibility toggle duplicated metadata: $route"
done
printf 'ok - desktop toggle routes have native metadata and thin compatibility\n'
