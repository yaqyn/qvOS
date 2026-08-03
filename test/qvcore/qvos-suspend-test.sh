#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
guard="$root/bin/qv-system-suspend-if-safe"
inhibitor="$root/bin/qv-system-inhibit-sleep"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
command_log="$test_root/commands"

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

install -d "$test_bin" "$test_root/runtime"

install -m 0755 /dev/stdin "$test_bin/pidof" <<'SCRIPT'
#!/bin/bash
[[ $1 == "hyprlock" ]] || exit 1

if [[ -n ${QVOS_TEST_LOCK_SEQUENCE:-} && -s $QVOS_TEST_LOCK_SEQUENCE ]]; then
  lock_pid="$(head -n 1 "$QVOS_TEST_LOCK_SEQUENCE")"
  sed -i '1d' "$QVOS_TEST_LOCK_SEQUENCE"
  [[ $lock_pid =~ ^[0-9]+$ ]] || exit 1
  printf '%s\n' "$lock_pid"
elif [[ ${QVOS_TEST_LOCKED:-0} == "1" ]]; then
  printf '111\n'
else
  exit 1
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/ps" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_LOCK_AGE:-1800}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qv-toggle-enabled" <<'SCRIPT'
#!/bin/bash
[[ $1 == "suspend-off" && ${QVOS_TEST_SUSPEND_OFF:-0} == "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
if [[ ${QVOS_TEST_CODEX:-0} == "1" && $* == *codex* ]]; then
  exit 0
fi
if [[ ${QVOS_TEST_GAME:-0} == "1" ]] &&
  { [[ $* == *gamescope* ]] || [[ $* == *steamapps* ]] || [[ $* == *gamemoderun* ]]; }; then
  exit 0
fi
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
[[ $1 == "clients" && $2 == "-j" ]] || exit 1
printf '%s\n' "${QVOS_TEST_CLIENTS:-[]}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemd-inhibit" <<'SCRIPT'
#!/bin/bash
if [[ ${1:-} == "--list" ]]; then
  printf '%s\n' "${QVOS_TEST_INHIBITORS:-[]}"
  exit 0
fi

printf 'systemd-inhibit' >>"$QVOS_TEST_COMMAND_LOG"
printf ' %q' "$@" >>"$QVOS_TEST_COMMAND_LOG"
printf '\n' >>"$QVOS_TEST_COMMAND_LOG"
while (($#)); do
  if [[ $1 == "--" ]]; then
    shift
    exec "$@"
  fi
  shift
done
exit 2
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$QVOS_TEST_COMMAND_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sleep" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qv-restart-hypridle" <<'SCRIPT'
#!/bin/bash
printf 'restart-hypridle\n' >>"$QVOS_TEST_COMMAND_LOG"
SCRIPT

run_guard() {
  QVOS_TEST_COMMAND_LOG="$command_log" \
    QVOS_TEST_LOCKED="${QVOS_TEST_LOCKED:-1}" \
    QVOS_TEST_LOCK_AGE="${QVOS_TEST_LOCK_AGE:-1800}" \
    QVOS_TEST_LOCK_SEQUENCE="${QVOS_TEST_LOCK_SEQUENCE:-}" \
    QVOS_TEST_SUSPEND_OFF="${QVOS_TEST_SUSPEND_OFF:-0}" \
    QVOS_TEST_CODEX="${QVOS_TEST_CODEX:-0}" \
    QVOS_TEST_GAME="${QVOS_TEST_GAME:-0}" \
    QVOS_TEST_CLIENTS="${QVOS_TEST_CLIENTS:-[]}" \
    QVOS_TEST_INHIBITORS="${QVOS_TEST_INHIBITORS:-[]}" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    HOME="$test_root" \
    OMARCHY_PATH="$root" \
    PATH="$test_bin:/usr/bin" \
    "$guard" "$@"
}

run_guard --check | grep -Fq 'Automatic suspend is ready.' ||
  fail "safe suspend check"
pass "a locked idle session is eligible for suspend"

if QVOS_TEST_LOCKED=0 run_guard --check >/dev/null; then
  fail "unlocked session accepted"
fi
if QVOS_TEST_SUSPEND_OFF=1 run_guard --check >/dev/null; then
  fail "disabled suspend accepted"
fi
if QVOS_TEST_LOCK_AGE=1799 run_guard --check >/dev/null; then
  fail "short lock accepted"
fi
pass "unlock, short locks, and the existing suspend toggle block automatic suspend"

block_inhibitor='[{"who":"Build","what":"sleep","why":"Compilation is active","mode":"block"}]'
if QVOS_TEST_INHIBITORS="$block_inhibitor" run_guard --check >/dev/null; then
  fail "blocking inhibitor accepted"
fi
delay_inhibitor='[{"who":"hypridle","what":"sleep","why":"Lock before sleep","mode":"delay"}]'
QVOS_TEST_INHIBITORS="$delay_inhibitor" run_guard --check >/dev/null ||
  fail "delay inhibitor blocked suspend"
pass "system sleep inhibitors are honored without rejecting normal delay hooks"

if QVOS_TEST_CODEX=1 run_guard --check >/dev/null; then
  fail "active Codex accepted"
fi
fullscreen='[{"mapped":true,"fullscreen":2}]'
if QVOS_TEST_CLIENTS="$fullscreen" run_guard --check >/dev/null; then
  fail "fullscreen client accepted"
fi
if QVOS_TEST_GAME=1 run_guard --check >/dev/null; then
  fail "active game accepted"
fi
pass "Codex, fullscreen applications, and games block automatic suspend"

lock_sequence="$test_root/lock-sequence"
printf '%s\n' 111 111 222 stopped >"$lock_sequence"
: >"$command_log"
QVOS_TEST_LOCK_SEQUENCE="$lock_sequence" run_guard --watch >/dev/null
if grep -Fq 'systemctl suspend' "$command_log"; then
  fail "changed lock session suspended"
fi
pass "the retry watcher stops across unlock and relock"

: >"$command_log"
run_guard >/dev/null
grep -Fqx 'systemctl suspend' "$command_log" ||
  fail "safe suspend execution"
pass "an eligible session requests suspend"

: >"$command_log"
QVOS_TEST_COMMAND_LOG="$command_log" \
  QVOS_SLEEP_INHIBIT_REASON="Codex session is active" \
  OMARCHY_PATH="$root" \
  PATH="$test_bin:/usr/bin" \
  "$inhibitor" -- printf 'protected\n' >/dev/null
grep -Fq -- '--why=Codex\ session\ is\ active' "$command_log" ||
  fail "sleep inhibitor reason"
grep -Fq -- '--mode=block-weak' "$command_log" ||
  fail "sleep inhibitor override mode"
pass "development commands block automatic sleep while allowing deliberate suspend"
