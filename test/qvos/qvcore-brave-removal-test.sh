#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
owner="$root/qv/core/brave-origin.sh"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
packages="$test_root/packages"
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
  "$test_bin" \
  "$test_home/.config/BraveSoftware/Brave-Browser-Beta"
printf '%s\n' brave-origin-beta-bin >"$packages"
printf 'preserve\n' \
  >"$test_home/.config/BraveSoftware/Brave-Browser-Beta/Preferences"
touch "$action_log"

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
grep -Fxq "$1" "$QVOS_TEST_PACKAGES"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ $1 == "brave-origin-beta" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
[[ $* == "-Rs --print brave-origin-beta-bin" ]] || exit 2
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-remove-browser" <<'SCRIPT'
#!/bin/bash
[[ $* == "brave-origin" ]] || exit 2
printf 'browser-owner\tbrave-origin\n' >>"$QVOS_TEST_ACTION_LOG"
: >"$QVOS_TEST_PACKAGES"
SCRIPT

for command in omarchy-pkg-drop sudo; do
  install -m 0755 /dev/stdin "$test_bin/$command" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT
done

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "confirm" ]] || exit 2
[[ ${QVOS_TEST_CONFIRM:-1} == "1" ]]
SCRIPT

run_owner() {
  HOME="$test_home" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_CONFIRM="${QVOS_TEST_CONFIRM:-1}" \
    QVOS_TEST_PACKAGES="$packages" \
    PATH="$test_bin:/usr/bin" \
    "$owner" "$@"
}

run_owner --remove --check
grep -Fxq brave-origin-beta-bin "$packages" ||
  fail "Brave Origin changed during removal preflight"
[[ ! -s $action_log ]] || fail "Brave preflight ran a removal action"
pass "Brave Origin removal preflights without mutation"

set +e
cancel_output=$(QVOS_TEST_CONFIRM=0 run_owner --remove 2>&1)
cancel_status=$?
set -e
((cancel_status == 130)) || fail "Brave removal cancellation status"
grep -Fq 'nothing was changed' <<<"$cancel_output" ||
  fail "Brave removal cancellation explanation"
grep -Fxq brave-origin-beta-bin "$packages" ||
  fail "Brave Origin changed after cancellation"
[[ ! -s $action_log ]] || fail "Brave cancellation ran a removal action"
pass "Brave Origin removal requires an explicit confirmation"

remove_output=$(run_owner --remove --yes)
[[ ! -s $packages ]] || fail "Brave Origin package remains after removal"
[[ $(<"$action_log") == $'browser-owner\tbrave-origin' ]] ||
  fail "Brave Origin removal bypassed the browser owner"
[[ -f $test_home/.config/BraveSoftware/Brave-Browser-Beta/Preferences ]] ||
  fail "Brave Origin profile was removed"
grep -Fq 'browser profile and personal data were preserved' \
  <<<"$remove_output" ||
  fail "Brave Origin preservation result"
pass "Brave Origin removal reuses browser cleanup and preserves profile data"
