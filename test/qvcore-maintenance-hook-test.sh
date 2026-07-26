#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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

install -d \
  "$fixture/qv/core" \
  "$test_root/.local/state/qvos/qvcore"

run_hook() {
  local component=$1

  QVOS_TEST_MAINTENANCE_LOG="$action_log" \
    HOME="$test_root" \
    OMARCHY_PATH="$fixture" \
    bash "$root/qv/core/$component/post-update.sh"
}

for component in share codex proton; do
  install -m 0644 /dev/null \
    "$test_root/.local/state/qvos/qvcore/$component"
  install -m 0755 /dev/stdin "$fixture/qv/core/$component.sh" <<'SCRIPT'
#!/bin/bash
printf 'legacy component ran\n' >>"$QVOS_TEST_MAINTENANCE_LOG"
SCRIPT

  : >"$action_log"
  run_hook "$component"
  [[ ! -s $action_log ]] ||
    fail "$component hook ran against a pre-lifecycle component"

  install -m 0755 /dev/stdin "$fixture/qv/core/$component.sh" <<'SCRIPT'
#!/bin/bash
# qvcore:lifecycle=1
[[ ${1:-} == "--repair" ]] || exit 2
printf 'repair\n' >>"$QVOS_TEST_MAINTENANCE_LOG"
SCRIPT

  run_hook "$component"
  [[ $(<"$action_log") == "repair" ]] ||
    fail "$component hook repair delegation"
done
pass "qvCORE maintenance hooks wait for lifecycle-capable deployed source"

rm -f "$test_root/.local/state/qvos/qvcore/share"
: >"$action_log"
run_hook share
[[ ! -s $action_log ]] ||
  fail "disabled qvCORE component maintenance"
pass "disabled qvCORE components remain untouched during updates"
