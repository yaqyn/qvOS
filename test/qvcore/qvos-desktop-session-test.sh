#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
source_root="$test_root/source"
test_bin="$test_root/bin"
hyprctl_log="$test_root/hyprctl.log"
session_log="$test_root/session.log"
controls_log="$test_root/controls.log"
hyprlock_pid_file="$test_root/hyprlock.pid"
lock_pid=""

cleanup() {
  [[ -z $lock_pid ]] || kill "$lock_pid" 2>/dev/null || true
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
clients)
  printf '%s\n' "${QVOS_TEST_CLIENTS_JSON:-[]}"
  ;;
dispatch)
  printf 'dispatch' >>"$QVOS_TEST_HYPRCTL_LOG"
  printf '|%s' "${@:2}" >>"$QVOS_TEST_HYPRCTL_LOG"
  printf '\n' >>"$QVOS_TEST_HYPRCTL_LOG"
  ;;
switchxkblayout)
  printf 'layout|%s\n' "${*:2}" >>"$QVOS_TEST_HYPRCTL_LOG"
  ;;
*) exit 1 ;;
esac
SCRIPT

run_hyprland_owner() {
  QVOS_TEST_HYPRCTL_LOG="$hyprctl_log" \
    QVOS_TEST_CLIENTS_JSON="$1" \
    PATH="$test_bin:/usr/bin" \
    "$root/qvcore/desktop/hyprland/window-close-all" "${@:2}"
}

: >"$hyprctl_log"
run_hyprland_owner '[{"address":"0x1"},{"address":"0xAbC"}]'
[[ $(<"$hyprctl_log") == $'dispatch|hl.dsp.window.close({ window = "address:0x1" })\ndispatch|hl.dsp.window.close({ window = "address:0xAbC" })\ndispatch|hl.dsp.focus({ workspace = "1" })' ]] ||
  fail "validated all-window close order"

: >"$hyprctl_log"
if run_hyprland_owner '[{"address":"0x1"},{"address":"unsafe"}]' \
  >/dev/null 2>&1; then
  fail "invalid Hyprland window inventory accepted"
fi
[[ ! -s $hyprctl_log ]] || fail "partial close before complete validation"
if run_hyprland_owner '[]' unexpected >/dev/null 2>&1; then
  fail "all-window owner accepted unexpected arguments"
fi
printf 'ok - all-window closure validates the full client inventory before mutation\n'

: >"$hyprctl_log"
QVOS_TEST_HYPRCTL_LOG="$hyprctl_log" \
  QVOS_TEST_CLIENTS_JSON='[{"class":"org.qvos.screensaver","address":"0x2"},{"class":"app","address":"unrelated"}]' \
  QVOS_PATH="$root" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/screensaver/close"
[[ $(<"$hyprctl_log") == 'dispatch|hl.dsp.window.close({ window = "address:0x2" })' ]] ||
  fail "bounded screensaver close"

: >"$hyprctl_log"
if QVOS_TEST_HYPRCTL_LOG="$hyprctl_log" \
  QVOS_TEST_CLIENTS_JSON='[{"class":"org.qvos.screensaver","address":"0x2"},{"class":"org.qvos.screensaver","address":"unsafe"}]' \
  QVOS_PATH="$root" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/screensaver/close" >/dev/null 2>&1; then
  fail "invalid screensaver window inventory accepted"
fi
[[ ! -s $hyprctl_log ]] || fail "partial screensaver close before validation"
printf 'ok - screensaver closure is class-bounded and atomic before dispatch\n'

for owner in lock logout logout-worker wake; do
  install -D -m 0755 "$root/qvcore/desktop/session/$owner" \
    "$source_root/qvcore/desktop/session/$owner"
done
install -D -m 0755 "$root/qvcore/desktop/hyprland/window-close-all" \
  "$source_root/qvcore/desktop/hyprland/window-close-all"
install -D -m 0755 "$root/qvcore/desktop/hyprland/qvos-runtime-config" \
  "$source_root/qvcore/desktop/hyprland/qvos-runtime-config"
install -D -m 0644 "$root/qvcore/desktop/restart/process-lib" \
  "$source_root/qvcore/desktop/restart/process-lib"
install -D -m 0755 /dev/stdin \
  "$source_root/qvcore/screensaver/close" <<'SCRIPT'
#!/bin/bash
printf 'screensaver-close\n' >>"$QVOS_TEST_SESSION_LOG"
SCRIPT
for control in display keyboard; do
  install -D -m 0755 /dev/stdin \
    "$source_root/qvcore/controls/brightness/$control" <<'SCRIPT'
#!/bin/bash
printf '%s:%s\n' "${0##*/}" "$*" >>"$QVOS_TEST_CONTROLS_LOG"
SCRIPT
done
install -m 0755 /dev/stdin "$test_bin/hyprlock" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$$" >"$QVOS_TEST_HYPRLOCK_PID_FILE"
trap 'rm -f -- "$QVOS_TEST_HYPRLOCK_PID_FILE"' EXIT
printf 'hyprlock\n' >>"$QVOS_TEST_SESSION_LOG"
if [[ ${QVOS_TEST_HYPRLOCK_STATUS:-0} != "0" ]]; then
  exit "$QVOS_TEST_HYPRLOCK_STATUS"
fi
/usr/bin/sleep 1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

