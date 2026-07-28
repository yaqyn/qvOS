#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
action_log="$test_root/actions.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$source_root/qv/core"
cp "$root/qv/core/catalog.tsv" "$source_root/qv/core/catalog.tsv"
cp "$root/qv/core/install" "$source_root/qv/core/install"
cp "$root/qv/core/remove" "$source_root/qv/core/remove"

while IFS=$'\t' read -r component _label _icon _extra; do
  [[ -n $component && $component != "#"* ]] || continue
  install -m 0755 /dev/stdin "$source_root/qv/core/$component.sh" <<'SCRIPT'
#!/bin/bash
printf '%s\t%s\t%s\n' "${0##*/}" "${1:-}" "${2:-}" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
done <"$root/qv/core/catalog.tsv"

run_install() {
  HOME="$test_root/home" \
    OMARCHY_PATH="$source_root" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$root/bin/omarchy-install-qvcore" "$@"
}

run_remove() {
  HOME="$test_root/home" \
    OMARCHY_PATH="$source_root" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$root/bin/omarchy-qvcore-remove" "$@"
}

for component in warp share proton brave media qvdev; do
  run_install "$component"
  [[ $(tail -n 1 "$action_log") == "$component.sh"$'\tinstall\t' ]] ||
    fail "Install route: $component"
  run_remove "$component" --yes
  [[ $(tail -n 1 "$action_log") == "$component.sh"$'\tremove\t--yes' ]] ||
    fail "Remove route: $component"
done

for retired in "" all apps setups dev codex brave-origin; do
  if run_install "$retired" >/dev/null 2>&1; then
    fail "retired Install route accepted: ${retired:-empty}"
  fi
done
if run_remove qvdev --check >/dev/null 2>&1; then
  fail "retired removal preflight mode accepted"
fi

printf 'ok - qvCORE routes exactly six stacks through Install and Remove\n'
