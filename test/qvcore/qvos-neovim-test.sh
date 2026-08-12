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

[[ -f $root/qvcore/config/files/nvim/init.lua &&
  ! -L $root/qvcore/config/files/nvim/init.lua ]] ||
  fail "native Neovim seed"
[[ ! -e $root/qvcore/config/neovim &&
  ! -e $root/qvcore/config/retired-neovim-signatures.psv ]] ||
  fail "retired Neovim convergence owner"
pass "official Neovim seed has no provider convergence owner"

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
