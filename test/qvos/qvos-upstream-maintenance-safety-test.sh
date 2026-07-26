#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
test_home="$test_root/home"
action_log="$test_root/actions.log"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

mkdir -p "$test_bin" "$test_home"
touch "$action_log"

install -m 0755 /dev/stdin "$test_bin/blocked-action" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$(basename "$0")" >>"$QVOS_TEST_ACTION_LOG"
exit 97
SCRIPT

for command in \
  git \
  gum \
  hyprctl \
  omarchy-branch-set \
  omarchy-pkg-drop \
  omarchy-refresh-pacman \
  omarchy-reinstall-configs \
  omarchy-reinstall-git \
  omarchy-reinstall-pkgs \
  omarchy-snapshot \
  omarchy-tui-remove-all \
  omarchy-update-perform \
  omarchy-webapp-remove-all \
  pacman \
  sudo; do
  ln -s blocked-action "$test_bin/$command"
done

export QVOS_TEST_ACTION_LOG="$action_log"

blocked_commands=(
  "omarchy-remove-preinstalls|omarchy remove preinstalls|"
  "omarchy-reinstall|omarchy reinstall|"
  "omarchy-reinstall-git|omarchy reinstall git|"
  "omarchy-reinstall-pkgs|omarchy reinstall pkgs|"
  "omarchy-reinstall-configs|omarchy reinstall configs|"
  "omarchy-branch-set|omarchy branch set|master"
  "omarchy-channel-set|omarchy channel set|stable"
  "omarchy-update-branch|omarchy update branch|master"
)

for command_spec in "${blocked_commands[@]}"; do
  IFS='|' read -r binary route argument <<<"$command_spec"

  set +e
  output=$(
    HOME="$test_home" \
      OMARCHY_PATH="$root" \
      PATH="$test_bin:/usr/bin:/bin" \
      "$root/bin/$binary" ${argument:+"$argument"} 2>&1
  )
  status=$?
  set -e

  (( status == 1 )) || fail "$route exits with the qvOS safety status"
  grep -Fq "Blocked on qvOS: $route" <<<"$output" ||
    fail "$route explains the qvOS block"
  grep -Fq 'Use "omarchy qvos repair" for the base' <<<"$output" ||
    fail "$route identifies the safe qvOS replacement"
done

[[ ! -s $action_log ]] || fail "blocked routes reached upstream actions"
pass "upstream reset, reinstall, branch, and channel routes fail before mutation"

missing_guard_root="$test_root/missing-guard"
mkdir -p "$missing_guard_root/qv"

set +e
missing_guard_output=$(
  HOME="$test_home" \
    OMARCHY_PATH="$missing_guard_root" \
    PATH="$test_bin:/usr/bin:/bin" \
    "$root/bin/omarchy-remove-preinstalls" 2>&1
)
missing_guard_status=$?
set -e

(( missing_guard_status == 1 )) || fail "missing qvOS guard fails closed"
grep -Fq 'Blocked on qvOS: the maintenance safety guard is unavailable' \
  <<<"$missing_guard_output" || fail "missing qvOS guard explains the safety block"
[[ ! -s $action_log ]] || fail "missing qvOS guard reached upstream actions"
pass "a partial qvOS checkout cannot re-enable upstream maintenance"

visible_commands=$("$root/bin/omarchy" commands --json)
all_commands=$("$root/bin/omarchy" commands --all --json)

for command_spec in "${blocked_commands[@]}"; do
  IFS='|' read -r binary _ _ <<<"$command_spec"

  jq -e --arg binary "$binary" \
    'all(.commands[]; .binary != $binary)' <<<"$visible_commands" >/dev/null ||
    fail "$binary remains visible in normal command discovery"
  jq -e --arg binary "$binary" \
    'any(.commands[]; .binary == $binary and .hidden == true and (.summary | startswith("Unavailable on qvOS:")))' \
    <<<"$all_commands" >/dev/null ||
    fail "$binary is not documented as a hidden qvOS block"
done
pass "blocked routes are hidden from normal command discovery"

for binary in \
  omarchy-pkg-remove \
  omarchy-refresh-hyprland \
  omarchy-snapshot \
  omarchy-update; do
  jq -e --arg binary "$binary" \
    'any(.commands[]; .binary == $binary)' <<<"$visible_commands" >/dev/null ||
    fail "$binary was hidden with the incompatible upstream workflows"
done
pass "targeted qvOS maintenance routes remain discoverable"

if grep -Fq 'Preinstalls' "$root/bin/omarchy-menu"; then
  fail "Remove menu still exposes upstream preinstall removal"
fi

if grep -Fq 'omarchy-channel-set' "$root/bin/omarchy-menu" ||
  grep -Fq 'show_update_channel_menu' "$root/bin/omarchy-menu"; then
  fail "Update menu still exposes upstream channel switching"
fi
pass "qvOS menus hide incompatible upstream maintenance workflows"
