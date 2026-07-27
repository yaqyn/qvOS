#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
hook="$root/qv/core/post-update-hook"
test_root="$(mktemp -d)"
fixture="$test_root/omarchy"
action_log="$test_root/actions"

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

install -d "$fixture/qv/core"
install -m 0644 "$hook" \
  "$fixture/qv/core/post-update-hook"
install -m 0755 /dev/stdin "$fixture/qv/core/health.sh" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_MAINTENANCE_LOG"
SCRIPT

QVOS_TEST_MAINTENANCE_LOG="$action_log" \
  HOME="$test_root" \
  OMARCHY_PATH="$fixture" \
  bash "$hook"
[[ $(<"$action_log") == "maintain" ]] ||
  fail "central qvCORE hook delegation"
pass "one central post-update hook maintains enabled setup integrations"

rm -f "$fixture/qv/core/health.sh"
: >"$action_log"
QVOS_TEST_MAINTENANCE_LOG="$action_log" \
  HOME="$test_root" \
  OMARCHY_PATH="$fixture" \
  bash "$hook"
[[ ! -s $action_log ]] ||
  fail "central qvCORE hook runs without deployed health source"
pass "qvCORE maintenance waits for its deployed setup owner"
