#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
menu_args_log="$test_root/menu-args.log"
menu_log="$test_root/menu.log"
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

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-walker" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_MENU_ARGS_LOG"
cat >"$QVOS_TEST_MENU_LOG"
printf '%s\n' "${QVOS_TEST_MENU_CHOICE:-Update qvOS}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_ROUTE_LOG"
SCRIPT

run_route() {
  local choice=$1
  local expected=$2

  : >"$route_log"
  QVOS_TEST_MENU_CHOICE="$choice" \
    QVOS_TEST_MENU_ARGS_LOG="$menu_args_log" \
    QVOS_TEST_MENU_LOG="$menu_log" \
    QVOS_TEST_ROUTE_LOG="$route_log" \
    HOME="$test_root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/omarchy-menu" qvos

  [[ $(<"$route_log") == "$expected" ]] || fail "$choice route"
}

run_route "Update qvOS" "omarchy-update"

[[ $(<"$menu_log") == $'󱅾  Update qvOS\n󰑓  Repair qvOS\n󰘶  Inherited Extras\n󰓅  qvCORE Health / Repair\n󰐕  Disable qvCORE Integrations\n  Install qvCORE\n󰖟  Brave\n󰖂  WARP\n  Share\n󰵮  Devel\n󱚤  Codex\n󰌾  Proton\n  Steam\n󰕧  Media' ]] ||
  fail "flat qvOS feature menu"
grep -Fq -- '--width 360' "$menu_args_log" || fail "qvOS menu width"
grep -Fq -- '--maxheight 760' "$menu_args_log" || fail "qvOS menu height"
pass "direct qvOS menu shows every normal qvOS button in one window"

run_route "Repair qvOS" "omarchy-qvos-repair"
run_route "Inherited Extras" "omarchy-qvos-cleanup-inherited --apply"
run_route "qvCORE Health / Repair" "omarchy-qvcore-repair"
run_route "Disable qvCORE Integrations" "omarchy-qvcore-disable"
run_route "Install qvCORE" "omarchy-install-qvcore"
run_route "Brave" "omarchy-install-qvcore brave-origin"
run_route "WARP" "omarchy-install-qvcore warp"
run_route "Share" "omarchy-install-qvcore share"
run_route "Devel" "omarchy-install-qvcore dev"
run_route "Codex" "omarchy-install-qvcore codex"
run_route "Proton" "omarchy-install-qvcore proton"
run_route "Steam" "omarchy-install-qvcore steam"
run_route "Media" "omarchy-install-qvcore media"
pass "direct qvOS menu delegates every button to its existing owner"

grep -Fqx \
  'bindd = SUPER SHIFT ALT, SPACE, qvOS menu, exec, omarchy-menu qvos' \
  "$root/config/hypr/qv/bindings.conf" || fail "direct qvOS menu binding"

grep -Fq 'mirror their buttons' "$root/AGENTS.md" ||
  fail "direct qvOS menu workflow instruction"
pass "qvOS menu shortcut and workflow contract stay explicit"
