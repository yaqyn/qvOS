#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
menu_log="$test_root/menu.log"
action_log="$test_root/action.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$source_root/qv/core" "$test_root/home/.local/state/qvos/qvcore"
cp "$root/qv/core/catalog.tsv" "$source_root/qv/core/catalog.tsv"

run_menu() {
  local choice=$1

  HOME="$test_root/home" \
    OMARCHY_PATH="$source_root" \
    QVOS_TEST_CHOICE="$choice" \
    QVOS_TEST_MENU_LOG="$menu_log" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    bash -c '
      menu() {
        printf "%b\n" "$2" >"$QVOS_TEST_MENU_LOG"
        printf "%s\n" "$QVOS_TEST_CHOICE"
      }
      present_terminal() {
        printf "%s\n" "$*" >"$QVOS_TEST_ACTION_LOG"
      }
      back_menu() {
        printf "back\n" >"$QVOS_TEST_ACTION_LOG"
      }
      source "$1"
      show_qvcore_menu back_menu
    ' _ "$root/qv/menu/extension.sh"
}

run_menu WARP
expected_install=$'󰖂  WARP — Install\n  Share — Install\n󰌾  Proton — Install\n󰖟  Brave — Install\n󰕧  Media — Install\n󰵮  qvDEV — Install'
[[ $(<"$menu_log") == "$expected_install" ]] ||
  fail "six direct Install rows"
[[ $(<"$action_log") == "omarchy-install-qvcore warp" ]] ||
  fail "WARP Install action"

install -m 0644 /dev/null "$test_root/home/.local/state/qvos/qvcore/share"
install -m 0644 /dev/null "$test_root/home/.local/state/qvos/qvcore/qvdev"
run_menu Share
grep -Fqx '  Share — Remove' "$menu_log" ||
  fail "enrolled Share Remove row"
grep -Fqx '󰵮  qvDEV — Remove' "$menu_log" ||
  fail "enrolled qvDEV Remove row"
[[ $(<"$action_log") == "omarchy-qvcore-remove share" ]] ||
  fail "Share Remove action"

run_menu qvDEV
[[ $(<"$action_log") == "omarchy-qvcore-remove qvdev" ]] ||
  fail "qvDEV Remove action"

if rg -q 'Status|Repair|Disable|Applications|Managed Setups|Install Everything' "$menu_log"; then
  fail "retired qvCORE menu complexity"
fi

printf 'ok - qvCORE menu shows six dynamic Install or Remove actions\n'
