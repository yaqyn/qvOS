#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
menu_args_log="$test_root/menu-args.log"
qvos_menu_log="$test_root/qvos-menu.log"
qvcore_menu_log="$test_root/qvcore-menu.log"
apps_menu_log="$test_root/apps-menu.log"
setups_menu_log="$test_root/setups-menu.log"
remove_menu_log="$test_root/remove-menu.log"
route_log="$test_root/route.log"

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

install -d "$test_bin"
HOME="$test_root" OMARCHY_PATH="$root" "$root/qv/menu/install" --repair

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-walker" <<'SCRIPT'
#!/bin/bash
case $* in
*"qvOS…"*)
  printf '%s\n' "$*" >"$QVOS_TEST_MENU_ARGS_LOG"
  cat >"$QVOS_TEST_QVOS_MENU_LOG"
  printf '%s\n' "${QVOS_TEST_MENU_CHOICE:-Update qvOS}"
  ;;
*"Remove…"*)
  cat >"$QVOS_TEST_REMOVE_MENU_LOG"
  printf '%s\n' "${QVOS_TEST_REMOVE_CHOICE:-Standalone Tools}"
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

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-qvos-update" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "omarchy-launch-qvos-update" >"$QVOS_TEST_ROUTE_LOG"
SCRIPT

run_menu() {
  QVOS_TEST_MENU_CHOICE="${QVOS_TEST_MENU_CHOICE:-Update qvOS}" \
    QVOS_TEST_QVCORE_CHOICE="${QVOS_TEST_QVCORE_CHOICE:-Install Everything}" \
    QVOS_TEST_APP_CHOICE="${QVOS_TEST_APP_CHOICE:-Brave}" \
    QVOS_TEST_SETUP_CHOICE="${QVOS_TEST_SETUP_CHOICE:-WARP}" \
    QVOS_TEST_REMOVE_CHOICE="${QVOS_TEST_REMOVE_CHOICE:-Standalone Tools}" \
    QVOS_TEST_MENU_ARGS_LOG="$menu_args_log" \
    QVOS_TEST_QVOS_MENU_LOG="$qvos_menu_log" \
    QVOS_TEST_QVCORE_MENU_LOG="$qvcore_menu_log" \
    QVOS_TEST_APPS_MENU_LOG="$apps_menu_log" \
    QVOS_TEST_SETUPS_MENU_LOG="$setups_menu_log" \
    QVOS_TEST_REMOVE_MENU_LOG="$remove_menu_log" \
    QVOS_TEST_ROUTE_LOG="$route_log" \
    HOME="$test_root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/omarchy-menu" "${1:-qvos}"
}

run_route() {
  local choice=$1
  local expected=$2

  : >"$route_log"
  QVOS_TEST_MENU_CHOICE="$choice" run_menu
  [[ $(<"$route_log") == "$expected" ]] || fail "$choice route"
}

run_qvcore_route() {
  local section=$1
  local choice=$2
  local expected=$3

  : >"$route_log"
  case $section in
  main)
    QVOS_TEST_MENU_CHOICE=qvCORE \
      QVOS_TEST_QVCORE_CHOICE="$choice" \
      run_menu
    ;;
  apps)
    QVOS_TEST_MENU_CHOICE=qvCORE \
      QVOS_TEST_QVCORE_CHOICE=Applications \
      QVOS_TEST_APP_CHOICE="$choice" \
      run_menu
    ;;
  setups)
    QVOS_TEST_MENU_CHOICE=qvCORE \
      QVOS_TEST_QVCORE_CHOICE="Managed Setups" \
      QVOS_TEST_SETUP_CHOICE="$choice" \
      run_menu
    ;;
  esac
  [[ $(<"$route_log") == "$expected" ]] || fail "$choice route"
}

run_route "Update qvOS" "omarchy-launch-qvos-update"
[[ $(<"$qvos_menu_log") == $'󱅾  Update qvOS\n󰒓  System\n󰏖  qvCORE (Optional)' ]] ||
  fail "qvOS quick-access menu"
grep -Fq -- '--width 360' "$menu_args_log" || fail "qvOS menu width"
grep -Fq -- '--maxheight 760' "$menu_args_log" || fail "qvOS menu height"
pass "qvOS exposes update and one unified system hub"

run_route "System" "omarchy-qvos-system"
: >"$route_log"
QVOS_TEST_REMOVE_CHOICE="Standalone Tools" run_menu remove
[[ $(<"$route_log") == "omarchy-qvos-personal-software --remove-standalone" ]] ||
  fail "Remove Standalone Tools route"
if grep -Fq "Personal Software" "$remove_menu_log"; then
  fail "Remove menu duplicates the qvOS personal-software inventory"
fi
: >"$route_log"
run_menu update
[[ $(<"$route_log") == "omarchy-launch-qvos-update" ]] ||
  fail "Update qvOS route"
update_override=$(
  sed -n '/^show_update_menu()/,/^}/p' "$root/qv/menu/extension.sh"
)
[[ $update_override == $'show_update_menu() {\n  omarchy-launch-qvos-update\n}' ]] ||
  fail "Update qvOS stays direct"
pass "qvOS menus keep update, system, package, and standalone ownership distinct"

run_qvcore_route main "Install Everything" "omarchy-install-qvcore"
[[ $(<"$qvcore_menu_log") == $'  Install Everything\n󰏖  Applications\n󰒓  Managed Setups\n󰆴  Remove qvCORE Software' ]] ||
  fail "qvCORE category menu"
run_qvcore_route main "Remove qvCORE Software" "omarchy-qvcore-remove"
run_qvcore_route apps Devel "omarchy-install-qvcore dev"
run_qvcore_route setups "Setup Status" "omarchy-qvcore-status"
run_qvcore_route setups "Gaming Dependencies" "omarchy-install-qvcore steam"
pass "qvCORE owns installation, setup lifecycle, and curated removal"

grep -Fqx \
  'bindd = SUPER SHIFT ALT, SPACE, qvOS menu, exec, omarchy-menu qvos' \
  "$root/qv/config/files/hypr/qv/bindings.conf" || fail "direct qvOS menu binding"

grep -Fq 'for user-friendly direct access and testing' \
  "$root/qv/menu/AGENTS.md" ||
  fail "direct qvOS menu workflow instruction"
pass "qvOS menu shortcut and workflow contract stay explicit"
