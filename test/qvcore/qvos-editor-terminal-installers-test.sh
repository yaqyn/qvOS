#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_bin="$test_root/bin"
package_log="$test_root/packages.log"
package_dir="$test_root/packages"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

install -d \
  "$source_root/bin" \
  "$source_root/qvcore/config/files" \
  "$source_root/qvcore/desktop/applications" \
  "$source_root/qvcore/defaults" \
  "$source_root/qvcore/software" \
  "$source_root/qvcore/theme" \
  "$test_bin" \
  "$package_dir"
cp -a "$root/qvcore/config/files/alacritty" "$source_root/qvcore/config/files/"
cp -a "$root/qvcore/config/files/foot" "$source_root/qvcore/config/files/"
cp -a "$root/qvcore/config/files/ghostty" "$source_root/qvcore/config/files/"
cp -a "$root/qvcore/config/files/kitty" "$source_root/qvcore/config/files/"
install -m 0644 "$root/qvcore/desktop/applications/Alacritty.desktop" \
  "$source_root/qvcore/desktop/applications/Alacritty.desktop"
install -m 0644 "$root/qvcore/software/foot.desktop" \
  "$source_root/qvcore/software/foot.desktop"
install -m 0644 "$root/qvcore/defaults/lib" \
  "$source_root/qvcore/defaults/lib"
install -m 0755 "$root/qvcore/defaults/terminal" \
  "$source_root/qvcore/defaults/terminal"
install -m 0755 "$root/bin/qv-default-terminal" \
  "$source_root/bin/qv-default-terminal"
for owner in helix-install terminal-install zed-install; do
  install -m 0755 "$root/qvcore/software/$owner" \
    "$source_root/qvcore/software/$owner"
done
for owner in refresh set-zed validate; do
  install -m 0755 "$root/qvcore/theme/$owner" \
    "$source_root/qvcore/theme/$owner"
done
for route in install-helix install-terminal install-zed; do
  install -m 0755 "$root/bin/qv-$route" "$source_root/bin/qv-$route"
  install -m 0755 "$root/bin/omarchy-$route" \
    "$source_root/bin/omarchy-$route"
done

install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
(($# > 0)) || exit 2
for package in "$@"; do
  printf '%s\n' "$package" >>"$QVOS_TEST_PACKAGE_LOG"
  touch "$QVOS_TEST_PACKAGE_DIR/$package"
  case $package in
  alacritty|foot|ghostty|kitty|helix)
    ln -sfn /bin/true "$QVOS_TEST_BIN/$package"
    ;;
  zed)
    ln -sfn /bin/true "$QVOS_TEST_BIN/zeditor"
    ;;
  esac
done
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'SCRIPT'
#!/bin/bash
command -v -- "${1:-}" >/dev/null 2>&1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-theme-set" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

export QVOS_PATH="$source_root"
export PATH="$test_bin:/usr/bin"
export QVOS_TEST_PACKAGE_LOG="$package_log"
export QVOS_TEST_PACKAGE_DIR="$package_dir"
export QVOS_TEST_BIN="$test_bin"

prepare_theme() {
  local home=$1

  install -d "$home/.config/qvos/current/theme"
  install -m 0644 "$root/qvcore/theme/yaqyn/colors.toml" \
    "$home/.config/qvos/current/theme/colors.toml"
  install -m 0644 /dev/stdin \
    "$home/.config/qvos/current/theme/helix.toml" <<'HELIX'
"ui.background" = { bg = "background" }
[palette]
background = "#080808"
HELIX
}

terminal_home="$test_root/terminal-home"
install -d "$terminal_home"
export HOME="$terminal_home"
"$source_root/qvcore/software/terminal-install" --check alacritty
[[ ! -e $package_log && ! -e $HOME/.config/alacritty ]] ||
  fail "terminal preflight mutated the fixture"
"$source_root/qvcore/software/terminal-install" alacritty >/dev/null
cmp -s "$root/qvcore/config/files/alacritty/alacritty.toml" \
  "$HOME/.config/alacritty/alacritty.toml" || fail "Alacritty default config"
cmp -s "$root/qvcore/desktop/applications/Alacritty.desktop" \
  "$HOME/.local/share/applications/Alacritty.desktop" ||
  fail "Alacritty desktop entry"
[[ $("$source_root/bin/qv-default-terminal") == "alacritty" ]] ||
  fail "Alacritty default selection"
printf 'custom terminal config\n' >"$HOME/.config/alacritty/alacritty.toml"
printf 'custom desktop entry\n' >"$HOME/.local/share/applications/Alacritty.desktop"
"$source_root/qvcore/software/terminal-install" alacritty >/dev/null
[[ $(<"$HOME/.config/alacritty/alacritty.toml") == "custom terminal config" ]] ||
  fail "existing terminal config preservation"
