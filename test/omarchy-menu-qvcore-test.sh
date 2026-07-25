#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
install_menu_log="$test_root/install-menu.log"
qvcore_menu_log="$test_root/qvcore-menu.log"
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
  printf 'qvCORE\n'
else
  cat >"$QVOS_TEST_QVCORE_MENU_LOG"
  printf '%s\n' "${QVOS_TEST_QVCORE_CHOICE:-Install All}"
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_ROUTE_LOG"
SCRIPT

QVOS_TEST_INSTALL_MENU_LOG="$install_menu_log" \
  QVOS_TEST_QVCORE_MENU_LOG="$qvcore_menu_log" \
  QVOS_TEST_ROUTE_LOG="$route_log" \
  HOME="$test_root" \
  PATH="$test_bin:$root/bin:/usr/bin" \
  "$root/bin/omarchy-menu" install

grep -Fqx '󰏖  qvCORE' "$install_menu_log" || fail "qvCORE install-menu entry"
[[ $(<"$qvcore_menu_log") == $'  Install All\n󰖟  Brave Origin\n󰖂  WARP\n󰵮  Development\n󱚤  Codex\n󰌾  Proton\n  Steam' ]] || fail "qvCORE component list"
[[ $(<"$route_log") == "omarchy-install-qvcore" ]] || fail "complete qvCORE route"
pass "qvCORE exposes the complete opt-in profile"

run_direct_route() {
  local choice=$1
  local expected=$2

  : >"$route_log"
  QVOS_TEST_INSTALL_MENU_LOG="$install_menu_log" \
    QVOS_TEST_QVCORE_MENU_LOG="$qvcore_menu_log" \
    QVOS_TEST_QVCORE_CHOICE="$choice" \
    QVOS_TEST_ROUTE_LOG="$route_log" \
    HOME="$test_root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/omarchy-menu" qvcore

  [[ $(<"$route_log") == "$expected" ]] || fail "$choice route"
}

run_direct_route "Brave Origin" "omarchy-install-qvcore brave-origin"
run_direct_route "WARP" "omarchy-install-qvcore warp"
run_direct_route "Development" "omarchy-install-qvcore dev"
run_direct_route "Codex" "omarchy-install-qvcore codex"
run_direct_route "Proton" "omarchy-install-qvcore proton"
run_direct_route "Steam" "omarchy-install-qvcore steam"
pass "qvCORE components can be installed independently"
