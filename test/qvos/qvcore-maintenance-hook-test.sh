#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
hook="$root/config/omarchy/hooks/post-update.d/qvos-qvcore"
migration="$root/migrations/1785073962.sh"
test_root="$(mktemp -d)"
fixture="$test_root/omarchy"
action_log="$test_root/actions"
installed_hook="$test_root/.config/omarchy/hooks/post-update.d/qvos-qvcore"

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
  "$fixture/config/omarchy/hooks/post-update.d" \
  "$fixture/qv/core" \
  "$(dirname -- "$installed_hook")"
install -m 0644 "$hook" \
  "$fixture/config/omarchy/hooks/post-update.d/qvos-qvcore"
install -m 0755 /dev/stdin "$fixture/qv/core/health.sh" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_MAINTENANCE_LOG"
SCRIPT

QVOS_TEST_MAINTENANCE_LOG="$action_log" \
  HOME="$test_root" \
  OMARCHY_PATH="$fixture" \
  bash "$hook"
[[ $(<"$action_log") == "update" ]] ||
  fail "central qvCORE hook delegation"
pass "one central post-update hook delegates to qvCORE update health"

rm -f "$fixture/qv/core/health.sh"
: >"$action_log"
QVOS_TEST_MAINTENANCE_LOG="$action_log" \
  HOME="$test_root" \
  OMARCHY_PATH="$fixture" \
  bash "$hook"
[[ ! -s $action_log ]] ||
  fail "central qvCORE hook runs without deployed health source"
pass "qvCORE update hook waits for its deployed lifecycle owner"

for component in share dev codex proton; do
  install -m 0644 /dev/null \
    "$test_root/.config/omarchy/hooks/post-update.d/qvos-qvcore-$component"
done
HOME="$test_root" OMARCHY_PATH="$fixture" bash "$migration" >/dev/null
cmp -s "$hook" "$installed_hook" ||
  fail "central qvCORE hook migration"
for component in share dev codex proton; do
  [[ ! -e $test_root/.config/omarchy/hooks/post-update.d/qvos-qvcore-$component ]] ||
    fail "$component legacy post-update hook migration cleanup"
done
pass "migration replaces per-component hooks with one quiet update check"