[[ $(<"$HOME/.local/share/applications/Alacritty.desktop") == "custom desktop entry" ]] ||
  fail "existing terminal desktop entry preservation"
pass "terminal install delegates defaults and preserves existing user files"

foot_home="$test_root/foot-home"
install -d "$foot_home"
HOME="$foot_home" "$source_root/qvcore/software/terminal-install" foot >/dev/null
cmp -s "$root/qvcore/software/foot.desktop" \
  "$foot_home/.local/share/applications/foot.desktop" ||
  fail "Foot desktop entry"
[[ $(HOME="$foot_home" "$source_root/bin/qv-default-terminal") == "foot" ]] ||
  fail "Foot default selection"
pass "Foot installs only its native optional desktop entry"

unsafe_terminal_home="$test_root/unsafe-terminal-home"
unsafe_desktop="$test_root/unsafe-desktop"
install -d "$unsafe_terminal_home/.local/share/applications"
printf 'preserve\n' >"$unsafe_desktop"
ln -s "$unsafe_desktop" \
  "$unsafe_terminal_home/.local/share/applications/Alacritty.desktop"
before_packages=$(wc -l <"$package_log")
if HOME="$unsafe_terminal_home" \
  "$source_root/qvcore/software/terminal-install" --check alacritty \
  >/dev/null 2>&1; then
  fail "linked terminal desktop entry passed preflight"
fi
[[ $(wc -l <"$package_log") == "$before_packages" &&
  $(<"$unsafe_desktop") == "preserve" ]] ||
  fail "terminal preflight touched packages or a linked target"
pass "terminal preflight fails before packages on unsafe managed paths"

helix_home="$test_root/helix-home"
prepare_theme "$helix_home"
install -d "$helix_home/.config/helix/themes"
printf 'theme = "omarchy"\n' >"$helix_home/.config/helix/config.toml"
ln -s "$helix_home/.config/qvos/current/theme/helix.toml" \
  "$helix_home/.config/helix/themes/omarchy.toml"
export HOME="$helix_home"
before_packages=$(wc -l <"$package_log")
"$source_root/qvcore/software/helix-install" --check
[[ $(wc -l <"$package_log") == "$before_packages" ]] ||
  fail "Helix preflight installed a package"
"$source_root/qvcore/software/helix-install" >/dev/null
[[ $(<"$HOME/.config/helix/config.toml") == 'theme = "qvos"' ]] ||
  fail "Helix legacy config migration"
[[ $(readlink -- "$HOME/.config/helix/themes/qvos.toml") == \
  "$HOME/.config/qvos/current/theme/helix.toml" ]] ||
  fail "Helix qvOS theme link"
[[ ! -e $HOME/.config/helix/themes/omarchy.toml &&
  ! -L $HOME/.config/helix/themes/omarchy.toml ]] ||
  fail "exact Helix legacy link cleanup"
[[ ! -e $HOME/.bashrc ]] || fail "Helix installer edited Bash configuration"
pass "Helix migrates only its exact legacy seed and never edits the shell"

reconcile_helix_home="$test_root/reconcile-helix-home"
prepare_theme "$reconcile_helix_home"
install -d "$reconcile_helix_home/.config/helix/themes"
printf 'theme = "omarchy"\n' >"$reconcile_helix_home/.config/helix/config.toml"
ln -s "$reconcile_helix_home/.config/omarchy/current/theme/helix.toml" \
  "$reconcile_helix_home/.config/helix/themes/omarchy.toml"
before_packages=$(wc -l <"$package_log")
HOME="$reconcile_helix_home" \
  "$source_root/qvcore/software/helix-install" --reconcile
[[ $(wc -l <"$package_log") == "$before_packages" ]] ||
  fail "Helix reconciliation installed a package"
[[ $(<"$reconcile_helix_home/.config/helix/config.toml") == 'theme = "qvos"' ]] ||
  fail "Helix package-free configuration migration"
[[ $(readlink -- "$reconcile_helix_home/.config/helix/themes/qvos.toml") == \
  "$reconcile_helix_home/.config/qvos/current/theme/helix.toml" ]] ||
  fail "Helix package-free native theme link"
[[ ! -e $reconcile_helix_home/.config/helix/themes/omarchy.toml &&
  ! -L $reconcile_helix_home/.config/helix/themes/omarchy.toml ]] ||
  fail "Helix package-free legacy link cleanup"
pass "Helix configuration reconciles without touching packages"

