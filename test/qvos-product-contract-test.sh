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
[[ $theme_list != *"Sirius"* ]] || fail "obsolete Sirius theme"
pass "obsolete Sirius theme stays out of the catalog"
