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
  "$source_root/qv/core/qvdev" \
  "$source_root/qv/direct" \
  "$source_root/qv/thunar" \
  "$test_bin" \
  "$installed_packages" \
  "$installed_tools" \
  "$(dirname -- "$thunar_config")"
cp "$root/qv/core/qvdev.sh" "$source_root/qv/core/qvdev.sh"
cp "$root/qv/core/qvdev/packages.tsv" "$source_root/qv/core/qvdev/packages.tsv"
cp "$root/qv/thunar/actions.sh" "$source_root/qv/thunar/actions.sh"
cp "$root/qv/thunar/codex" "$source_root/qv/thunar/codex"
printf '<?xml version="1.0" encoding="UTF-8"?><actions/>\n' >"$thunar_config"

install -m 0755 /dev/stdin "$source_root/qv/direct/tool" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
action=$1
target=$2
case $action in
list-scope)
  [[ $target == "qvdev" ]] &&
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

for name in omarchy-pkg-present omarchy-pkg-missing omarchy-pkg-add \
  omarchy-pkg-drop omarchy-cmd-present pacman gum; do
  install -m 0755 /dev/stdin "$test_bin/$name" <<'SCRIPT'
#!/bin/bash
case ${0##*/} in
omarchy-pkg-present) [[ -f $QVOS_TEST_PACKAGES/$1 ]] ;;
omarchy-pkg-missing) [[ ! -f $QVOS_TEST_PACKAGES/$1 ]] ;;
omarchy-pkg-add)
  for package in "$@"; do
    install -m 0644 /dev/null "$QVOS_TEST_PACKAGES/$package"
    printf 'package-add\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
omarchy-pkg-drop)
  for package in "$@"; do
    rm -f "$QVOS_TEST_PACKAGES/$package"
    printf 'package-drop\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
omarchy-cmd-present) exit 0 ;;
pacman | gum) exit 0 ;;
esac
SCRIPT
done

run_qvdev() {
  HOME="$test_root/home" \
    PATH="$test_bin:/usr/bin" \
    QVOS_THUNAR_CONFIG="$thunar_config" \
    QVOS_TEST_PACKAGES="$installed_packages" \
    QVOS_TEST_TOOLS="$installed_tools" \
    QVOS_TEST_LOG="$log" \
    "$source_root/qv/core/qvdev.sh" "$@"
}

install -m 0644 /dev/null "$installed_packages/7zip"
install -m 0644 /dev/null "$installed_tools/codex"
install -m 0644 /dev/null "$installed_tools/node"
run_qvdev install >/dev/null
[[ -f $test_root/home/.local/state/qvos/qvcore/qvdev ]] ||
  fail "qvDEV enrollment"
[[ $(grep -c $'^package-add\t7zip$' "$log" || true) == "0" ]] ||
  fail "qvDEV reinstalls compatible Pacman software"
[[ $(grep -c $'^tool-install\tnode$' "$log" || true) == "0" ]] ||
  fail "qvDEV reinstalls a compatible direct tool"
for tool_id in node uv semgrep devcontainer playwright-cli; do
  [[ -f $installed_tools/$tool_id ]] || fail "qvDEV direct tool: $tool_id"
done
[[ -x $test_root/home/.local/share/qvos/thunar/codex ]] ||
  fail "qvDEV Codex workbench helper"

run_qvdev remove --yes >/dev/null
[[ -f $installed_tools/codex ]] || fail "qvDEV removed Omarchy Codex"
[[ ! -e $test_root/home/.local/state/qvos/qvcore/qvdev ]] ||
  fail "qvDEV enrollment removal"
[[ ! -e $test_root/home/.local/share/qvos/thunar/codex ]] ||
  fail "qvDEV workbench integration removal"
[[ $(grep $'^tool-remove' "$log" | tail -n 5) == \
  $'tool-remove\tplaywright-cli\ntool-remove\tdevcontainer\ntool-remove\tsemgrep\ntool-remove\tuv\ntool-remove\tnode' ]] ||
  fail "qvDEV direct removal dependency order"
[[ -z $(find "$installed_packages" -type f -print -quit) ]] ||
  fail "qvDEV Pacman removal"

if awk -F '\t' '$1 == "aur" { found = 1 } END { exit !found }' \
  "$root/qv/core/qvdev/packages.tsv"; then
  fail "qvDEV unexpectedly owns AUR packages"
fi
if rg -q 'python@latest|wrangler|convex|@playwright/test' \
  "$root/qv/core/qvdev.sh" \
  "$root/qv/core/qvdev/packages.tsv" \
  "$root/qv/direct/manifest.tsv"; then
  fail "qvDEV violates Python or project-local boundaries"
fi
grep -Fqx $'playwright-cli\tqvdev\tPlaywright CLI\tnpm\tplaywright-cli\t@playwright/cli\t-\t-\t-' \
  "$root/qv/direct/manifest.tsv" ||
  fail "qvDEV Playwright CLI ownership"

printf 'ok - qvDEV preserves Omarchy Codex while owning its workbench integration\n'
