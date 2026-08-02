#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

"$root/qv/theme/check"

themes_dir="$test_root/.config/omarchy/themes"
external_theme="$test_root/external/linked"
test_bin="$test_root/bin"
install -d "$themes_dir" "$test_bin" "$(dirname -- "$external_theme")"
cp -a "$root/qv/theme/yaqyn" "$themes_dir/personal"
cp -a "$root/qv/theme/yaqyn" "$external_theme"
printf 'personal\n' >"$themes_dir/personal/marker"
printf 'linked\n' >"$external_theme/marker"
mkdir -p "$themes_dir/yaqyn"
printf 'old yaqyn\n' >"$themes_dir/yaqyn/marker"
ln -s "$external_theme" "$themes_dir/linked"
ln -s "$root/themes/tokyo-night" "$themes_dir/tokyo-night"

HOME="$test_root" OMARCHY_PATH="$root" "$root/qv/theme/install" >/dev/null
[[ -L $themes_dir/yaqyn ]] || fail "Yaqyn runtime link"
[[ -f $themes_dir/personal/marker ]] || fail "personal theme data preservation"
[[ -L $themes_dir/linked && -f $themes_dir/linked/marker ]] ||
  fail "external compatible theme link preservation"
[[ ! -e $themes_dir/tokyo-night && ! -L $themes_dir/tokyo-night ]] ||
  fail "retired stock theme link cleanup"
compgen -G "$test_root/.local/state/qvos/theme-backups/yaqyn.*/marker" >/dev/null ||
  fail "prior Yaqyn data backup"

theme_list=$(HOME="$test_root" OMARCHY_PATH="$root" "$root/bin/omarchy-theme-list")
[[ $theme_list == $'Linked\nPersonal\nYaqyn' ]] || fail "Yaqyn and custom theme list"

printf '#!/bin/bash\nexit 0\n' >"$test_bin/theme-command-stub"
printf '#!/bin/bash\nexit 1\n' >"$test_bin/pgrep"
chmod 0755 "$test_bin/theme-command-stub" "$test_bin/pgrep"
for command in \
  omarchy-hook \
  omarchy-restart-btop \
  omarchy-restart-helix \
  omarchy-restart-hyprctl \
  omarchy-restart-mako \
  omarchy-restart-opencode \
  omarchy-restart-swayosd \
  omarchy-restart-terminal \
  omarchy-restart-waybar \
  omarchy-theme-bg-next \
  omarchy-theme-colors-from-alacritty \
  omarchy-theme-set-browser \
  omarchy-theme-set-foot \
  omarchy-theme-set-gnome \
  omarchy-theme-set-keyboard \
  omarchy-theme-set-obsidian \
  omarchy-theme-set-templates \
  omarchy-theme-set-vscode; do
  ln -s theme-command-stub "$test_bin/$command"
done
ln -s "$root/bin/omarchy-theme-set" "$test_bin/omarchy-theme-set"

HOME="$test_root" \
  OMARCHY_PATH="$root" \
  OMARCHY_THEME_SKIP_BACKGROUND=1 \
  PATH="$test_bin:/usr/bin" \
  "$root/bin/omarchy-theme-set" "Personal"
[[ $(<"$test_root/.config/omarchy/current/theme.name") == "personal" ]] ||
  fail "custom theme selection"
[[ $(<"$test_root/.config/omarchy/current/theme/marker") == "personal" ]] ||
  fail "custom theme rendering"

HOME="$test_root" \
  OMARCHY_PATH="$root" \
  OMARCHY_THEME_SKIP_BACKGROUND=1 \
  PATH="$test_bin:/usr/bin" \
  "$root/bin/omarchy-theme-set" "Linked"
[[ $(<"$test_root/.config/omarchy/current/theme/marker") == "linked" ]] ||
  fail "linked compatible theme rendering"

set +e
yaqyn_remove_output=$(
  HOME="$test_root" OMARCHY_PATH="$root" PATH="$test_bin:/usr/bin" \
    "$root/bin/omarchy-theme-remove" "Yaqyn" 2>&1
)
yaqyn_remove_status=$?
set -e
((yaqyn_remove_status == 1)) || fail "Yaqyn removal protection status"
[[ $yaqyn_remove_output == "Yaqyn is the bundled qvOS theme and cannot be removed." ]] ||
  fail "Yaqyn removal protection message"

HOME="$test_root" OMARCHY_PATH="$root" PATH="$test_bin:/usr/bin" \
  "$root/bin/omarchy-theme-remove" "Linked"
[[ ! -L $themes_dir/linked ]] || fail "linked theme removal"
[[ -f $external_theme/marker ]] || fail "external linked theme target preservation"
[[ $(<"$test_root/.config/omarchy/current/theme.name") == "yaqyn" ]] ||
  fail "active custom theme fallback"

set +e
yaqyn_install_output=$(
  HOME="$test_root" OMARCHY_PATH="$root" PATH="$test_bin:/usr/bin" \
    "$root/bin/omarchy-theme-install" \
    "https://example.com/omarchy-yaqyn-theme.git" 2>&1
)
yaqyn_install_status=$?
set -e
((yaqyn_install_status == 1)) || fail "Yaqyn repository protection status"
[[ $yaqyn_install_output == "Yaqyn is bundled with qvOS and cannot be replaced by a theme repository." ]] ||
  fail "Yaqyn repository protection message"

printf 'ok - bundled Yaqyn and compatible directory, Git, and linked theme lifecycles\n'
