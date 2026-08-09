#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_bin="$test_root/bin"
installed_packages="$test_root/packages"
installed_tools="$test_root/tools"
log="$test_root/actions.log"
thunar_config="$test_root/home/.config/Thunar/uca.xml"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$source_root/development/devel" \
  "$source_root/qvcore/direct" \
  "$source_root/qvcore/install" \
  "$source_root/qvcore/thunar" \
  "$test_bin" \
  "$installed_packages" \
  "$installed_tools" \
  "$(dirname -- "$thunar_config")"
cp "$root/development/devel/manage" "$source_root/development/devel/manage"
cp "$root/development/devel/packages.tsv" "$source_root/development/devel/packages.tsv"
cp "$root/qvcore/install/migrate-structure" "$source_root/qvcore/install/migrate-structure"
cp "$root/qvcore/thunar/actions.sh" "$source_root/qvcore/thunar/actions.sh"
cp "$root/qvcore/thunar/codex" "$source_root/qvcore/thunar/codex"
printf '<?xml version="1.0" encoding="UTF-8"?><actions/>\n' >"$thunar_config"

install -m 0755 /dev/stdin "$source_root/qvcore/direct/tool" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
action=$1
target=$2
case $action in
list-scope)
  [[ $target == "devel" ]] &&
    printf 'node\nuv\nsemgrep\ndevcontainer\nplaywright-cli\n'
  ;;
install)
  install -m 0644 /dev/null "$QVOS_TEST_TOOLS/$target"
  printf 'tool-install\t%s\n' "$target" >>"$QVOS_TEST_LOG"
  ;;
verify | installed) [[ -f $QVOS_TEST_TOOLS/$target ]] ;;
remove)
  rm -f "$QVOS_TEST_TOOLS/$target"
  printf 'tool-remove\t%s\n' "$target" >>"$QVOS_TEST_LOG"
  ;;
esac
SCRIPT

for name in qv-pkg-present qv-pkg-missing qv-pkg-add \
  qv-pkg-drop qv-cmd-present pacman gum; do
  install -m 0755 /dev/stdin "$test_bin/$name" <<'SCRIPT'
#!/bin/bash
case ${0##*/} in
qv-pkg-present) [[ -f $QVOS_TEST_PACKAGES/$1 ]] ;;
qv-pkg-missing) [[ ! -f $QVOS_TEST_PACKAGES/$1 ]] ;;
qv-pkg-add)
  for package in "$@"; do
    install -m 0644 /dev/null "$QVOS_TEST_PACKAGES/$package"
    printf 'package-add\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
qv-pkg-drop)
  for package in "$@"; do
    rm -f "$QVOS_TEST_PACKAGES/$package"
    printf 'package-drop\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
qv-cmd-present) exit 0 ;;
pacman | gum) exit 0 ;;
esac
SCRIPT
done

run_devel() {
  HOME="$test_root/home" \
    XDG_STATE_HOME="$test_root/home/.local/state" \
    PATH="$test_bin:/usr/bin" \
    QVOS_THUNAR_CONFIG="$thunar_config" \
    QVOS_TEST_PACKAGES="$installed_packages" \
    QVOS_TEST_TOOLS="$installed_tools" \
    QVOS_TEST_LOG="$log" \
    "$source_root/development/devel/manage" "$@"
}

install -m 0644 /dev/null "$installed_packages/7zip"
install -m 0644 /dev/null "$installed_tools/codex"
install -m 0644 /dev/null "$installed_tools/node"
run_devel install >/dev/null
[[ -f $test_root/home/.local/state/qvos/development/devel ]] ||
  fail "Devel enrollment"
[[ $(stat -c '%a' "$test_root/home/.local/state/qvos/development") == "700" &&
  $(stat -c '%a' "$test_root/home/.local/state/qvos/development/devel") == "600" ]] ||
  fail "private Devel enrollment"
[[ $(grep -c $'^package-add\t7zip$' "$log" || true) == "0" ]] ||
  fail "Devel reinstalls compatible Pacman software"
[[ $(grep -c $'^tool-install\tnode$' "$log" || true) == "0" ]] ||
  fail "Devel reinstalls a compatible direct tool"
for tool_id in node uv semgrep devcontainer playwright-cli; do
  [[ -f $installed_tools/$tool_id ]] || fail "Devel direct tool: $tool_id"
done
[[ -x $test_root/home/.local/lib/qvos/thunar/codex ]] ||
  fail "Devel Codex workbench helper"

printf 'stale integration\n' \
  >"$test_root/home/.local/lib/qvos/thunar/codex"
action_count=$(wc -l <"$log")
run_devel reconcile >/dev/null
cmp -s \
  "$source_root/qvcore/thunar/codex" \
  "$test_root/home/.local/lib/qvos/thunar/codex" ||
  fail "Devel enrolled integration reconciliation"
[[ $(wc -l <"$log") == "$action_count" ]] ||
  fail "Devel reconciliation changed packages or direct tools"

run_devel remove --yes >/dev/null
[[ -f $installed_tools/codex ]] || fail "Devel removed qvOS Codex"
[[ ! -e $test_root/home/.local/state/qvos/development/devel ]] ||
  fail "Devel enrollment removal"
[[ ! -e $test_root/home/.local/lib/qvos/thunar/codex ]] ||
  fail "Devel workbench integration removal"
[[ $(grep $'^tool-remove' "$log" | tail -n 5) == \
  $'tool-remove\tplaywright-cli\ntool-remove\tdevcontainer\ntool-remove\tsemgrep\ntool-remove\tuv\ntool-remove\tnode' ]] ||
  fail "Devel direct removal dependency order"
[[ -z $(find "$installed_packages" -type f -print -quit) ]] ||
  fail "Devel Pacman removal"

install -d "$test_root/home/.local/state/qvos/qvcore"
install -m 0644 /dev/null "$test_root/home/.local/state/qvos/qvcore/qvdev"
if run_devel invalid >/dev/null 2>&1; then
  fail "Devel invalid action"
fi
[[ -f $test_root/home/.local/state/qvos/qvcore/qvdev &&
  ! -e $test_root/home/.local/state/qvos/development/devel ]] ||
  fail "Devel invalid action migrated enrollment state"

if awk -F '\t' '$1 == "aur" { found = 1 } END { exit !found }' \
  "$root/development/devel/packages.tsv"; then
  fail "Devel unexpectedly owns AUR packages"
fi
if rg -q 'python@latest|wrangler|convex|@playwright/test' \
  "$root/development/devel/manage" \
  "$root/development/devel/packages.tsv" \
  "$root/qvcore/direct/manifest.tsv"; then
  fail "Devel violates Python or project-local boundaries"
fi
grep -Fqx $'playwright-cli\tdevel\tPlaywright CLI\tnpm\tplaywright-cli\t@playwright/cli\t-\t-\t-' \
  "$root/qvcore/direct/manifest.tsv" ||
  fail "Devel Playwright CLI ownership"

printf 'ok - Devel preserves qvOS Codex while owning its workbench integration\n'
