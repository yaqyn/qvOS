#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
launcher="$root/bin/qv-launch-floating-terminal-with-presentation"
compatibility_launcher="$root/bin/omarchy-launch-floating-terminal-with-presentation"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
event_log="$test_root/events"
test_omarchy="$test_root/omarchy"

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

(( $(wc -l <"$launcher") <= 10 &&
  $(wc -l <"$compatibility_launcher") <= 5 )) ||
  fail "presentation adapter contains implementation"
# shellcheck disable=SC2016
grep -Fqx 'exec "$QVOS_PATH/qvcore/presentation/run" "$@"' "$launcher" ||
  fail "native presentation adapter is not direct"
# shellcheck disable=SC2016
grep -Fqx 'exec "$QVOS_PATH/qvcore/presentation/run" "$@"' \
  "$compatibility_launcher" ||
  fail "presentation compatibility adapter is not direct"

install -d \
  "$test_bin" \
  "$test_omarchy/qvcore/branding" \
  "$test_omarchy/qvcore/presentation"
install -m 0755 \
  "$root/qvcore/presentation/run" \
  "$test_omarchy/qvcore/presentation/run"

install -m 0755 /dev/stdin "$test_bin/setsid" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qv-launch-app" <<'SCRIPT'
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

install -m 0755 /dev/stdin "$test_omarchy/qvcore/branding/show-logo" <<'SCRIPT'
#!/bin/bash
printf 'logo\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_omarchy/qvcore/presentation/show-done" <<'SCRIPT'
#!/bin/bash
printf 'done\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_omarchy/qvcore/presentation/show-failed" <<'SCRIPT'
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

install -m 0755 /dev/stdin "$test_bin/qvos-test-arguments" <<'SCRIPT'
#!/bin/bash
printf 'argument\t%s\n' "$1" >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

run_launcher() {
  QVOS_TEST_EVENT_LOG="$event_log" \
    QVOS_PATH="$test_omarchy" \
    PATH="$test_bin:/usr/bin" \
    "$launcher" "$@"
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

: >"$event_log"
run_launcher qvos-test-arguments "argument with spaces"
[[ $(<"$event_log") == $'logo\nargument\targument with spaces\ndone' ]] ||
  fail "presentation command argument preservation"
pass "presentation preserves command argument boundaries"

: >"$event_log"
set +e
run_launcher "qvos-test-arguments 'shell-looking argument'" >/dev/null 2>&1
string_status=$?
set -e
((string_status == 127)) || fail "shell-looking command status"
[[ $(<"$event_log") == $'logo\nfailed\t127' ]] ||
  fail "shell-looking command execution"
pass "presentation never shell-parses a caller string"

gum_log="$test_root/gum"
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_GUM_LOG"
SCRIPT

QVOS_TEST_GUM_LOG="$gum_log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/presentation/show-done"
grep -Fqx 'Done! Press any key to close...' "$gum_log" ||
  fail "completion owner copy"
pass "completion owner validates and presents a native result"

QVOS_TEST_GUM_LOG="$gum_log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/presentation/show-failed" 7
grep -Fqx 'Failed (exit 7). Press any key to close...' "$gum_log" ||
  fail "failure owner copy"
for invalid_status in 0 256 08 invalid; do
  set +e
  QVOS_TEST_GUM_LOG="$gum_log" PATH="$test_bin:/usr/bin" \
    "$root/qvcore/presentation/show-failed" "$invalid_status" >/dev/null 2>&1
  invalid_result=$?
  set -e
  (( invalid_result == 2 )) || fail "invalid failure status: $invalid_status"
done
pass "failure owner rejects misleading or malformed statuses"
