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

for owner in \
  services/proton/manage \
  development/devel/manage; do
  install -D -m 0755 /dev/stdin "$source_root/$owner" <<'SCRIPT'
#!/bin/bash
printf '%s\t%s\t%s\n' "${0#*source/}" "${1:-}" "${2:-}" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
done
install -D -m 0755 \
  "$root/compat/omarchy/install-qvcore" \
  "$source_root/compat/omarchy/install-qvcore"
install -D -m 0755 \
  "$root/compat/omarchy/remove-qvcore" \
  "$source_root/compat/omarchy/remove-qvcore"

run_install() {
  OMARCHY_PATH="$source_root" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$root/bin/omarchy-install-qvcore" "$@"
}

run_remove() {
  OMARCHY_PATH="$source_root" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$root/bin/omarchy-qvcore-remove" "$@"
}

for route in proton devel qvdev; do
  run_install "$route"
  expected_owner="development/devel/manage"
  [[ $route == "proton" ]] && expected_owner="services/proton/manage"
  [[ $(tail -n 1 "$action_log") == "$expected_owner"$'\tinstall\t' ]] ||
    fail "compatibility install route: $route"

  run_remove "$route" --yes
  [[ $(tail -n 1 "$action_log") == "$expected_owner"$'\tremove\t--yes' ]] ||
    fail "compatibility remove route: $route"
done

for retired in "" all apps setups brave media share warp dev codex; do
  if run_install "$retired" >/dev/null 2>&1; then
    fail "retired compatibility install route accepted: ${retired:-empty}"
  fi
  if run_remove "$retired" >/dev/null 2>&1; then
    fail "retired compatibility remove route accepted: ${retired:-empty}"
  fi
done

if run_remove devel --check >/dev/null 2>&1; then
  fail "unsupported compatibility removal option accepted"
fi

printf 'ok - former qvCORE commands are thin Proton and Devel compatibility routes\n'
