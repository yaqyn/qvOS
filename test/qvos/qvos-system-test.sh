#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
system_owner="$root/qv/maintenance/qvos-system"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_source="$test_root/source"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_home/.local/bin" \
  "$test_home/.local/share/qvos/maintenance" \
  "$test_source/qv/maintenance" \
  "$test_bin"
touch "$action_log"

install -m 0755 /dev/stdin \
  "$test_home/.local/share/qvos/maintenance/qvos-repair" <<'SCRIPT'
#!/bin/bash
printf 'runtime-repair\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin \
  "$test_source/qv/maintenance/qvos-repair" <<'SCRIPT'
#!/bin/bash
printf 'source-repair\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin \
  "$test_source/qv/maintenance/personal-software" <<'SCRIPT'
#!/bin/bash
printf 'software\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "choose" ]] || exit 2
printf '%s\n' "${QVOS_TEST_SELECTION:-Cancel}"
SCRIPT

run_system() {
  HOME="$test_home" \
    OMARCHY_PATH="$test_source" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    PATH="$test_bin:/usr/bin" \
    "$system_owner" "$@"
}

assert_action() {
  local expected=$1

  [[ $(<"$action_log") == "$expected" ]] ||
    fail "expected action: $expected"
  : >"$action_log"
}

run_system --status
assert_action $'runtime-repair\t--status'
run_system --repair
assert_action $'runtime-repair\t'
run_system --software
assert_action $'software\t--remove-standalone'
pass "qvOS System direct modes preserve the compatibility software route"

QVOS_TEST_SELECTION="Check system health" run_system
assert_action $'runtime-repair\t--status'
QVOS_TEST_SELECTION="Repair & recovery" run_system
assert_action $'runtime-repair\t'
pass "qvOS System presents only health and recovery actions"

set +e
cancel_output=$(QVOS_TEST_SELECTION=Cancel run_system 2>&1)
cancel_status=$?
set -e
((cancel_status == 130)) || fail "qvOS System cancellation succeeds"
grep -Fq 'qvOS System canceled.' <<<"$cancel_output" ||
  fail "qvOS System cancellation result"
[[ ! -s $action_log ]] || fail "qvOS System cancellation delegates an action"
pass "qvOS System cancellation is mutation-free"

mv \
  "$test_home/.local/share/qvos/maintenance/qvos-repair" \
  "$test_home/.local/share/qvos/maintenance/qvos-repair.missing"
run_system --status
assert_action $'source-repair\t--status'
mv \
  "$test_home/.local/share/qvos/maintenance/qvos-repair.missing" \
  "$test_home/.local/share/qvos/maintenance/qvos-repair"
pass "qvOS System falls back to tracked Recovery when runtime is unavailable"

install -m 0755 \
  "$root/qv/maintenance/qvos-system" \
  "$test_home/.local/share/qvos/maintenance/qvos-system"
install -m 0755 \
  "$root/qv/maintenance/qv" \
  "$test_home/.local/bin/qv"
HOME="$test_home" \
  OMARCHY_PATH="$test_source" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$test_home/.local/bin/qv" system --status
assert_action $'runtime-repair\t--status'
HOME="$test_home" \
  OMARCHY_PATH="$test_source" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/bin/omarchy-qvos-system" --software
assert_action $'software\t--remove-standalone'
pass "qv and Omarchy expose the same installed qvOS System hub"

set +e
invalid_output=$(run_system --status --repair 2>&1)
invalid_status=$?
set -e
((invalid_status == 2)) || fail "qvOS System accepts conflicting modes"
grep -Fq 'Usage: qvos-system' <<<"$invalid_output" ||
  fail "qvOS System invalid-mode usage"
[[ ! -s $action_log ]] || fail "qvOS System invalid mode delegates an action"
pass "qvOS System rejects ambiguous modes before delegation"
