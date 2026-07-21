#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
menu_log="$test_root/menu.log"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

grep -qx 'code' "$root/install/omarchy-base.packages" || fail "Code OSS package contract"

editor_env=$(bash -c 'source "$1"; printf "%s\n%s\n%s\n" "$EDITOR" "$VISUAL" "$SUDO_EDITOR"' _ "$root/config/uwsm/default")
[[ $editor_env == $'code\ncode\ncode' ]] || fail "editor environment contract"
pass "Code OSS is installed and owns all editor variables"

grep -qx 'gnome-keyring' "$root/install/omarchy-base.packages" || fail "desktop keyring package contract"
grep -Fqx "run_logged \"\$OMARCHY_INSTALL/login/default-keyring.sh\"" "$root/install/login/all.sh" || fail "default keyring setup contract"
grep -Fq "pam_gnome_keyring\\.so/d" "$root/install/login/sddm.sh" || fail "SDDM keyring setup contract"
if grep -RqsE 'omarchy-pkg-drop[[:space:]]+gnome-keyring' "$root/migrations"; then
  fail "retired keyring removal migration"
fi
pass "desktop keyring support stays complete"

grep -Fq 'ping -c 1 9.9.9.9' "$root/bin/omarchy-debug" || fail "Quad9 diagnostic probe"
pass "diagnostics follow the qvOS Quad9 policy"

if grep -Eq '^alias (c|cx|ic|ix|icx)=' "$root/default/bash/aliases"; then
  fail "disabled AI aliases"
fi
pass "disabled AI aliases stay out of the default shell"

