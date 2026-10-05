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

"$root/qvcore/theme/check"

conflict_home="$test_root/conflict-home"
install -d \
  "$conflict_home/.config/omarchy/themes/personal" \
  "$conflict_home/.config/qvos/themes/personal"
printf 'legacy\n' >"$conflict_home/.config/omarchy/themes/personal/marker"
printf 'native\n' >"$conflict_home/.config/qvos/themes/personal/marker"
if HOME="$conflict_home" QVOS_PATH="$root" \
  "$root/qvcore/theme/config-root" >/dev/null 2>&1; then
  fail "conflicting theme compatibility path"
fi
[[ $(<"$conflict_home/.config/omarchy/themes/personal/marker") == "legacy" &&
  $(<"$conflict_home/.config/qvos/themes/personal/marker") == "native" &&
  ! -L $conflict_home/.config/omarchy/themes ]] ||
  fail "conflicting theme path preservation"
pass "real compatibility-path state is preserved and rejected"

linked_root_home="$test_root/linked-root-home"
linked_root_target="$test_root/linked-root-target"
install -d "$linked_root_home/.config/omarchy" "$linked_root_target"
printf 'external\n' >"$linked_root_target/marker"
ln -s "$linked_root_target" "$linked_root_home/.config/omarchy/themes"
if HOME="$linked_root_home" QVOS_PATH="$root" \
  "$root/qvcore/theme/config-root" >/dev/null 2>&1; then
  fail "unrecognized theme compatibility link"
fi
[[ -L $linked_root_home/.config/omarchy/themes &&
  $(<"$linked_root_target/marker") == "external" &&
  ! -e $linked_root_home/.config/qvos ]] ||
  fail "linked theme-root preservation"
pass "unrecognized compatibility-root links are preserved"

themes_dir="$test_root/.config/qvos/themes"
external_theme="$test_root/external/linked"
test_bin="$test_root/bin"
install -d \
  "$themes_dir" \
  "$test_bin" \
  "$(dirname -- "$external_theme")"
cp -a "$root/qvcore/theme/yaqyn" "$themes_dir/personal"
cp -a "$root/qvcore/theme/yaqyn" "$external_theme"
printf 'personal\n' >"$themes_dir/personal/marker"
printf 'linked\n' >"$external_theme/marker"
mkdir -p "$themes_dir/yaqyn"
printf 'old yaqyn\n' >"$themes_dir/yaqyn/marker"
ln -s "$external_theme" "$themes_dir/linked"
ln -s "$test_root/missing-theme" "$themes_dir/broken"

HOME="$test_root" QVOS_PATH="$root" "$root/qvcore/theme/install" >/dev/null
for managed_entry in themes current backgrounds themed; do
  compatibility_path="$test_root/.config/omarchy/$managed_entry"
  [[ -L $compatibility_path &&
    $(readlink -- "$compatibility_path") == "../qvos/$managed_entry" ]] ||
    fail "native theme compatibility link: $managed_entry"
done
HOME="$test_root" QVOS_PATH="$root" "$root/qvcore/theme/config-root"
[[ -L $themes_dir/yaqyn ]] || fail "Yaqyn runtime link"
[[ -f $themes_dir/personal/marker ]] || fail "personal theme data preservation"
[[ -L $themes_dir/linked && -f $themes_dir/linked/marker ]] ||
  fail "external compatible theme link preservation"
[[ -L $themes_dir/broken ]] || fail "unrelated broken theme link preservation"
[[ $(readlink -- "$test_root/.config/btop/themes/current.theme") == \
  "$test_root/.config/qvos/current/theme/btop.theme" ]] ||
  fail "native btop theme integration"
[[ $(readlink -- "$test_root/.config/mako/config") == \
  "$test_root/.config/qvos/current/theme/mako.ini" ]] ||
  fail "native Mako theme integration"
compgen -G "$test_root/.local/state/qvos/theme-backups/yaqyn.*/marker" >/dev/null ||
  fail "prior Yaqyn data backup"
