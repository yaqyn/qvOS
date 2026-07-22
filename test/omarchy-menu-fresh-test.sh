#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
install_menu_log="$test_root/install-menu.log"
fresh_menu_log="$test_root/fresh-menu.log"
route_log="$test_root/route.log"

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

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-walker" <<'SCRIPT'
#!/bin/bash
if [[ $* == *"Install…"* ]]; then
  cat >"$QVOS_TEST_INSTALL_MENU_LOG"
  printf 'Fresh\n'
else
  cat >"$QVOS_TEST_FRESH_MENU_LOG"
  printf 'WARP\n'
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_ROUTE_LOG"
SCRIPT

QVOS_TEST_INSTALL_MENU_LOG="$install_menu_log" \
  QVOS_TEST_FRESH_MENU_LOG="$fresh_menu_log" \
  QVOS_TEST_ROUTE_LOG="$route_log" \
  HOME="$test_root" \
  PATH="$test_bin:$root/bin:/usr/bin" \
  "$root/bin/omarchy-menu" install

grep -Fqx '  Fresh' "$install_menu_log" || fail "Fresh install-menu entry"
[[ $(<"$fresh_menu_log") == "󰖂  WARP" ]] || fail "manually curated Fresh list"
[[ $(<"$route_log") == "omarchy-setup-dns WARP" ]] || fail "complete WARP setup route"
pass "Fresh delegates its qvOS-owned WARP entry to the complete setup workflow"

: >"$fresh_menu_log"
: >"$route_log"
QVOS_TEST_INSTALL_MENU_LOG="$install_menu_log" \
  QVOS_TEST_FRESH_MENU_LOG="$fresh_menu_log" \
  QVOS_TEST_ROUTE_LOG="$route_log" \
  HOME="$test_root" \
  PATH="$test_bin:$root/bin:/usr/bin" \
  "$root/bin/omarchy-menu" fresh

[[ $(<"$route_log") == "omarchy-setup-dns WARP" ]] || fail "direct Fresh route"
pass "Fresh can be opened directly"
