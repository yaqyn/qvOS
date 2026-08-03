#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

"$root/qvcore/theme/check"

themes_dir="$test_root/.config/omarchy/themes"
external_theme="$test_root/external/linked"
test_bin="$test_root/bin"
install -d "$themes_dir" "$test_bin" "$(dirname -- "$external_theme")"
cp -a "$root/qvcore/theme/yaqyn" "$themes_dir/personal"
cp -a "$root/qvcore/theme/yaqyn" "$external_theme"
printf 'personal\n' >"$themes_dir/personal/marker"
printf 'linked\n' >"$external_theme/marker"
mkdir -p "$themes_dir/yaqyn"
printf 'old yaqyn\n' >"$themes_dir/yaqyn/marker"
ln -s "$external_theme" "$themes_dir/linked"
ln -s "$root/themes/tokyo-night" "$themes_dir/tokyo-night"
ln -s "$test_root/missing-theme" "$themes_dir/broken"

HOME="$test_root" OMARCHY_PATH="$root" "$root/qvcore/theme/install" >/dev/null
[[ -L $themes_dir/yaqyn ]] || fail "Yaqyn runtime link"
[[ -f $themes_dir/personal/marker ]] || fail "personal theme data preservation"
[[ -L $themes_dir/linked && -f $themes_dir/linked/marker ]] ||
  fail "external compatible theme link preservation"
[[ ! -e $themes_dir/tokyo-night && ! -L $themes_dir/tokyo-night ]] ||
  fail "retired stock theme link cleanup"
[[ -L $themes_dir/broken ]] || fail "unrelated broken theme link preservation"
compgen -G "$test_root/.local/state/qvos/theme-backups/yaqyn.*/marker" >/dev/null ||
  fail "prior Yaqyn data backup"

theme_list=$(HOME="$test_root" OMARCHY_PATH="$root" "$root/bin/omarchy-theme-list")
[[ $theme_list == $'Linked\nPersonal\nYaqyn' ]] || fail "Yaqyn and custom theme list"

"$root/qvcore/theme/validate" "$root/qvcore/theme/yaqyn" >/dev/null ||
  fail "bundled Yaqyn payload validation"
unsafe_theme="$themes_dir/unsafe"
cp -a "$root/qvcore/theme/yaqyn" "$unsafe_theme"
printf 'accent = "#112233";e touch /tmp/qvos-theme-injection\n' >"$unsafe_theme/colors.toml"
if "$root/qvcore/theme/validate" "$unsafe_theme" >/dev/null 2>&1; then
  fail "unsafe color payload rejection"
fi
rm -rf -- "$unsafe_theme"
cp -a "$root/qvcore/theme/yaqyn" "$unsafe_theme"
ln -s /etc/passwd "$unsafe_theme/internal-link"
if "$root/qvcore/theme/validate" "$unsafe_theme" >/dev/null 2>&1; then
  fail "internal theme link rejection"
fi
rm -rf -- "$unsafe_theme"

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

theme_source="$test_root/theme-source"
theme_remote="$test_root/remotes/omarchy-remote-theme.git"
mkdir -p "$theme_source" "$(dirname -- "$theme_remote")"
cp -a "$root/qvcore/theme/yaqyn/." "$theme_source/"
git -C "$theme_source" init -q -b main
git -C "$theme_source" add .
git -C "$theme_source" \
  -c user.name='qvOS Test' \
  -c user.email='test@qvos.invalid' \
  commit -qm 'Theme fixture'
git clone -q --bare "$theme_source" "$theme_remote"

HOME="$test_root" \
  OMARCHY_PATH="$root" \
  OMARCHY_THEME_SKIP_BACKGROUND=1 \
  PATH="$test_bin:/usr/bin" \
  GIT_ALLOW_PROTOCOL=file \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0="url.file://$test_root/remotes/.insteadOf" \
  GIT_CONFIG_VALUE_0='https://themes.example/' \
  "$root/bin/omarchy-theme-install" \
  'https://themes.example/omarchy-remote-theme.git' >/dev/null