pass "native theme roots retain exact compatibility and application links"

custom_integration_home="$test_root/custom-integration-home"
custom_integration_target="$test_root/custom-integration-target"
install -d "$custom_integration_home/.config/btop/themes"
printf 'custom integration\n' >"$custom_integration_target"
ln -s "$custom_integration_target" \
  "$custom_integration_home/.config/btop/themes/current.theme"
HOME="$custom_integration_home" QVOS_PATH="$root" \
  "$root/qvcore/theme/config-root" >/dev/null 2>&1
[[ -L $custom_integration_home/.config/btop/themes/current.theme &&
  $(readlink -- "$custom_integration_home/.config/btop/themes/current.theme") == \
    "$custom_integration_target" &&
  $(<"$custom_integration_target") == "custom integration" ]] ||
  fail "custom application-theme integration preservation"
pass "theme reconciliation preserves custom application integrations"

theme_list=$(HOME="$test_root" QVOS_PATH="$root" "$root/bin/qv-theme-list")
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
cp -a "$root/qvcore/theme/yaqyn" "$unsafe_theme"
printf '112233; __import__("os").system("touch /tmp/qvos-theme-injection")\n' \
  >"$unsafe_theme/keyboard.rgb"
if "$root/qvcore/theme/validate" "$unsafe_theme" >/dev/null 2>&1; then
  fail "keyboard code-injection payload rejection"
fi
rm -rf -- "$unsafe_theme"
cp -a "$root/qvcore/theme/yaqyn" "$unsafe_theme"
jq '.extension = "publisher.package;touch-pwned"' \
  "$unsafe_theme/vscode.json" >"$unsafe_theme/vscode.json.next"
mv -- "$unsafe_theme/vscode.json.next" "$unsafe_theme/vscode.json"
if "$root/qvcore/theme/validate" "$unsafe_theme" >/dev/null 2>&1; then
  fail "unsafe editor extension metadata rejection"
fi
rm -rf -- "$unsafe_theme"

install -m 0755 /dev/stdin "$test_bin/theme-command-stub" <<'COMMAND'
#!/bin/bash
if [[ -n ${QVOS_THEME_TEST_COMMAND_LOG:-} ]]; then
  printf '%s\n' "${0##*/}" >>"$QVOS_THEME_TEST_COMMAND_LOG"
fi
exit 0
COMMAND
printf '#!/bin/bash\nexit 1\n' >"$test_bin/pgrep"
chmod 0755 "$test_bin/theme-command-stub" "$test_bin/pgrep"
ln -s pgrep "$test_bin/qv-toggle-enabled"
for command in \
  qv-hook \
  qv-restart-btop \
  qv-restart-helix \
  qv-restart-hyprctl \
  qv-restart-mako \
  qv-restart-swayosd \
  qv-restart-terminal \
  qv-restart-waybar \
  omarchy-restart-btop \
  omarchy-restart-helix \
  omarchy-restart-hyprctl \
  omarchy-restart-mako \
  omarchy-restart-swayosd \
  omarchy-restart-terminal \
  omarchy-restart-waybar; do
  ln -s theme-command-stub "$test_bin/$command"
done
ln -s "$root/bin/qv-theme-set" "$test_bin/qv-theme-set"

theme_set_output=$(
  HOME="$test_root" \
    QVOS_PATH="$root" \
    QVOS_THEME_SKIP_BACKGROUND=1 \
    QVOS_THEME_SKIP_INTEGRATIONS=1 \
    PATH="$test_bin:/usr/bin" \
    "$root/bin/qv-theme-set" "Personal" 2>&1
) || fail "custom theme selection command"
[[ -z $theme_set_output ]] || fail "custom theme selection emitted warnings"
[[ $(<"$test_root/.config/qvos/current/theme.name") == "personal" ]] ||
  fail "custom theme selection"
