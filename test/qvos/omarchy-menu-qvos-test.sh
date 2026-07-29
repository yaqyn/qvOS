#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

if rg -q 'show_qvos_menu|omarchy-menu qvos|SUPER SHIFT ALT, SPACE' \
  "$root/qv/menu/extension.sh" \
  "$root/qv/config/files/hypr/qv/bindings.conf" \
  "$root/qv/waybar/overrides.jsonc"; then
  printf 'not ok - retired qvOS feature menu remains reachable\n' >&2
  exit 1
fi

grep -Fq 'menu:software-qvcore' "$root/qv/menu/concepts.psv" || {
  printf 'not ok - qvCORE is missing from its normal Software route\n' >&2
  exit 1
}

printf 'ok - the retired qvOS feature menu is absent while qvCORE remains in Software\n'
