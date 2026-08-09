#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

if rg -q 'show_qvos_menu|omarchy-menu qvos|SUPER SHIFT ALT, SPACE' \
  "$root/qvcore/menu/routes" \
  "$root/qvcore/config/files/hypr/bindings.conf" \
  "$root/qvcore/waybar/overrides.jsonc"; then
  printf 'not ok - retired qvOS feature menu remains reachable\n' >&2
  exit 1
fi

if rg -q 'menu:software-qvcore|show_qvcore_menu' "$root/qvcore/menu"; then
  printf 'not ok - the former optional qvCORE route remains reachable\n' >&2
  exit 1
fi
grep -Fq 'menu:software-services' "$root/qvcore/menu/concepts.psv" || {
  printf 'not ok - Services is missing from Software\n' >&2
  exit 1
}
grep -Fq 'menu:software-development' "$root/qvcore/menu/concepts.psv" || {
  printf 'not ok - Development is missing from Software\n' >&2
  exit 1
}

printf 'ok - the retired qvOS feature menu is absent and Software uses product categories\n'