[[ -d $themes_dir/remote/.git ]] || fail "Git-managed custom theme source"
[[ ! -e $test_root/.config/omarchy/current/theme/.git ]] ||
  fail "rendered theme excludes Git metadata"

set +e
local_install_output=$(
  HOME="$test_root" OMARCHY_PATH="$root" PATH="$test_bin:/usr/bin" \
    "$root/bin/omarchy-theme-install" "$theme_source" 2>&1
)
local_install_status=$?
set -e
((local_install_status == 2)) || fail "local repository URL rejection status"
[[ $local_install_output == "Theme repositories must use HTTPS or Git SSH." ]] ||
  fail "local repository URL rejection message"

vault="$test_root/vault"
mkdir -p "$vault/.obsidian/themes/Omarchy" "$test_root/.config/obsidian"
printf 'preserve\n' >"$vault/.obsidian/themes/Omarchy/marker"
printf 'body {}\n' >"$test_root/.config/omarchy/current/theme/obsidian.css"
jq -n --arg vault "$vault" '{vaults: {test: {path: $vault}}}' \
  >"$test_root/.config/obsidian/obsidian.json"
HOME="$test_root" OMARCHY_PATH="$root" \
  "$root/bin/omarchy-theme-set-obsidian"
grep -Fq '"name": "qvOS"' "$vault/.obsidian/themes/qvOS/manifest.json" ||
  fail "qvOS Obsidian theme identity"
[[ -f $vault/.obsidian/themes/qvOS/theme.css ]] ||
  fail "qvOS Obsidian theme stylesheet"
[[ -f $vault/.obsidian/themes/Omarchy/marker ]] ||
  fail "legacy Obsidian theme data preservation"

background_fixture="$test_root/background-fixture"
background_home="$test_root/background-home"
background_log="$test_root/background-open.log"
install -D -m 0755 "$root/bin/omarchy-theme-bg-install" \
  "$background_fixture/bin/omarchy-theme-bg-install"
install -D -m 0755 "$root/qvcore/theme/backgrounds" \
  "$background_fixture/qvcore/theme/backgrounds"
install -D -m 0755 "$root/qvcore/theme/name" \
  "$background_fixture/qvcore/theme/name"
install -D -m 0755 /dev/stdin "$background_fixture/qvcore/desktop/open" <<'OPEN'
#!/bin/bash
printf '%s\n' "$1" >"$QVOS_TEST_BACKGROUND_OPEN_LOG"
OPEN
mkdir -p \
  "$background_home/.config/omarchy/current" \
  "$background_home/.config/omarchy/themes/yaqyn"
printf 'yaqyn\n' >"$background_home/.config/omarchy/current/theme.name"
HOME="$background_home" \
  OMARCHY_PATH="$background_fixture" \
  QVOS_TEST_BACKGROUND_OPEN_LOG="$background_log" \
  "$background_fixture/bin/omarchy-theme-bg-install"
expected_background="$background_home/.config/omarchy/backgrounds/yaqyn"
[[ -d $expected_background && $(<"$background_log") == "$expected_background" ]] ||
  fail "validated current-theme background directory"
printf '../escape\n' >"$background_home/.config/omarchy/current/theme.name"
if HOME="$background_home" \
  OMARCHY_PATH="$background_fixture" \
  QVOS_TEST_BACKGROUND_OPEN_LOG="$background_log" \
  "$background_fixture/bin/omarchy-theme-bg-install" >/dev/null 2>&1; then
  fail "theme background path traversal rejection"
fi
[[ ! -e $background_home/.config/omarchy/escape ]] ||
  fail "invalid theme name created an external background directory"

printf 'ok - bundled Yaqyn and compatible directory, Git, and linked theme lifecycles\n'