[[ $(<"$test_root/.config/qvos/current/theme/marker") == "personal" ]] ||
  fail "custom theme rendering"

theme_set_output=$(
  HOME="$test_root" \
    QVOS_PATH="$root" \
    QVOS_THEME_SKIP_BACKGROUND=1 \
    QVOS_THEME_SKIP_INTEGRATIONS=1 \
    PATH="$test_bin:/usr/bin" \
    "$root/bin/qv-theme-set" "Linked" 2>&1
) || fail "linked theme selection command"
[[ -z $theme_set_output ]] || fail "linked theme selection emitted warnings"
[[ $(<"$test_root/.config/qvos/current/theme/marker") == "linked" ]] ||
  fail "linked compatible theme rendering"

set +e
yaqyn_remove_output=$(
  HOME="$test_root" QVOS_PATH="$root" PATH="$test_bin:/usr/bin" \
    "$root/bin/qv-theme-remove" "Yaqyn" 2>&1
)
yaqyn_remove_status=$?
set -e
((yaqyn_remove_status == 1)) || fail "Yaqyn removal protection status"
[[ $yaqyn_remove_output == "Yaqyn is the bundled qvOS theme and cannot be removed." ]] ||
  fail "Yaqyn removal protection message"

HOME="$test_root" QVOS_PATH="$root" QVOS_THEME_SKIP_INTEGRATIONS=1 \
  PATH="$test_bin:/usr/bin" "$root/bin/qv-theme-remove" "Linked"
[[ ! -L $themes_dir/linked ]] || fail "linked theme removal"
[[ -f $external_theme/marker ]] || fail "external linked theme target preservation"
[[ $(<"$test_root/.config/qvos/current/theme.name") == "yaqyn" ]] ||
  fail "active custom theme fallback"

policy_root="$test_root/browser-policies"
outside_policy="$test_root/outside-browser-policy"
for browser_policy in \
  etc/chromium/policies/managed \
  etc/brave/policies/managed; do
  install -d -m 0755 "$policy_root/$browser_policy"
  printf 'prior policy\n' >"$policy_root/$browser_policy/color.json"
  chmod 0644 "$policy_root/$browser_policy/color.json"
done
install -d -m 0755 "$policy_root/etc/opt/edge/policies/managed"
printf 'outside policy\n' >"$outside_policy"
ln -s "$outside_policy" \
  "$policy_root/etc/opt/edge/policies/managed/color.json"
if HOME="$test_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_THEME_TESTING=1 \
  QVOS_THEME_BROWSER_POLICY_ROOT="$policy_root" \
  "$root/qvcore/theme/set-browser" >/dev/null 2>&1; then
  fail "linked browser theme policy was accepted"
fi
for browser_policy in \
  etc/chromium/policies/managed \
  etc/brave/policies/managed; do
  [[ $(<"$policy_root/$browser_policy/color.json") == "prior policy" ]] ||
    fail "browser policy preflight mutated an earlier target"
done
[[ $(<"$outside_policy") == "outside policy" ]] ||
  fail "linked browser policy target was mutated"
rm -f -- "$policy_root/etc/opt/edge/policies/managed/color.json"
install -m 0644 /dev/null \
  "$policy_root/etc/opt/edge/policies/managed/color.json"
install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'COMMAND'
#!/bin/bash
exit 1
COMMAND
HOME="$test_root" \
PATH="$test_bin:/usr/bin" \
QVOS_THEME_TESTING=1 \
QVOS_THEME_BROWSER_POLICY_ROOT="$policy_root" \
  "$root/qvcore/theme/set-browser"
expected_policy='{"BrowserThemeColor":"#141414","BrowserColorScheme":"device"}'
for browser_policy in \
  etc/chromium/policies/managed \
  etc/opt/edge/policies/managed \
  etc/brave/policies/managed; do
  target="$policy_root/$browser_policy/color.json"
  [[ $(<"$target") == "$expected_policy" && $(stat -c %a -- "$target") == "644" ]] ||
    fail "bounded browser theme policy: $browser_policy"
