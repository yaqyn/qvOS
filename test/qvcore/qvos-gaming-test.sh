#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
fixture="$test_root/source"
test_home="$test_root/home"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$fixture/bin" "$fixture/qvcore/gaming" "$test_bin"
for route in \
  omarchy-install-gaming-retroarch \
  omarchy-remove-gaming-retroarch \
  qv-install-gaming-retroarch \
  qv-remove-gaming-retroarch; do
  install -m 0755 "$root/bin/$route" "$fixture/bin/$route"
done
for source in \
  retroarch-install \
  retroarch-packages \
  retroarch-remove; do
  install -m 0755 "$root/qvcore/gaming/$source" "$fixture/qvcore/gaming/$source"
done
install -m 0644 "$root/qvcore/gaming/retroarch.packages" \
  "$fixture/qvcore/gaming/retroarch.packages"

install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'STUB'
#!/bin/bash
printf 'add:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-drop" <<'STUB'
#!/bin/bash
printf 'drop:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB

config_dir="$test_home/.config/retroarch"
config_file="$config_dir/retroarch.cfg"
preset="$config_dir/config/global.slangp"
save_file="$test_home/.local/share/retroarch/saves/game.srm"
cache_file="$test_home/.cache/retroarch/cache.bin"
rom_file="$test_home/Games/roms/game.rom"
install -D -m 0600 /dev/stdin "$config_file" <<'CONFIG'
custom_setting = "preserve"
video_driver = "old"
video_driver = "duplicate"
CONFIG
install -D -m 0644 /dev/stdin "$preset" <<'PRESET'
#reference "custom.slangp"
PRESET
install -D -m 0600 /dev/stdin "$save_file" <<'SAVE'
save
SAVE
install -D -m 0600 /dev/stdin "$cache_file" <<'CACHE'
cache
CACHE
install -D -m 0600 /dev/stdin "$rom_file" <<'ROM'
rom
ROM
touch "$action_log"

run_retroarch() {
  HOME="$test_home" \
    QVOS_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$@"
}

run_retroarch "$fixture/bin/qv-install-gaming-retroarch" >/dev/null
add_packages=$(sed -n 's/^add://p' "$action_log")
[[ -n $add_packages ]] || fail "RetroArch package install delegation"
grep -qw 'libretro-database-git' <<<"$add_packages" ||
  fail "RetroArch database package installation"
[[ $(grep -Fc 'video_driver = "vulkan"' "$config_file") == 1 ]] ||
  fail "RetroArch config convergence"
grep -Fqx 'custom_setting = "preserve"' "$config_file" ||
  fail "RetroArch custom config preservation"
grep -Fqx '#reference "custom.slangp"' "$preset" ||
  fail "RetroArch custom global shader preservation"

run_retroarch "$fixture/bin/qv-remove-gaming-retroarch" >/dev/null
drop_packages=$(sed -n 's/^drop://p' "$action_log")
[[ $drop_packages == "$add_packages" ]] ||
  fail "RetroArch install and removal package symmetry"
for user_file in "$config_file" "$preset" "$save_file" "$cache_file" "$rom_file"; do
  [[ -f $user_file ]] || fail "RetroArch user data preservation: $user_file"
done

external_config="$test_root/external-retroarch.cfg"
printf 'external\n' >"$external_config"
rm -- "$config_file"
ln -s "$external_config" "$config_file"
: >"$action_log"
if run_retroarch "$fixture/bin/omarchy-install-gaming-retroarch" >/dev/null 2>&1; then
  fail "RetroArch symbolic-link config rejection"
fi
[[ ! -s $action_log && $(<"$external_config") == "external" ]] ||
  fail "RetroArch preflight preceded package and external-file mutation"

"$root/qvcore/gaming/check"
printf 'ok - gaming package, configuration, and user-data lifecycles are singular\n'
