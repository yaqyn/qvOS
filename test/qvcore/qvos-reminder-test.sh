#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
runtime="$test_root/runtime"
test_bin="$test_root/bin"
event_log="$test_root/events"
native_state="$runtime/qvos/reminders"
legacy_state="$runtime/omarchy-reminders"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_home" "$runtime" "$test_bin"
: >"$event_log"
install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
printf 'notify' >>"$QVOS_REMINDER_TEST_LOG"
printf '\t%s' "$@" >>"$QVOS_REMINDER_TEST_LOG"
printf '\n' >>"$QVOS_REMINDER_TEST_LOG"
exit "${QVOS_REMINDER_NOTIFY_STATUS:-0}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
if [[ $* == *'list-units'* ]]; then
  [[ ${QVOS_REMINDER_LIST_STATUS:-0} == "0" ]] || exit "$QVOS_REMINDER_LIST_STATUS"
  printf '%s\n' "${QVOS_REMINDER_TIMERS:-}"
elif [[ $* == *' show '* || ${3:-} == "show" ]]; then
  case ${!#} in
  qvos-*) printf '%s\n' "${QVOS_REMINDER_NATIVE_NEXT:-2min}" ;;
  omarchy-*) printf '%s\n' "${QVOS_REMINDER_LEGACY_NEXT:-3min}" ;;
  *) exit 1 ;;
  esac
elif [[ $* == *' stop '* ]]; then
  printf 'stop' >>"$QVOS_REMINDER_TEST_LOG"
  printf '\t%s' "$@" >>"$QVOS_REMINDER_TEST_LOG"
  printf '\n' >>"$QVOS_REMINDER_TEST_LOG"
  exit "${QVOS_REMINDER_STOP_STATUS:-0}"
else
  exit 2
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/systemd-run" <<'SCRIPT'
#!/bin/bash
printf 'schedule' >>"$QVOS_REMINDER_TEST_LOG"
printf '\t%s' "$@" >>"$QVOS_REMINDER_TEST_LOG"
printf '\n' >>"$QVOS_REMINDER_TEST_LOG"
exit "${QVOS_REMINDER_SCHEDULE_STATUS:-0}"
SCRIPT

run_reminder() {
  HOME="$test_home" \
    XDG_RUNTIME_DIR="$runtime" \
    QVOS_PATH="$root" \
    QVOS_REMINDER_TEST_LOG="$event_log" \
    PATH="$test_bin:/usr/bin" \
    "$root/bin/qv-reminder" "$@"
}

run_reminder 15 "Check the oven" >/dev/null
message_file=$(find "$native_state" -mindepth 1 -maxdepth 1 -type f \
  -name 'qvos-reminder-15m-*.message' -print -quit)
[[ -n $message_file && ! -L $message_file &&
  $(stat -c '%a' "$message_file") == "600" ]] ||
  fail "private native reminder message state"
[[ $(<"$message_file") == "Check the oven" ]] || fail "exact stored message"
schedule=$(grep '^schedule' "$event_log")
[[ $schedule == *$'\t--on-active=15m'* &&
  $schedule == *$'\t--unit=qvos-reminder-15m-'* &&
  $schedule == *$'\t--\t'*"/qvcore/reminder/notify"*$'\t'*"$message_file" &&
  $schedule != *'Check the oven'* ]] ||
  fail "private native reminder scheduling"

QVOS_PATH="$root" XDG_RUNTIME_DIR="$runtime" \
  QVOS_REMINDER_TEST_LOG="$event_log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/reminder/notify" "$message_file"
[[ ! -e $message_file ]] || fail "delivered message state cleanup"
grep -Fq $'notify\t-u\tcritical\t󰔛    Reminder\t      Check the oven' \
  "$event_log" || fail "native notification owner arguments"
printf 'ok - reminders keep text out of unique qvOS unit arguments\n'

: >"$event_log"
native_unit=qvos-reminder-5m-1786191000-1786191000123456789
legacy_unit=omarchy-reminder-30m-1786190000
install -d -m 0700 "$native_state" "$legacy_state"
printf 'Native message' >"$native_state/$native_unit.message"
printf 'Legacy message' >"$legacy_state/$legacy_unit.message"
chmod 0600 "$native_state/$native_unit.message" "$legacy_state/$legacy_unit.message"
QVOS_REMINDER_TIMERS=$'qvos-reminder-5m-1786191000-1786191000123456789.timer loaded active waiting\nomarchy-reminder-30m-1786190000.timer loaded active waiting' \
  SECONDS_SINCE_BOOT=100 run_reminder show
