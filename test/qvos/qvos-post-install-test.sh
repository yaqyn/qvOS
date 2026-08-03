#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_omarchy="$test_root/omarchy"
test_install="$test_omarchy/install"
test_bin="$test_root/bin"
event_log="$test_root/events"
completion_marker="$test_root/install-completed"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$test_install/post-install" \
  "$test_omarchy/qv/branding" \
  "$test_omarchy/qv/install/post-install" \
  "$test_omarchy/qv/security"
install -m 0755 \
  "$root/qv/install/post-install/finished" \
  "$test_omarchy/qv/install/post-install/finished"
install -m 0644 \
  "$root/qv/branding/logo.txt" \
  "$test_omarchy/qv/branding/logo.txt"
: >"$event_log"

install -m 0644 /dev/stdin \
  "$test_install/post-install/allow-reboot.sh" <<'SCRIPT'
printf 'allow-reboot\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

run_logged() {
  printf 'run:%s\n' "$1" >>"$QVOS_TEST_EVENT_LOG"
}
stop_install_log() {
  printf 'stop-log\n' >>"$QVOS_TEST_EVENT_LOG"
}
export -f run_logged stop_install_log

install -m 0755 /dev/stdin \
  "$test_omarchy/qv/install/post-install/finished" <<'SCRIPT'
#!/bin/bash
printf 'finished\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

QVOS_TEST_EVENT_LOG="$event_log" \
OMARCHY_PATH="$test_omarchy" \
OMARCHY_INSTALL="$test_install" \
  bash -c 'source "$1"' _ "$root/qv/install/post-install/run"

expected_run=$(
  printf 'run:%s\n' "$test_install/post-install/pacman.sh"
  printf 'run:%s\n' "$test_omarchy/qv/security/install"
  printf '%s\n' allow-reboot stop-log finished
)
[[ $(<"$event_log") == "$expected_run" ]] ||
  fail "post-install owner order"

install -m 0755 \
  "$root/qv/install/post-install/finished" \
  "$test_omarchy/qv/install/post-install/finished"

install -m 0755 /dev/stdin "$test_bin/qvos-tui" <<'SCRIPT'
#!/bin/bash
printf 'tui:%s:%s\n' "${QVOS_TUI_FULLSCREEN:-}" "$*" >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$QVOS_TEST_EVENT_LOG"
if [[ ${1:-} == "test" ]]; then
  exit 1
fi
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
printf 'gum:%s\n' "$*" >>"$QVOS_TEST_EVENT_LOG"
exit "${QVOS_TEST_GUM_STATUS:-1}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/tte" <<'SCRIPT'
#!/bin/bash
input=$(cat)
printf 'tte:%s:%s\n' "$*" "$input" >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/clear" <<'SCRIPT'
#!/bin/bash
printf 'clear\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

run_finished() {
  HOME="$test_root/home" \
    OMARCHY_PATH="$test_omarchy" \
    OMARCHY_INSTALL_LOG_FILE="$test_root/install.log" \
    QVOS_INSTALL_COMPLETION_MARKER="$completion_marker" \
    QVOS_TEST_EVENT_LOG="$event_log" \
    PATH="$test_bin:/usr/bin" \
    "$test_omarchy/qv/install/post-install/finished"
}

: >"$event_log"
OMARCHY_CHROOT_INSTALL=1 \
QVOS_TUI_BIN="$test_bin/qvos-tui" \
  run_finished >/dev/null
[[ -f $completion_marker ]] || fail "ISO completion marker"
grep -Fqx 'tui:1:--iso-finished' "$event_log" ||
  fail "ISO finished TUI"
if grep -Fq 'gum:' "$event_log"; then
  fail "ISO TUI fell through to the legacy prompt"
fi

rm -f -- "$completion_marker"
printf 'Total: 3m 12s\n' >"$test_root/install.log"
: >"$event_log"
run_finished >/dev/null
[[ ! -e $completion_marker ]] ||
  fail "declined non-ISO reboot created a completion marker"
grep -Fqx \
  "tte:-i $test_omarchy/qv/branding/logo.txt --canvas-width 0 --anchor-text c --frame-rate 920 laseretch:" \
  "$event_log" || fail "qvOS finished logo owner"
grep -Fqx \
  'tte:--canvas-width 0 --anchor-text c --frame-rate 640 print:Installed in 3m 12s' \
  "$event_log" || fail "installation duration presentation"
grep -Fq 'gum:confirm ' "$event_log" || fail "non-ISO reboot prompt"
if grep -Fq 'sudo:reboot' "$event_log"; then
  fail "declined reboot reached the system reboot command"
fi

: >"$event_log"
QVOS_TEST_GUM_STATUS=0 run_finished >/dev/null
grep -Fqx 'sudo:reboot' "$event_log" ||
  fail "accepted non-ISO reboot did not reach the system owner"

: >"$event_log"
OMARCHY_CHROOT_INSTALL=1 \
QVOS_TEST_GUM_STATUS=0 \
  run_finished >/dev/null
[[ -f $completion_marker ]] || fail "fallback chroot completion marker"
if grep -Fq 'sudo:reboot' "$event_log"; then
  fail "fallback chroot completion rebooted inside the target"
fi

rm -f -- "$completion_marker"
symlink_target="$test_root/symlink-target"
ln -s "$symlink_target" "$completion_marker"
if OMARCHY_CHROOT_INSTALL=1 \
  QVOS_TUI_BIN="$test_bin/qvos-tui" \
  run_finished >/dev/null 2>&1; then
  fail "ISO completion accepted a symbolic-link marker"
fi
[[ ! -e $symlink_target ]] ||
  fail "ISO completion followed a symbolic-link marker"

printf 'ok - qvOS singularly owns post-install order and both finished paths\n'
