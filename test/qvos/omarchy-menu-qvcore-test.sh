#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
install_menu_log="$test_root/install-menu.log"
qvcore_menu_log="$test_root/qvcore-menu.log"
apps_menu_log="$test_root/apps-menu.log"
setups_menu_log="$test_root/setups-menu.log"
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
HOME="$test_root" OMARCHY_PATH="$root" "$root/qv/menu/install" --repair

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-walker" <<'SCRIPT'
#!/bin/bash
case $* in
*"Install…"*)
  cat >"$QVOS_TEST_INSTALL_MENU_LOG"
  printf 'qvCORE\n'
  ;;
*"qvCORE — Applications…"*)
  cat >"$QVOS_TEST_APPS_MENU_LOG"
  printf '%s\n' "${QVOS_TEST_APP_CHOICE:-Brave}"
  ;;
*"qvCORE — Managed Setups…"*)
  cat >"$QVOS_TEST_SETUPS_MENU_LOG"
  printf '%s\n' "${QVOS_TEST_SETUP_CHOICE:-WARP}"
  ;;
*)
  cat >"$QVOS_TEST_QVCORE_MENU_LOG"
  printf '%s\n' "${QVOS_TEST_QVCORE_CHOICE:-Install Everything}"
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_ROUTE_LOG"
SCRIPT

run_menu() {
  QVOS_TEST_INSTALL_MENU_LOG="$install_menu_log" \
    QVOS_TEST_QVCORE_MENU_LOG="$qvcore_menu_log" \
    QVOS_TEST_APPS_MENU_LOG="$apps_menu_log" \
    QVOS_TEST_SETUPS_MENU_LOG="$setups_menu_log" \
    QVOS_TEST_QVCORE_CHOICE="${QVOS_TEST_QVCORE_CHOICE:-Install Everything}" \
    QVOS_TEST_APP_CHOICE="${QVOS_TEST_APP_CHOICE:-Brave}" \
    QVOS_TEST_SETUP_CHOICE="${QVOS_TEST_SETUP_CHOICE:-WARP}" \
    QVOS_TEST_ROUTE_LOG="$route_log" \
    HOME="$test_root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/omarchy-menu" "$1"
}

run_route() {
  local section=$1
  local choice=$2
  local expected=$3

  : >"$route_log"
  case $section in
  main)
    QVOS_TEST_QVCORE_CHOICE="$choice" run_menu qvcore
    ;;
  apps)
    QVOS_TEST_QVCORE_CHOICE=Applications \
      QVOS_TEST_APP_CHOICE="$choice" \
      run_menu qvcore
    ;;
  setups)
    QVOS_TEST_QVCORE_CHOICE="Managed Setups" \
      QVOS_TEST_SETUP_CHOICE="$choice" \
      run_menu qvcore
    ;;
  esac
  [[ $(<"$route_log") == "$expected" ]] || fail "$choice route"
}

run_menu install
grep -Fqx '󰏖  qvCORE (Optional)' "$install_menu_log" ||
  fail "optional qvCORE install-menu entry"
[[ $(<"$qvcore_menu_log") == $'  Install Everything\n󰏖  Applications\n󰒓  Managed Setups\n󰆴  Remove qvCORE Software' ]] ||
  fail "qvCORE category menu"
[[ $(<"$route_log") == "omarchy-install-qvcore" ]] ||
  fail "complete qvCORE route"
pass "qvCORE presents a curated software catalog with a separate setup category"

run_route main "Install Everything" "omarchy-install-qvcore"
run_route main "Remove qvCORE Software" "omarchy-qvcore-remove"
run_route apps "Install All Apps" "omarchy-install-qvcore apps"
run_route apps Brave "omarchy-install-qvcore brave-origin"
run_route apps Devel "omarchy-install-qvcore dev"
run_route apps Codex "omarchy-install-qvcore codex"
run_route apps Media "omarchy-install-qvcore media"
[[ $(<"$apps_menu_log") == $'  Install All Apps\n󰖟  Brave\n󰵮  Devel\n󱚤  Codex\n󰕧  Media' ]] ||
  fail "qvCORE application list"
pass "ordinary qvCORE apps share one install catalog regardless of backend"

run_route setups "Setup Status" "omarchy-qvcore-status"
run_route setups "Repair Setup" "omarchy-qvcore-repair"
run_route setups "Disable Integration" "omarchy-qvcore-disable"
run_route setups "Install All Setups" "omarchy-install-qvcore setups"
run_route setups WARP "omarchy-install-qvcore warp"
run_route setups Share "omarchy-install-qvcore share"
run_route setups Proton "omarchy-install-qvcore proton"
run_route setups "Gaming Dependencies" "omarchy-install-qvcore steam"
[[ $(<"$setups_menu_log") == $'󰋼  Setup Status\n󰑓  Repair Setup\n󰐕  Disable Integration\n  Install All Setups\n󰖂  WARP\n  Share\n󰌾  Proton\n  Gaming Dependencies' ]] ||
  fail "qvCORE managed setup list"
pass "health, repair, and disable are limited to the four managed setups"
