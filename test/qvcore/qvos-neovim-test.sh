#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

fixture_source="$test_root/source"
fixture_home="$test_root/provider-home"
signature_manifest="$fixture_source/qvcore/config/retired-neovim-signatures.psv"
install -d \
  "$fixture_source/qvcore/config/files/nvim" \
  "$fixture_home/.config/nvim/lua/config" \
  "$fixture_home/.config/nvim/lua/plugins"
cp "$root/qvcore/config/files/nvim/init.lua" \
  "$fixture_source/qvcore/config/files/nvim/init.lua"
for fixture in \
  init.lua \
  lazyvim.json \
  lua/config/lazy.lua \
  lua/plugins/all-themes.lua \
  lua/plugins/omarchy-theme-hotreload.lua; do
  printf 'provider fixture: %s\n' "$fixture" >"$fixture_home/.config/nvim/$fixture"
  printf '%s|%s\n' \
    "$fixture" \
    "$(sha256sum "$fixture_home/.config/nvim/$fixture" | cut -d ' ' -f 1)" \
    >>"$signature_manifest"
done
printf 'preserve custom data\n' >"$fixture_home/.config/nvim/custom.lua"
ln -s '../../../../.config/omarchy/current/theme/neovim.lua' \
  "$fixture_home/.config/nvim/lua/plugins/theme.lua"

HOME="$fixture_home" QVOS_PATH="$fixture_source" \
  "$root/qvcore/config/neovim" >/dev/null
[[ $(sha256sum "$fixture_home/.config/nvim/init.lua" | cut -d ' ' -f 1) == \
  $(sha256sum "$root/qvcore/config/files/nvim/init.lua" | cut -d ' ' -f 1) ]] ||
  fail "native Neovim seed installation"
[[ ! -e $fixture_home/.config/nvim/lazyvim.json ]] ||
  fail "provider Neovim config retirement"
mapfile -t provider_backups < <(
  find "$fixture_home/.local/state/qvos/config-backups" \
    -mindepth 1 -maxdepth 1 -type d -name 'neovim.*' -print
)
(( ${#provider_backups[@]} == 1 )) || fail "provider Neovim backup count"
[[ $(<"${provider_backups[0]}/custom.lua") == "preserve custom data" ]] ||
  fail "provider Neovim custom-data backup"
[[ -L ${provider_backups[0]}/lua/plugins/theme.lua &&
  $(readlink -- "${provider_backups[0]}/lua/plugins/theme.lua") == \
  '../../../qvos/current/theme/neovim.lua' ]] ||
  fail "archived provider theme seam migration"
HOME="$fixture_home" QVOS_PATH="$fixture_source" \
  "$root/qvcore/config/neovim" >/dev/null
(( $(find "$fixture_home/.local/state/qvos/config-backups" \
  -mindepth 1 -maxdepth 1 -type d -name 'neovim.*' | wc -l) == 1 )) ||
  fail "Neovim reconciliation idempotence"
pass "provider Neovim config is replaced atomically with a preserved backup"

custom_home="$test_root/custom-home"
install -d "$custom_home/.config/nvim/lua/plugins"
printf 'custom config\n' >"$custom_home/.config/nvim/init.lua"
ln -s "$custom_home/.config/omarchy/current/theme/neovim.lua" \
  "$custom_home/.config/nvim/lua/plugins/theme.lua"
HOME="$custom_home" QVOS_PATH="$fixture_source" \
  "$root/qvcore/config/neovim"
[[ $(<"$custom_home/.config/nvim/init.lua") == "custom config" ]] ||
  fail "custom Neovim config preservation"
[[ $(readlink -- "$custom_home/.config/nvim/lua/plugins/theme.lua") == \
  '../../../qvos/current/theme/neovim.lua' ]] ||
  fail "custom Neovim theme seam migration"
[[ ! -e $custom_home/.local/state/qvos/config-backups ]] ||
  fail "custom Neovim config backup side effect"
pass "custom Neovim config is preserved while its exact theme seam migrates"

linked_home="$test_root/linked-home"
linked_target="$test_root/linked-config"
install -d "$linked_home/.config" "$linked_target"
printf 'outside\n' >"$linked_target/init.lua"
ln -s "$linked_target" "$linked_home/.config/nvim"
if HOME="$linked_home" QVOS_PATH="$fixture_source" \
  "$root/qvcore/config/neovim" >/dev/null 2>&1; then
  fail "linked Neovim config acceptance"
fi
[[ $(<"$linked_target/init.lua") == "outside" ]] ||
  fail "linked Neovim target preservation"
pass "unsafe Neovim config roots fail closed"

theme_home="$test_root/theme-home"
install -d "$theme_home"
HOME="$theme_home" QVOS_PATH="$root" "$root/qvcore/theme/install" >/dev/null
HOME="$theme_home" \
  QVOS_PATH="$root" \
  QVOS_THEME_SKIP_INTEGRATIONS=1 \
  "$root/qvcore/theme/set" Yaqyn
custom_theme="$theme_home/.config/qvos/themes/custom"
cp -a "$root/qvcore/theme/yaqyn" "$custom_theme"
printf 'error("imported editor code must not run")\n' \
  >"$custom_theme/qvos-neovim.lua"
sed -i 's/^accent = .*/accent = "#123456"/' "$custom_theme/colors.toml"
HOME="$theme_home" \
  QVOS_PATH="$root" \
  QVOS_THEME_SKIP_INTEGRATIONS=1 \
  "$root/qvcore/theme/set" Custom
install -d "$theme_home/.config/nvim"
cp "$root/qvcore/config/files/nvim/init.lua" "$theme_home/.config/nvim/init.lua"
[[ -f $theme_home/.config/qvos/current/theme/qvos-neovim.lua ]] ||
  fail "generated Neovim colorscheme"
grep -Fq 'accent = "#123456"' \
  "$theme_home/.config/qvos/current/theme/qvos-neovim.lua" ||
  fail "compatible-theme Neovim palette"
! grep -Fq 'imported editor code' \
  "$theme_home/.config/qvos/current/theme/qvos-neovim.lua" ||
  fail "imported Neovim code retirement"
HOME="$theme_home" nvim --headless -u "$theme_home/.config/nvim/init.lua" \
  '+lua if vim.g.colors_name ~= "qvos" then vim.cmd("cquit 1") end' '+qall'
pass "official Neovim loads the generated qvOS theme without plugins"
