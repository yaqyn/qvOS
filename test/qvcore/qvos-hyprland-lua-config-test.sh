#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
verify_log="$test_root/verify.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

command -v Hyprland >/dev/null 2>&1 || fail "Hyprland is unavailable"
install -d \
  "$test_home/.config/hypr" \
  "$test_home/.config/qvos/themes"
cp -a "$root/qvcore/config/files/hypr/." "$test_home/.config/hypr/"
cp -a "$root/qvcore/theme/yaqyn" "$test_home/.config/qvos/themes/yaqyn"
sed -i "s|~/.local/share/qvos|$root|g" \
  "$test_home/.config/hypr/hyprland.lua"

QVOS_THEME_SKIP_INTEGRATIONS=1 \
HOME="$test_home" \
QVOS_PATH="$root" \
  "$root/qvcore/theme/set" yaqyn
if ! HOME="$test_home" Hyprland --verify-config \
  -c "$test_home/.config/hypr/hyprland.lua" >"$verify_log" 2>&1; then
  cat "$verify_log" >&2
  fail "missing optional toggle state invalidated Hyprland"
fi

install -d "$test_home/.local/state/qvos/toggles/hypr"
cp "$root/qvcore/config/toggle-state" \
  "$test_home/.local/state/qvos/toggles/hypr/broken.lua"
if HOME="$test_home" Hyprland --verify-config \
  -c "$test_home/.config/hypr/hyprland.lua" >"$verify_log" 2>&1; then
  fail "malformed existing toggle state was ignored"
fi
grep -Fq 'broken.lua' "$verify_log" ||
  fail "malformed toggle error did not identify its source"

printf 'ok - native Hyprland Lua tolerates absent optional state and rejects malformed state\n'