install -d "$test_bin" "$test_root/.config/omarchy/themes"

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ $1 == "localsend" && ${QVOS_TEST_LOCALSEND:-0} == "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-missing" <<'SCRIPT'
#!/bin/bash
[[ $1 == "localsend" && ${QVOS_TEST_LOCALSEND:-0} != "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-missing" <<'SCRIPT'
#!/bin/bash
[[ $1 == "code" && ${QVOS_TEST_CODE_MISSING:-0} == "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_PACKAGE_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-theme-current" <<'SCRIPT'
#!/bin/bash
printf 'Orion\n'
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-theme-set" <<'SCRIPT'
#!/bin/bash
printf 'theme %s\n' "$1" >>"$QVOS_TEST_STYLE_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-plymouth-reset" <<'SCRIPT'
#!/bin/bash
printf 'unlock Yaqyn\n' >>"$QVOS_TEST_STYLE_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-restart-walker" <<'SCRIPT'
#!/bin/bash
printf 'restart Walker\n' >>"$QVOS_TEST_STYLE_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-walker" <<'SCRIPT'
#!/bin/bash
{
  printf '%s\n' "$*"
  cat
} >>"$QVOS_TEST_MENU_LOG"
SCRIPT

run_menu() {
  QVOS_TEST_LOCALSEND="$1" \
    QVOS_TEST_MENU_LOG="$menu_log" \
    HOME="$test_root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/omarchy-menu" trigger
}

: >"$menu_log"
run_menu 0
if grep -q 'Share' "$menu_log"; then
  fail "LocalSend menu hidden when unavailable"
fi

: >"$menu_log"
run_menu 1
grep -q 'Share' "$menu_log" || fail "LocalSend menu shown when available"
pass "LocalSend menu follows command availability"

set +e
share_output=$(QVOS_TEST_LOCALSEND=0 PATH="$test_bin:$root/bin:/usr/bin" "$root/bin/omarchy-menu-share" clipboard 2>&1)
share_status=$?
set -e
((share_status == 1)) || fail "missing LocalSend exit status"
[[ $share_output == "LocalSend is not installed" ]] || fail "missing LocalSend error"
pass "direct LocalSend route fails clearly when unavailable"

migration_home="$test_root/migration-home"
package_log="$test_root/package.log"
install -d "$migration_home/.config/uwsm"
printf '%s\n' \
  'export EDITOR=code-oss' \
  'export VISUAL=code-oss' \
  'export SUDO_EDITOR=code-oss' \
  >"$migration_home/.config/uwsm/default"

QVOS_TEST_PACKAGE_LOG="$package_log" HOME="$migration_home" PATH="$test_bin:$root/bin:/usr/bin" bash -c 'source "$1"' _ "$root/migrations/1784657678.sh" >/dev/null
migrated_editor_env=$(bash -c 'source "$1"; printf "%s\n%s\n%s\n" "$EDITOR" "$VISUAL" "$SUDO_EDITOR"' _ "$migration_home/.config/uwsm/default")
[[ $migrated_editor_env == $'code\ncode\ncode' ]] || fail "existing editor migration"

printf '%s\n' \
  'export EDITOR=helix' \
  'export VISUAL=helix' \
  'export SUDO_EDITOR=helix' \
  >"$migration_home/.config/uwsm/default"
QVOS_TEST_CODE_MISSING=1 QVOS_TEST_PACKAGE_LOG="$package_log" HOME="$migration_home" PATH="$test_bin:$root/bin:/usr/bin" bash -c 'source "$1"' _ "$root/migrations/1784657678.sh" >/dev/null
migrated_custom_env=$(bash -c 'source "$1"; printf "%s\n%s\n%s\n" "$EDITOR" "$VISUAL" "$SUDO_EDITOR"' _ "$migration_home/.config/uwsm/default")
[[ $migrated_custom_env == $'helix\nhelix\nhelix' ]] || fail "custom editor migration"
[[ $(<"$package_log") == "code" ]] || fail "existing Code OSS package migration"
pass "existing qvOS defaults migrate while custom editor choices stay intact"

theme_list=$(HOME="$test_root" OMARCHY_PATH="$root" "$root/bin/omarchy-theme-list")
[[ $theme_list == "Yaqyn" ]] || fail "single bundled theme"
pass "Yaqyn is the only bundled theme"

HOME="$test_root" OMARCHY_PATH="$root" lua - "$root" <<'LUA' || fail "single Yaqyn Style entries"
local root = arg[1]

dofile(root .. "/default/elephant/omarchy_themes.lua")
local themes = GetEntries()
assert(#themes == 1)
assert(themes[1].Text == "Yaqyn  ")
assert(themes[1].Preview == root .. "/themes/yaqyn/preview.png")
assert(themes[1].Actions.activate == "omarchy-theme-set yaqyn")

dofile(root .. "/default/elephant/omarchy_unlocks.lua")
local unlocks = GetEntries()
assert(#unlocks == 1)
assert(unlocks[1].Text == "Yaqyn  ")
assert(unlocks[1].Preview == root .. "/default/plymouth/preview-unlock.png")
assert(
  unlocks[1].Actions.activate
    == "omarchy-launch-floating-terminal-with-presentation 'omarchy-plymouth-reset'"
)
LUA
pass "dynamic Style catalogs resolve to Yaqyn only"

grep -qx 'omarchy-theme-set "Yaqyn"' "$root/install/config/theme.sh" || fail "fresh install theme"
grep -qx 'Name=Yaqyn' "$root/default/plymouth/omarchy.plymouth" || fail "Plymouth theme identity"
grep -qx 'Name=Yaqyn' "$root/default/sddm/omarchy/metadata.desktop" || fail "SDDM theme identity"
pass "fresh desktop and unlock defaults are named Yaqyn"

if [[ -e $root/themes/yaqyn/unlock.png || -e $root/themes/yaqyn/preview-unlock.png ]]; then
  fail "theme-specific unlock variant"
fi
pass "the unlock catalog has no bundled variants"

style_log="$test_root/style.log"
install -d \
  "$migration_home/.config/omarchy/themes/orion" \
  "$migration_home/.config/omarchy/themes/qvos" \
  "$migration_home/.config/omarchy/themes/personal"
QVOS_TEST_STYLE_LOG="$style_log" HOME="$migration_home" OMARCHY_PATH="$root" PATH="$test_bin:$root/bin:/usr/bin" \
  bash -c 'source "$1"' _ "$root/migrations/1784659873.sh" >/dev/null
[[ ! -e $migration_home/.config/omarchy/themes/orion ]] || fail "legacy Orion cleanup"
[[ ! -e $migration_home/.config/omarchy/themes/qvos ]] || fail "legacy qvOS cleanup"
[[ -d $migration_home/.config/omarchy/themes/personal ]] || fail "personal theme preservation"
[[ $(readlink "$migration_home/.config/elephant/menus/omarchy_themes.lua") == "$root/default/elephant/omarchy_themes.lua" ]] || fail "theme provider refresh"
[[ $(readlink "$migration_home/.config/elephant/menus/omarchy_unlocks.lua") == "$root/default/elephant/omarchy_unlocks.lua" ]] || fail "unlock provider refresh"
[[ $(<"$style_log") == $'theme Yaqyn\nrestart Walker\nunlock Yaqyn' ]] || fail "Yaqyn migration actions"
pass "existing qvOS themes migrate to Yaqyn without deleting personal themes"

vsix="$root/themes/yaqyn/vscode/extension/yaqyn-theme-0.1.0.vsix"
vsix_manifest=$(unzip -p "$vsix" extension/package.json)
[[ $(jq -r '.name + "|" + .displayName + "|" + .contributes.themes[0].label' <<<"$vsix_manifest") == "yaqyn-theme|Yaqyn|Yaqyn" ]] || fail "Yaqyn VS Code package"
pass "the bundled VS Code theme is Yaqyn end to end"