name=${!#}
[[ $name == "hyprlock" && -r $QVOS_TEST_HYPRLOCK_PID_FILE ]] || exit 1
pid=$(<"$QVOS_TEST_HYPRLOCK_PID_FILE")
[[ $pid =~ ^[1-9][0-9]*$ && -r /proc/$pid/comm ]] || exit 1
printf '%s\n' "$pid"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sleep" <<'SCRIPT'
#!/bin/bash
if [[ ${1:-} == "0.05" ]]; then
  exec /usr/bin/sleep "$@"
fi
printf 'sleep:%s\n' "$*" >>"$QVOS_TEST_SESSION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/nohup" <<'SCRIPT'
#!/bin/bash
printf 'nohup:%s\n' "$*" >>"$QVOS_TEST_SESSION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/uwsm" <<'SCRIPT'
#!/bin/bash
printf 'uwsm:%s\n' "$*" >>"$QVOS_TEST_SESSION_LOG"
SCRIPT

run_session_owner() {
  QVOS_TEST_HYPRCTL_LOG="$hyprctl_log" \
    QVOS_TEST_SESSION_LOG="$session_log" \
    QVOS_TEST_CONTROLS_LOG="$controls_log" \
    QVOS_TEST_HYPRLOCK_PID_FILE="$hyprlock_pid_file" \
    QVOS_TEST_CLIENTS_JSON='[]' \
    PATH="$test_bin:/usr/bin" \
    "$source_root/qvcore/desktop/session/$1" "${@:2}"
}

: >"$controls_log"
run_session_owner wake
[[ $(<"$controls_log") == $'display:on\nkeyboard:restore' ]] ||
  fail "wake control order"
printf 'ok - wake delegates once to each native brightness owner\n'

: >"$session_log"
: >"$controls_log"
: >"$hyprctl_log"
QVOS_LOCK_ONLY=true run_session_owner lock
for ((attempt = 0; attempt < 200; attempt++)); do
  grep -Fqx 'keyboard:restore' "$controls_log" 2>/dev/null && break
  /usr/bin/sleep 0.01
done
grep -Fqx 'hyprlock' "$session_log" || fail "Hyprlock launch"
grep -Fqx 'screensaver-close' "$session_log" || fail "shared screensaver close"
grep -Fqx 'layout|all 0' "$hyprctl_log" || fail "default keyboard layout"
[[ $(<"$controls_log") == $'display:on\nkeyboard:restore' ]] ||
  fail "lock-only policy scheduled display dimming"
printf 'ok - lock starts Hyprlock once, closes the screensaver, and wakes cleanly\n'

: >"$session_log"
: >"$controls_log"
if QVOS_TEST_HYPRLOCK_STATUS=1 QVOS_LOCK_ONLY=true \
  run_session_owner lock >/dev/null 2>&1; then
  fail "failed Hyprlock launch was reported as successful"
fi
for ((attempt = 0; attempt < 100; attempt++)); do
  grep -Fqx 'keyboard:restore' "$controls_log" 2>/dev/null && break
  /usr/bin/sleep 0.01
done
grep -Fqx 'display:on' "$controls_log" || fail "failed-lock display recovery"
grep -Fqx 'keyboard:restore' "$controls_log" || fail "failed-lock keyboard recovery"
if grep -Fqx 'screensaver-close' "$session_log"; then
  fail "failed lock dismissed the current screensaver"
fi
printf 'ok - failed Hyprlock launch preserves the screensaver and reports failure\n'

cp /usr/bin/sleep "$test_bin/hyprlock"
"$test_bin/hyprlock" 30 &
lock_pid=$!
printf '%s\n' "$lock_pid" >"$hyprlock_pid_file"
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ $(</proc/$lock_pid/comm) == "hyprlock" ]] && break
  /usr/bin/sleep 0.01
done
: >"$controls_log"
run_session_owner lock
for ((attempt = 0; attempt < 100; attempt++)); do
  grep -Fqx 'display:off' "$controls_log" 2>/dev/null && break
  /usr/bin/sleep 0.01
done
[[ $(<"$controls_log") == $'keyboard:off\ndisplay:off' ]] ||
  fail "active-lock dim order"
kill "$lock_pid"
wait "$lock_pid" 2>/dev/null || true
lock_pid=""
rm -f -- "$hyprlock_pid_file"
printf 'ok - display dimming runs only while an exact Hyprlock process remains\n'

if QVOS_LOCK_ONLY=invalid run_session_owner lock >/dev/null 2>&1; then
  fail "invalid lock-only policy accepted"
fi
if run_session_owner wake unexpected >/dev/null 2>&1; then
  fail "wake accepted unexpected arguments"
fi
printf 'ok - session owners reject malformed input before mutation\n'

: >"$session_log"
: >"$hyprctl_log"
run_session_owner logout
grep -Fq "nohup:$source_root/qvcore/desktop/session/logout-worker" \
  "$session_log" || fail "fixed logout worker scheduling"
grep -Fqx 'sleep:1' "$session_log" || fail "application shutdown grace"
grep -Fqx 'dispatch|hl.dsp.focus({ workspace = "1" })' "$hyprctl_log" ||
  fail "logout window cleanup"
: >"$session_log"
run_session_owner logout-worker
[[ $(<"$session_log") == $'sleep:2\nuwsm:stop' ]] ||
  fail "fixed delayed logout worker"
printf 'ok - logout schedules one fixed worker and closes windows through its owner\n'

"$root/qvcore/desktop/check"
"$root/bin/qv" system lock --help | grep -F 'qv-system-lock' >/dev/null ||
  fail "native lock CLI route"
"$root/bin/qv" logout --help | grep -F 'qv-system-logout' >/dev/null ||
  fail "native logout CLI alias"
printf 'ok - native and compatibility session routes have one implementation owner\n'
