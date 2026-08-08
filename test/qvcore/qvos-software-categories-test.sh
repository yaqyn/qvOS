#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

concepts="$root/qvcore/menu/concepts.psv"
actions="$root/qvcore/menu/software-actions.psv"

grep -Fqx 'services||Services|Settings · Software|proton,dropbox,vpn,bitwarden|Browse|menu:software-services' \
  "$concepts" || fail "Services category contract"
grep -Fqx 'development|󰵮|Development|Settings · Software|languages,runtime,dev|Browse|menu:software-development' \
  "$concepts" || fail "Development category contract"
grep -Fqx 'proton|󰌾|Proton|Settings · Software · Services|pass,drive,mail,vpn,service,proton cli' \
  "$concepts" || fail "Proton category ownership"
grep -Fqx 'devel|󰵮|Devel|Settings · Software · Development|codex,workbench,tools,developer workstation' \
  "$concepts" || fail "Devel category ownership"
grep -Fqx 'proton|state|services/proton|native|true|tui|true|services/proton/manage install|services/proton/manage remove --yes' \
  "$actions" || fail "Proton lifecycle owner"
grep -Fqx 'devel|state|development/devel|tui|true|tui|true|development/devel/manage install|development/devel/manage remove --yes' \
  "$actions" || fail "Devel lifecycle owner"

if rg -qi 'menu:software-qvcore|show_qvcore_menu|Settings · Software · qvCORE' \
  "$root/qvcore/menu"; then
  fail "retired optional qvCORE category remains"
fi

export XDG_RUNTIME_DIR="$test_root/runtime"
install -d "$XDG_RUNTIME_DIR"
# shellcheck source=/dev/null
source "$root/qvcore/menu/extension.sh"
qv-launch-walker() { :; }

show_install_service_menu
[[ $(<"$XDG_RUNTIME_DIR/qvos-menu-view") == "software:services" ]] ||
  fail "Services browse route"
show_install_development_menu
[[ $(<"$XDG_RUNTIME_DIR/qvos-menu-view") == "software:development" ]] ||
  fail "Development browse route"

printf 'ok - Proton and Devel have singular Services and Development ownership\n'
