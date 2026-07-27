#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
owner="$root/qv/core/steam.sh"
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
  "$test_home/.config/steam" \
  "$test_home/.local/share/Steam" \
  "$test_home/.steam"
printf '%s\n' steam gamescope pipewire-jack >"$packages"
printf 'preserve\n' >"$test_home/.config/steam/config.vdf"
printf 'preserve\n' >"$test_home/.local/share/Steam/libraryfolders.vdf"
printf 'preserve\n' >"$test_home/.steam/registry.vdf"
touch "$action_log"

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
grep -Fxq "$1" "$QVOS_TEST_PACKAGES"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
[[ $* == "-Rs --print steam" ]] || exit 2
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
[[ $* == "steam" ]] || exit 2
printf 'drop\tsteam\n' >>"$QVOS_TEST_ACTION_LOG"
grep -Fvx steam "$QVOS_TEST_PACKAGES" >"$QVOS_TEST_PACKAGES.pending"
mv "$QVOS_TEST_PACKAGES.pending" "$QVOS_TEST_PACKAGES"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "confirm" ]] || exit 2
[[ ${QVOS_TEST_CONFIRM:-1} == "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-remove-gaming-steam" <<'SCRIPT'
#!/bin/bash
printf 'destructive-upstream-remove\n' >>"$QVOS_TEST_ACTION_LOG"
exit 1
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
grep -Fxq steam "$packages" || fail "Steam changed during removal preflight"
[[ ! -s $action_log ]] || fail "Steam preflight ran a removal action"
pass "Steam removal preflights without mutation"

set +e
cancel_output=$(QVOS_TEST_CONFIRM=0 run_owner --remove 2>&1)
cancel_status=$?
set -e
((cancel_status == 130)) || fail "Steam removal cancellation status"
grep -Fq 'nothing was changed' <<<"$cancel_output" ||
  fail "Steam removal cancellation explanation"
grep -Fxq steam "$packages" || fail "Steam changed after cancellation"
[[ ! -s $action_log ]] || fail "Steam cancellation ran a removal action"
pass "Steam removal requires an explicit confirmation"

remove_output=$(run_owner --remove --yes)
if grep -Fxq steam "$packages"; then
  fail "Steam package remains after confirmed removal"
fi
grep -Fxq gamescope "$packages" ||
  fail "shared qvCORE gaming dependency was removed"
grep -Fxq pipewire-jack "$packages" ||
  fail "shared audio dependency was removed"
[[ $(<"$action_log") == $'drop\tsteam' ]] ||
  fail "Steam removal bypassed the package owner"
for preserved_path in \
  "$test_home/.config/steam/config.vdf" \
  "$test_home/.local/share/Steam/libraryfolders.vdf" \
  "$test_home/.steam/registry.vdf"; do
  [[ -f $preserved_path ]] ||
    fail "Steam data was removed: $preserved_path"
done
grep -Fq 'game data and shared gaming dependencies were preserved' \
  <<<"$remove_output" ||
  fail "Steam preservation result"
pass "Steam removal preserves libraries, configuration, and shared dependencies"
