#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
menu_log="$test_root/menu.log"
action_log="$test_root/action.log"
choices="$test_root/choices"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$source_root/qv/core"
cp "$root/qv/core/catalog.tsv" "$source_root/qv/core/catalog.tsv"
printf 'qvCORE\nProton\n' >"$choices"

HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  QVOS_TEST_CHOICES="$choices" \
  QVOS_TEST_MENU_LOG="$menu_log" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  bash -c '
    menu() {
      printf "%s\n%b\n" "$1" "$2" >>"$QVOS_TEST_MENU_LOG"
      choice=$(head -n 1 "$QVOS_TEST_CHOICES")
      sed -i "1d" "$QVOS_TEST_CHOICES"
      printf "%s\n" "$choice"
    }
    back_to() {
      :
    }
    source "$1"
    launch_software_action() {
      printf "%s\n" "$1" >"$QVOS_TEST_ACTION_LOG"
    }
    show_qvos_menu
  ' _ "$root/qv/menu/extension.sh"

grep -Fqx 'qvOS' "$menu_log" || fail "qvOS menu opened"
grep -Fqx '󰏖  qvCORE (Optional)' "$menu_log" ||
  fail "qvCORE route remains under qvOS"
if grep -Fq 'System' "$menu_log"; then
  fail "retired qvOS System route remains"
fi
grep -Fqx '󰌾  Proton — Install' "$menu_log" ||
  fail "qvOS route opens the two-stack qvCORE menu"
[[ $(<"$action_log") == "proton" ]] ||
  fail "qvOS qvCORE route executes selected stack action"

printf 'ok - qvOS menu routes directly into the two-stack qvCORE surface\n'