grep -Fq 'Native message in 20s' "$event_log" || fail "native reminder listing"
grep -Fq 'Legacy message in 1m 20s' "$event_log" || fail "legacy reminder listing"

: >"$event_log"
if QVOS_REMINDER_TIMERS=$'qvos-reminder-5m-1786191000-1786191000123456789.timer loaded active waiting\nomarchy-reminder-30m-1786190000.timer loaded active waiting' \
  QVOS_REMINDER_STOP_STATUS=9 run_reminder clear >/dev/null 2>&1; then
  fail "failed timer stop returned success"
fi
[[ -e $native_state/$native_unit.message &&
  -e $legacy_state/$legacy_unit.message ]] ||
  fail "failed timer stop removed retry state"

: >"$event_log"
QVOS_REMINDER_TIMERS=$'qvos-reminder-5m-1786191000-1786191000123456789.timer loaded active waiting\nomarchy-reminder-30m-1786190000.timer loaded active waiting' \
  run_reminder clear
stop_event=$(grep '^stop' "$event_log")
[[ $stop_event == *$'\tqvos-reminder-5m-1786191000-1786191000123456789.timer'* &&
  $stop_event == *$'\tomarchy-reminder-30m-1786190000.timer'* &&
  $stop_event != *'.service'* ]] ||
  fail "validated reminder timer cleanup"
[[ ! -e $native_state/$native_unit.message &&
  ! -e $legacy_state/$legacy_unit.message ]] ||
  fail "native and legacy reminder message cleanup"
printf 'ok - show and clear safely cover native and still-running legacy timers\n'

: >"$event_log"
if QVOS_REMINDER_LIST_STATUS=7 run_reminder show >/dev/null 2>&1; then
  fail "failed timer query was reported as an empty list"
fi
QVOS_REMINDER_SCHEDULE_STATUS=9 run_reminder 10 "Retry safely" >/dev/null 2>&1 &&
  fail "failed scheduler returned success"
if find "$native_state" -type f -name 'qvos-reminder-10m-*.message' -print -quit |
  grep -q .; then
  fail "failed scheduling retained message state"
fi
for invalid in 0 525601 nope; do
  if run_reminder "$invalid" >/dev/null 2>&1; then
    fail "invalid reminder duration accepted: $invalid"
  fi
done
if run_reminder 1 $'line one\nline two' >/dev/null 2>&1; then
  fail "control characters were accepted in a reminder message"
fi
long_message=$(printf 'x%.0s' {1..513})
if run_reminder 1 "$long_message" >/dev/null 2>&1; then
  fail "oversized reminder message was accepted"
fi
printf 'ok - failures and invalid input leave no scheduled or stored residue\n'

unsafe_runtime="$test_root/unsafe-runtime"
runtime_link="$test_root/runtime-link"
ln -s "$unsafe_runtime" "$runtime_link"
if HOME="$test_home" XDG_RUNTIME_DIR="$runtime_link" QVOS_PATH="$root" \
  PATH="$test_bin:/usr/bin" "$root/bin/qv-reminder" show >/dev/null 2>&1; then
  fail "symbolic-link runtime root was accepted"
fi
[[ ! -e $unsafe_runtime ]] || fail "symbolic-link runtime root was followed"

outside="$test_root/outside"
install -d "$outside"
rm -rf -- "$native_state"
ln -s "$outside" "$native_state"
if run_reminder 5 unsafe >/dev/null 2>&1; then
  fail "symbolic-link reminder state was accepted"
fi
[[ -z $(find "$outside" -mindepth 1 -print -quit) ]] ||
  fail "symbolic-link reminder state was followed"

unlink "$native_state"
rmdir "$runtime/qvos"
ln -s "$outside" "$runtime/qvos"
if run_reminder 5 unsafe >/dev/null 2>&1; then
  fail "symbolic-link reminder state parent was accepted"
fi
[[ -z $(find "$outside" -mindepth 1 -print -quit) ]] ||
  fail "symbolic-link reminder state parent was followed"
printf 'ok - reminder state rejects linked and foreign runtime paths\n'

unlink "$runtime/qvos"

HOME="$test_home" XDG_RUNTIME_DIR="$runtime" QVOS_PATH="$root" \
  QVOS_REMINDER_TEST_LOG="$event_log" PATH="$test_bin:/usr/bin" \
  "$root/bin/omarchy-reminder" show >/dev/null
printf 'ok - the Omarchy command is a thin compatibility route\n'
