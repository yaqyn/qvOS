#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
command_path="$root/qv/desktop/web/qvos-localhost-open"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
launch_log="$test_root/launch"

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

install -d "$test_bin"

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash

case ",${QVOS_TEST_COMMANDS:-}," in
*,"$1",*) exit 0 ;;
*) exit 1 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-menu-input" <<'SCRIPT'
#!/bin/bash

printf '%s\n' "${QVOS_TEST_PORT_INPUT:-}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/uwsm-app" <<'SCRIPT'
#!/bin/bash

printf '%s\n' "$*" >"$QVOS_TEST_LAUNCH_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash

exit 0
SCRIPT

run_launcher() {
  QVOS_TEST_COMMANDS="${QVOS_TEST_COMMANDS:-}" \
    QVOS_TEST_PORT_INPUT="${QVOS_TEST_PORT_INPUT:-}" \
    QVOS_TEST_LAUNCH_LOG="$launch_log" \
    PATH="$test_bin:/usr/bin" \
    "$command_path" "$@"
}

QVOS_TEST_COMMANDS="chromium" run_launcher 3000
[[ "$(<"$launch_log")" == "-- chromium --app=http://localhost:3000" ]] || fail "Chromium web-app launch"
pass "Chromium is the primary localhost web-app browser"

QVOS_TEST_COMMANDS="brave-origin-beta" run_launcher 4173
[[ "$(<"$launch_log")" == "-- brave-origin-beta --app=http://localhost:4173" ]] || fail "Brave Origin web-app fallback"
pass "Brave Origin web-app mode is used when Chromium is unavailable"

QVOS_TEST_COMMANDS="omarchy-menu-input,chromium" QVOS_TEST_PORT_INPUT="5173" run_launcher
[[ "$(<"$launch_log")" == "-- chromium --app=http://localhost:5173" ]] || fail "prompted port launch"
pass "the keybinding prompt launches the selected port"

QVOS_TEST_COMMANDS="chromium" run_launcher 03000
[[ "$(<"$launch_log")" == "-- chromium --app=http://localhost:3000" ]] || fail "normalized port"
pass "leading zeroes are removed from ports"

for invalid_port in 0 65536 invalid; do
  if QVOS_TEST_COMMANDS="chromium" run_launcher "$invalid_port" >/dev/null 2>&1; then
    fail "invalid port $invalid_port"
  fi
done
pass "invalid ports are rejected"

if QVOS_TEST_COMMANDS="" run_launcher 3000 >/dev/null 2>&1; then
  fail "missing browser failure"
fi
pass "missing browsers produce a clear failure"

set +e
QVOS_TEST_COMMANDS="chromium" run_launcher 3000 extra >/dev/null 2>&1
usage_status=$?
set -e
((usage_status == 2)) || fail "unexpected argument status"
pass "unexpected arguments show usage"
