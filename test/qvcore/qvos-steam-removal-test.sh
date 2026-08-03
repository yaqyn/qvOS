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

install -d "$source_root/bin" "$test_root/home"
install -m 0755 /dev/stdin "$source_root/bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
printf 'package\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$source_root/bin/omarchy-remove-gaming-steam" <<'SCRIPT'
#!/bin/bash
printf 'data\tremove\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

run_owner() {
  HOME="$test_root/home" \
    OMARCHY_PATH="$source_root" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$root/qvcore/menu/steam-remove" "$@"
}

[[ $(run_owner --list) == $'Keep Game Libraries\nRemove Local Game Libraries' ]] ||
  fail "Steam removal scope list"

run_owner -- "Keep Game Libraries" >/dev/null
[[ $(<"$action_log") == $'package\tsteam' ]] ||
  fail "safe Steam removal touched game data"

: >"$action_log"
run_owner -- "Remove Local Game Libraries" >/dev/null
[[ $(<"$action_log") == $'data\tremove' ]] ||
  fail "explicit Steam data removal bypassed the inherited owner"

if run_owner -- "Delete Everything" >/dev/null 2>&1; then
  fail "unknown Steam removal scope"
fi

grep -Fqx \
  'steam|package|steam|tui|true|tui|true|omarchy-install-gaming-steam|qvcore/menu/steam-remove' \
  "$root/qvcore/menu/software-actions.psv" ||
  fail "Steam catalog safe removal owner"
grep -Fqx \
  'steam|uninstall|Remove Steam|action|No Steam removal choices are available.|Remove Local Game Libraries|Remove Steam, local game libraries, settings, and caches|true' \
  "$root/qvcore/tui/action/choices.psv" ||
  fail "Steam destructive scope contract"

printf 'ok - Steam removal preserves game libraries unless explicitly selected\n'