custom_helix_home="$test_root/custom-helix-home"
prepare_theme "$custom_helix_home"
install -d "$custom_helix_home/.config/helix/themes"
printf 'theme = "custom"\n' >"$custom_helix_home/.config/helix/config.toml"
ln -s "$custom_helix_home/.config/qvos/current/theme/helix.toml" \
  "$custom_helix_home/.config/helix/themes/omarchy.toml"
HOME="$custom_helix_home" "$source_root/qvcore/software/helix-install" >/dev/null
[[ $(<"$custom_helix_home/.config/helix/config.toml") == 'theme = "custom"' ]] ||
  fail "custom Helix config preservation"
[[ -L $custom_helix_home/.config/helix/themes/omarchy.toml ]] ||
  fail "custom Helix legacy theme preservation"
pass "Helix preserves custom configuration and its referenced legacy theme"

unsafe_helix_home="$test_root/unsafe-helix-home"
prepare_theme "$unsafe_helix_home"
install -d "$unsafe_helix_home/.config/helix/themes"
ln -s "$test_root/foreign-theme" \
  "$unsafe_helix_home/.config/helix/themes/qvos.toml"
before_packages=$(wc -l <"$package_log")
if HOME="$unsafe_helix_home" \
  "$source_root/qvcore/software/helix-install" --check >/dev/null 2>&1; then
  fail "conflicting Helix theme link passed preflight"
fi
[[ $(wc -l <"$package_log") == "$before_packages" ]] ||
  fail "Helix unsafe preflight installed a package"
pass "Helix refuses a conflicting qvOS theme before package mutation"

zed_home="$test_root/zed-home"
prepare_theme "$zed_home"
export HOME="$zed_home"
before_packages=$(wc -l <"$package_log")
"$source_root/qvcore/software/zed-install" --check
[[ $(wc -l <"$package_log") == "$before_packages" ]] ||
  fail "Zed preflight installed a package"
"$source_root/qvcore/software/zed-install" >/dev/null
zed_theme="$HOME/.config/zed/themes/qvos.json"
zed_settings="$HOME/.config/zed/settings.json"
jq -e '
  .["$schema"] == "https://zed.dev/schema/themes/v0.2.0.json" and
  .name == "qvOS" and .author == "Abdulrahman M. Yaqyn" and
  (.themes | length) == 1 and .themes[0].name == "qvOS" and
  .themes[0].appearance == "dark" and
  .themes[0].style["editor.background"] == "#080808" and
  .themes[0].style["terminal.ansi.bright_red"] == "#d00000"
' "$zed_theme" >/dev/null || fail "schema-shaped Zed qvOS theme"
jq -e '.theme == "qvOS" and length == 1' "$zed_settings" >/dev/null ||
  fail "Zed settings seed"
[[ $(tail -n 1 "$package_log") == "zed" ]] || fail "Zed package boundary"
! grep -Fqx omazed "$package_log" || fail "retired Omazed package"
printf '{"theme":"User Theme","custom":true}\n' >"$zed_settings"
settings_hash=$(sha256sum "$zed_settings")
"$source_root/qvcore/software/zed-install" >/dev/null
[[ $(sha256sum "$zed_settings") == "$settings_hash" ]] ||
  fail "existing Zed settings preservation"
pass "Zed installs one native theme without Omazed, launch, or settings overwrite"

unsafe_zed_home="$test_root/unsafe-zed-home"
prepare_theme "$unsafe_zed_home"
install -d "$unsafe_zed_home/.config/zed/themes"
unsafe_zed_target="$test_root/unsafe-zed-target"
printf 'preserve\n' >"$unsafe_zed_target"
ln -s "$unsafe_zed_target" "$unsafe_zed_home/.config/zed/themes/qvos.json"
before_packages=$(wc -l <"$package_log")
if HOME="$unsafe_zed_home" \
  "$source_root/qvcore/software/zed-install" --check >/dev/null 2>&1; then
  fail "linked Zed theme passed preflight"
fi
[[ $(wc -l <"$package_log") == "$before_packages" &&
  $(<"$unsafe_zed_target") == "preserve" ]] ||
  fail "Zed unsafe preflight touched packages or linked content"
pass "Zed rejects unsafe managed output before package mutation"

export HOME="$zed_home"
for route in install-helix install-zed; do
  "$source_root/bin/qv-$route" --check
  "$source_root/bin/omarchy-$route" --check
done
"$source_root/bin/qv-install-terminal" --check ghostty
"$source_root/bin/omarchy-install-terminal" --check ghostty
pass "native and compatibility adapters delegate to the same owners"
