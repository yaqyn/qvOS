#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$root/bin/omarchy-launch-floating-terminal-with-presentation"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
event_log="$test_root/events"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"

install -m 0755 /dev/stdin "$test_bin/setsid" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/uwsm-app" <<'SCRIPT'
#!/bin/bash
[[ $1 == "--" ]] && shift
exec "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/xdg-terminal-exec" <<'SCRIPT'
#!/bin/bash
while [[ $1 != "-e" ]]; do
  shift
done
shift
exec "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-show-logo" <<'SCRIPT'
#!/bin/bash
printf 'logo\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-show-done" <<'SCRIPT'
#!/bin/bash
printf 'done\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-show-failed" <<'SCRIPT'
#!/bin/bash
printf 'failed\t%s\n' "$1" >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qvos-test-success" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qvos-test-failure" <<'SCRIPT'
#!/bin/bash
exit 7
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qvos-test-cancel" <<'SCRIPT'
#!/bin/bash
exit 130
SCRIPT

run_launcher() {
  QVOS_TEST_EVENT_LOG="$event_log" \
    PATH="$test_bin:/usr/bin" \
    "$launcher" "$1"
}

: >"$event_log"
run_launcher qvos-test-success
[[ $(<"$event_log") == $'logo\ndone' ]] ||
  fail "successful presentation result"
pass "presentation reports successful commands as done"

: >"$event_log"
set +e
run_launcher qvos-test-failure
failure_status=$?
set -e
((failure_status == 7)) || fail "presentation failure exit status"
[[ $(<"$event_log") == $'logo\nfailed\t7' ]] ||
  fail "failed presentation result"
pass "presentation reports failures without claiming done"

: >"$event_log"
set +e
run_launcher qvos-test-cancel
cancel_status=$?
set -e
((cancel_status == 130)) || fail "presentation cancellation exit status"
[[ $(<"$event_log") == "logo" ]] ||
  fail "canceled presentation result"
pass "presentation closes canceled commands without a false result"
