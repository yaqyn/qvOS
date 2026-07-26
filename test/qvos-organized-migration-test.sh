#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
migration="$root/migrations/1785020679.sh"
test_root="$(mktemp -d)"
fixture="$test_root/omarchy"
test_bin="$test_root/bin"
action_log="$test_root/actions"
system_root="$test_root/system"

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
  "$fixture/install/config" \
  "$fixture/qv/core" \
  "$system_root/etc/chromium/policies/managed" \
  "$system_root/etc/brave/policies/managed" \
  "$system_root/var/log" \
  "$test_bin"
chmod 0777 \
  "$system_root/etc/chromium/policies/managed" \
  "$system_root/etc/brave/policies/managed"
touch \
  "$system_root/etc/chromium/policies/managed/color.json" \
  "$system_root/var/log/omarchy-install.log"
chmod 0666 \
  "$system_root/etc/chromium/policies/managed/color.json" \
  "$system_root/var/log/omarchy-install.log"

install -m 0644 /dev/stdin "$fixture/install/config/qvos-scripts.sh" <<'SCRIPT'
printf 'payload\n' >>"$QVOS_TEST_MIGRATION_LOG"
[[ ${QVOS_TEST_PAYLOAD_FAIL:-0} != "1" ]]
SCRIPT

for component in share codex proton; do
  install -m 0755 /dev/stdin "$fixture/qv/core/$component.sh" <<'SCRIPT'
#!/bin/bash
component=$(basename "$0" .sh)
printf '%s\t%s\n' "$component" "$*" >>"$QVOS_TEST_MIGRATION_LOG"
[[ $component != "${QVOS_TEST_COMPONENT_FAIL:-}" ]]
SCRIPT
done

install -m 0755 /dev/stdin "$test_bin/omarchy-refresh-config" <<'SCRIPT'
#!/bin/bash
printf 'refresh\t%s\n' "$*" >>"$QVOS_TEST_MIGRATION_LOG"
[[ ${QVOS_TEST_REFRESH_FAIL:-0} != "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf 'hyprctl\t%s\n' "$*" >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
case $1 in
localsend | codex | proton-drive) exit 0 ;;
*) exit 1 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/proton-drive" <<'SCRIPT'
#!/bin/bash
[[ $* == "filesystem info -j /my-files" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
case $1 in
chown)
  exit 0
  ;;
install)
  shift
  args=()
  while (($# > 0)); do
    case $1 in
    -o | -g)
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  exec install "${args[@]}"
  ;;
*)
  exec "$@"
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-theme-set-browser" <<'SCRIPT'
#!/bin/bash
printf 'theme-browser\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT

run_migration() {
  QVOS_TEST_COMPONENT_FAIL="${QVOS_TEST_COMPONENT_FAIL:-}" \
    QVOS_TEST_MIGRATION_LOG="$action_log" \
    QVOS_TEST_PAYLOAD_FAIL="${QVOS_TEST_PAYLOAD_FAIL:-0}" \
    QVOS_SYSTEM_ROOT="$system_root" \
    QVOS_TEST_REFRESH_FAIL="${QVOS_TEST_REFRESH_FAIL:-0}" \
    HOME="$test_root" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    bash "$migration"
}

: >"$action_log"
run_migration >/dev/null
[[ $(<"$action_log") == $'payload\nrefresh\thypr/qv/bindings.conf\nhyprctl\treload\nshare\t--adopt\ncodex\t--adopt\nproton\t--adopt\ntheme-browser' ]] ||
  fail "complete organized migration order"
[[ $(stat -c '%a' "$system_root/etc/chromium/policies/managed") == "755" ]] ||
  fail "existing Chromium policy directory mode"
[[ $(stat -c '%a' "$system_root/etc/brave/policies/managed") == "755" ]] ||
  fail "existing Brave policy directory mode"
[[ $(stat -c '%a' "$system_root/etc/chromium/policies/managed/color.json") == "644" ]] ||
  fail "existing Chromium theme policy mode"
[[ $(stat -c '%a' "$system_root/etc/brave/policies/managed/color.json") == "644" ]] ||
  fail "missing Brave theme policy creation"
[[ $(stat -c '%a' "$system_root/var/log/omarchy-install.log") == "640" ]] ||
  fail "existing install log mode"
pass "organized migration applies every eligible integration"

: >"$action_log"
set +e
failure_output=$(QVOS_TEST_COMPONENT_FAIL=share run_migration 2>&1)
failure_status=$?
set -e
((failure_status != 0)) ||
  fail "failed Share adoption marks migration complete"
grep -Fq 'qvOS foundation migration is incomplete' \
  <<<"$failure_output" ||
  fail "incomplete migration retry message"
grep -Fqx $'codex\t--adopt' "$action_log" ||
  fail "failed Share adoption prevents safe Codex adoption"
grep -Fqx $'proton\t--adopt' "$action_log" ||
  fail "failed Share adoption prevents safe Proton adoption"
pass "component failures remain retryable without blocking independent repairs"

: >"$action_log"
if QVOS_TEST_PAYLOAD_FAIL=1 run_migration >/dev/null 2>&1; then
  fail "failed desktop payload marks migration complete"
fi
pass "desktop payload failures keep the migration pending"