done
printf 'ok - browser colors respect the root-directory and user-leaf policy boundary\n'

browser_refresh_bin="$test_root/browser-refresh-bin"
browser_refresh_log="$test_root/browser-refresh.log"
install -d "$browser_refresh_bin"
install -m 0755 /dev/stdin "$browser_refresh_bin/qv-cmd-present" <<'COMMAND'
#!/bin/bash
[[ $# == 1 && $1 == "chromium" ]]
COMMAND
install -m 0755 /dev/stdin "$browser_refresh_bin/pgrep" <<'COMMAND'
#!/bin/bash
[[ $* == "-x chromium" ]]
COMMAND
install -m 0755 /dev/stdin "$browser_refresh_bin/chromium" <<'COMMAND'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_THEME_BROWSER_REFRESH_LOG"
COMMAND
: >"$browser_refresh_log"
HOME="$test_root" \
PATH="$browser_refresh_bin:/usr/bin" \
QVOS_THEME_TESTING=1 \
QVOS_THEME_BROWSER_POLICY_ROOT="$policy_root" \
QVOS_THEME_BROWSER_REFRESH_LOG="$browser_refresh_log" \
QVOS_THEME_SKIP_SESSION=1 \
  "$root/qvcore/theme/set-browser"
[[ ! -s $browser_refresh_log ]] ||
  fail "offline browser theme rendering refreshed a host-session process"
HOME="$test_root" \
PATH="$browser_refresh_bin:/usr/bin" \
QVOS_THEME_TESTING=1 \
QVOS_THEME_BROWSER_POLICY_ROOT="$policy_root" \
QVOS_THEME_BROWSER_REFRESH_LOG="$browser_refresh_log" \
  "$root/qvcore/theme/set-browser"
[[ $(<"$browser_refresh_log") == \
  "--refresh-platform-policy --no-startup-window" ]] ||
  fail "interactive browser theme rendering did not refresh Chromium exactly"
policy_snapshot=$(sha256sum \
  "$policy_root/etc/chromium/policies/managed/color.json")
if HOME="$test_root" \
  PATH="$browser_refresh_bin:/usr/bin" \
  QVOS_THEME_TESTING=1 \
  QVOS_THEME_BROWSER_POLICY_ROOT="$policy_root" \
  QVOS_THEME_SKIP_SESSION=invalid \
  "$root/qvcore/theme/set-browser" >/dev/null 2>&1; then
  fail "browser theme owner accepted an invalid session mode"
fi
[[ $(sha256sum "$policy_root/etc/chromium/policies/managed/color.json") == \
  "$policy_snapshot" ]] ||
  fail "invalid browser theme session mode changed policy"
pass "offline browser theming never crosses into the host session"

configure_fixture="$test_root/configure-fixture"
configure_bin="$configure_fixture/bin"
configure_log="$configure_fixture/events"
install -d "$configure_fixture/qvcore/theme" "$configure_bin"
install -m 0755 /dev/stdin "$configure_fixture/qvcore/theme/install" <<'COMMAND'
#!/bin/bash
printf 'install\n' >>"$QVOS_THEME_CONFIGURE_LOG"
COMMAND
install -m 0755 /dev/stdin "$configure_bin/sudo" <<'COMMAND'
#!/bin/bash
printf 'sudo|%s\n' "$*" >>"$QVOS_THEME_CONFIGURE_LOG"
COMMAND
install -m 0755 /dev/stdin "$configure_bin/qv-theme-set" <<'COMMAND'
#!/bin/bash
printf 'theme|%s|%s\n' "${QVOS_THEME_SKIP_SESSION:-unset}" "$*" \
  >>"$QVOS_THEME_CONFIGURE_LOG"
COMMAND
: >"$configure_log"
HOME="$test_root" \
  QVOS_PATH="$configure_fixture" \
  QVOS_THEME_CONFIGURE_LOG="$configure_log" \
  QVOS_CHROOT_INSTALL=1 \
  PATH="$configure_bin:/usr/bin" \
  "$root/qvcore/theme/configure"
grep -Fqx 'theme|1|Yaqyn' "$configure_log" ||
  fail "target-chroot theme configuration did not select offline rendering"
: >"$configure_log"
HOME="$test_root" \
  QVOS_PATH="$configure_fixture" \
  QVOS_THEME_CONFIGURE_LOG="$configure_log" \
  PATH="$configure_bin:/usr/bin" \
  "$root/qvcore/theme/configure"
grep -Fqx 'theme|unset|Yaqyn' "$configure_log" ||
  fail "ordinary theme configuration suppressed its user session"
pass "fresh theme configuration translates only the reviewed chroot boundary"

session_command_log="$test_root/theme-session-commands"
: >"$session_command_log"
session_skip_output=$(
  HOME="$test_root" \
    QVOS_PATH="$root" \
    QVOS_THEME_SKIP_SESSION=1 \
    QVOS_THEME_TEST_COMMAND_LOG="$session_command_log" \
    QVOS_THEME_TESTING=1 \
    QVOS_THEME_BROWSER_POLICY_ROOT="$policy_root" \
    PATH="$test_bin:/usr/bin" \
    "$root/bin/qv-theme-set" "Yaqyn" 2>&1
) || fail "offline theme rendering"
[[ -z $session_skip_output && ! -s $session_command_log ]] ||
  fail "offline theme rendering ran a session integration"
[[ $(<"$test_root/.config/qvos/current/theme.name") == "yaqyn" ]] ||
  fail "offline theme rendering did not activate Yaqyn"
pass "offline theme rendering avoids user-session work"

set +e
yaqyn_install_output=$(
  HOME="$test_root" QVOS_PATH="$root" PATH="$test_bin:/usr/bin" \
    "$root/bin/qv-theme-install" \
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
  QVOS_PATH="$root" \
  QVOS_THEME_SKIP_BACKGROUND=1 \
  QVOS_THEME_SKIP_INTEGRATIONS=1 \
  PATH="$test_bin:/usr/bin" \
  GIT_ALLOW_PROTOCOL=file \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0="url.file://$test_root/remotes/.insteadOf" \
  GIT_CONFIG_VALUE_0='https://themes.example/' \
  "$root/bin/qv-theme-install" \
  'https://themes.example/omarchy-remote-theme.git' >/dev/null
[[ -d $themes_dir/remote/.git ]] || fail "Git-managed custom theme source"
[[ ! -e $test_root/.config/qvos/current/theme/.git ]] ||
  fail "rendered theme excludes Git metadata"

previous_remote_head=$(git -C "$themes_dir/remote" rev-parse HEAD)
printf 'invalid keyboard payload\n' >"$theme_source/keyboard.rgb"
git -C "$theme_source" add keyboard.rgb
git -C "$theme_source" \
  -c user.name='qvOS Test' \
  -c user.email='test@qvos.invalid' \
  commit -qm 'Invalid theme update'
git -C "$theme_source" push -q "$theme_remote" main
set +e
HOME="$test_root" \
  QVOS_PATH="$root" \
  PATH="$test_bin:/usr/bin" \
  GIT_ALLOW_PROTOCOL=file \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0="url.file://$test_root/remotes/.insteadOf" \
  GIT_CONFIG_VALUE_0='https://themes.example/' \
  "$root/bin/qv-theme-update" >/dev/null 2>&1
theme_update_status=$?
set -e
((theme_update_status == 1)) || fail "invalid Git theme update status"
[[ $(git -C "$themes_dir/remote" rev-parse HEAD) == "$previous_remote_head" ]] ||
  fail "invalid Git theme update rollback"
[[ -z $(git -C "$themes_dir/remote" status --porcelain=v1 --untracked-files=all) ]] ||
  fail "invalid Git theme update cleanup"
"$root/qvcore/theme/validate" "$themes_dir/remote" >/dev/null ||
  fail "restored Git theme validation"

set +e
local_install_output=$(
  HOME="$test_root" QVOS_PATH="$root" PATH="$test_bin:/usr/bin" \
    "$root/bin/qv-theme-install" "$theme_source" 2>&1
)
local_install_status=$?
set -e
((local_install_status == 2)) || fail "local repository URL rejection status"
[[ $local_install_output == "Theme repositories must use HTTPS or Git SSH." ]] ||
  fail "local repository URL rejection message"

vault="$test_root/vault"
mkdir -p "$vault/.obsidian/themes/Omarchy" "$test_root/.config/obsidian"
printf 'preserve\n' >"$vault/.obsidian/themes/Omarchy/marker"
printf 'body {}\n' >"$test_root/.config/qvos/current/theme/obsidian.css"
jq -n --arg vault "$vault" '{vaults: {test: {path: $vault}}}' \
  >"$test_root/.config/obsidian/obsidian.json"
HOME="$test_root" QVOS_PATH="$root" \
  "$root/bin/qv-theme-set-obsidian"
grep -Fq '"name": "qvOS"' "$vault/.obsidian/themes/qvOS/manifest.json" ||
  fail "qvOS Obsidian theme identity"
[[ -f $vault/.obsidian/themes/qvOS/theme.css ]] ||
  fail "qvOS Obsidian theme stylesheet"
[[ -f $vault/.obsidian/themes/Omarchy/marker ]] ||
  fail "legacy Obsidian theme data preservation"

background_fixture="$test_root/background-fixture"
background_home="$test_root/background-home"
background_log="$test_root/background-open.log"
install -D -m 0755 "$root/bin/qv-theme-bg-install" \
  "$background_fixture/bin/qv-theme-bg-install"
install -D -m 0755 "$root/qvcore/theme/backgrounds" \
  "$background_fixture/qvcore/theme/backgrounds"
install -D -m 0755 "$root/qvcore/theme/name" \
  "$background_fixture/qvcore/theme/name"
install -D -m 0755 /dev/stdin "$background_fixture/qvcore/desktop/open" <<'OPEN'
#!/bin/bash
printf '%s\n' "$1" >"$QVOS_TEST_BACKGROUND_OPEN_LOG"
OPEN
mkdir -p \
  "$background_home/.config/qvos/current" \
  "$background_home/.config/qvos/themes/yaqyn"
printf 'yaqyn\n' >"$background_home/.config/qvos/current/theme.name"
HOME="$background_home" \
  QVOS_PATH="$background_fixture" \
  QVOS_TEST_BACKGROUND_OPEN_LOG="$background_log" \
  "$background_fixture/bin/qv-theme-bg-install"
expected_background="$background_home/.config/qvos/backgrounds/yaqyn"
[[ -d $expected_background && $(<"$background_log") == "$expected_background" ]] ||
  fail "validated current-theme background directory"
printf '../escape\n' >"$background_home/.config/qvos/current/theme.name"
if HOME="$background_home" \
  QVOS_PATH="$background_fixture" \
  QVOS_TEST_BACKGROUND_OPEN_LOG="$background_log" \
  "$background_fixture/bin/qv-theme-bg-install" >/dev/null 2>&1; then
  fail "theme background path traversal rejection"
fi
[[ ! -e $background_home/.config/omarchy/escape ]] ||
  fail "invalid theme name created an external background directory"

background_runtime_home="$test_root/background-runtime-home"
background_runtime_log="$test_root/background-runtime.log"
background_image="$test_root/background.png"
mkdir -p "$background_runtime_home/.config/qvos/current"
printf 'image fixture\n' >"$background_image"
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SYSTEMCTL'
#!/bin/bash
if [[ $* == *'--property=LoadState'* ]]; then
  printf 'not-found\n'
elif [[ $* == *'is-active'* ]]; then
  exit 0
fi
SYSTEMCTL
install -m 0755 /dev/stdin "$test_bin/setsid" <<'SETSID'
#!/bin/bash
exec "$@"
SETSID
install -m 0755 /dev/stdin "$test_bin/qv-launch-app" <<'UWSM'
#!/bin/bash
printf 'uwsm' >>"$QVOS_TEST_BACKGROUND_RUNTIME_LOG"
printf '|%s' "$@" >>"$QVOS_TEST_BACKGROUND_RUNTIME_LOG"
printf '\n' >>"$QVOS_TEST_BACKGROUND_RUNTIME_LOG"
UWSM
HOME="$background_runtime_home" \
QVOS_PATH="$root" \
QVOS_TEST_BACKGROUND_RUNTIME_LOG="$background_runtime_log" \
PATH="$test_bin:/usr/bin" \
  "$root/qvcore/theme/background-set" "$background_image"
for _ in {1..20}; do
  [[ -s $background_runtime_log ]] && break
  sleep 0.05
done
expected_background_link="$background_runtime_home/.config/qvos/current/background"
[[ -L $expected_background_link &&
  $(readlink -- "$expected_background_link") == "$background_image" ]] ||
  fail "atomic native background selection"
grep -Fqx \
  "uwsm|-u|qvos-wallpaper.scope|-d|qvOS wallpaper|-S|both|--|swaybg|-i|$expected_background_link|-m|fill" \
  "$background_runtime_log" || fail "stable qvOS wallpaper unit"
HOME="$background_runtime_home" \
QVOS_PATH="$root" \
QVOS_TEST_BACKGROUND_RUNTIME_LOG="$background_runtime_log" \
PATH="$test_bin:/usr/bin" \
  "$root/qvcore/theme/background-restore"
unlink -- "$expected_background_link"
printf 'user-owned background state\n' >"$expected_background_link"
if HOME="$background_runtime_home" \
  QVOS_PATH="$root" \
  QVOS_TEST_BACKGROUND_RUNTIME_LOG="$background_runtime_log" \
  PATH="$test_bin:/usr/bin" \
    "$root/qvcore/theme/background-set" "$background_image" >/dev/null 2>&1; then
  fail "non-link background-state replacement"
fi
grep -Fqx 'user-owned background state' "$expected_background_link" ||
  fail "non-link background-state preservation"
pass "background selection is atomic and one stable qvOS scope owns swaybg"

editor_home="$test_root/editor-home"
editor_bin="$test_root/editor-bin"
editor_log="$test_root/editor.log"
mkdir -p "$editor_home/.config/qvos/current/theme" "$editor_bin"
cp "$root/qvcore/theme/yaqyn/vscode.json" \
  "$editor_home/.config/qvos/current/theme/vscode.json"
install -m 0755 /dev/stdin "$editor_bin/qv-cmd-present" <<'COMMAND'
#!/bin/bash
[[ $1 == "code" ]]
COMMAND
install -m 0755 /dev/stdin "$editor_bin/qv-toggle-enabled" <<'TOGGLE'
#!/bin/bash
exit 1
TOGGLE
install -m 0755 /dev/stdin "$editor_bin/code" <<'CODE'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_EDITOR_LOG"
[[ ${1:-} == "--list-extensions" ]]
CODE
HOME="$editor_home" \
  PATH="$editor_bin:/usr/bin" \
  QVOS_TEST_EDITOR_LOG="$editor_log" \
  "$root/qvcore/theme/set-vscode" 2>/dev/null
[[ $(<"$editor_log") == "--list-extensions" ]] ||
  fail "external theme editor extension remains user-controlled"
[[ ! -e $editor_home/.config/Code/User/settings.json ]] ||
  fail "missing editor extension changed editor settings"

printf 'ok - bundled Yaqyn and compatible directory, Git, and linked theme lifecycles\n'
