#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
repair="$root/qv/maintenance/qvos-repair"
cleanup_command="$root/qv/maintenance/qvos-cleanup-inherited"
catalog="$root/qv/maintenance/inherited-extras.tsv"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
missing_packages="$test_root/missing-packages"
installed_extras="$test_root/installed-extras"
action_log="$test_root/actions.log"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_home/.config/hypr/qv" \
  "$test_bin" \
  "$missing_packages" \
  "$installed_extras"
touch "$action_log" "$missing_packages/alacritty"
printf 'custom bindings\n' >"$test_home/.config/hypr/qv/bindings.conf"

install -m 0755 /dev/stdin "$test_bin/git" <<'SCRIPT'
#!/bin/bash
[[ $* == *"branch --show-current"* ]] || exit 2
printf '%s\n' "${QVOS_TEST_BRANCH:-OS}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
case $1 in
1password-beta | 1password-cli | aether | claude-code | opencode | cliamp | libreoffice-fresh | pinta | signal-desktop | spotify | typora | xournalpp)
  [[ -f $QVOS_TEST_INSTALLED_EXTRAS/$1 ]]
  ;;
*)
  [[ ! -f $QVOS_TEST_MISSING_PACKAGES/$1 ]]
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'add\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
for package in "$@"; do
  rm -f "$QVOS_TEST_MISSING_PACKAGES/$package"
done
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
printf 'drop\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
for package in "$@"; do
  rm -f "$QVOS_TEST_INSTALLED_EXTRAS/$package"
done
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-qvcore-repair-enabled" <<'SCRIPT'
#!/bin/bash
printf 'qvcore\trepair-enabled\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-refresh-waybar" <<'SCRIPT'
#!/bin/bash
printf 'waybar\trefresh\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
reload) printf 'hyprland\treload\n' >>"$QVOS_TEST_ACTION_LOG" ;;
configerrors) ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
choose) printf '%s\n' "${QVOS_TEST_GUM_SELECTION:-}" ;;
confirm) [[ ${QVOS_TEST_GUM_CONFIRM:-1} == "1" ]] ;;
*) exit 2 ;;
esac
SCRIPT

run_repair() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_INSTALLED_EXTRAS="$installed_extras" \
    QVOS_TEST_MISSING_PACKAGES="$missing_packages" \
    QVOS_TEST_BRANCH="${QVOS_TEST_BRANCH:-OS}" \
    HOME="$test_home" \
    OMARCHY_PATH="$root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$repair" "$@"
}

run_cleanup() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_GUM_CONFIRM="${QVOS_TEST_GUM_CONFIRM:-1}" \
    QVOS_TEST_GUM_SELECTION="${QVOS_TEST_GUM_SELECTION:-}" \
    QVOS_TEST_INSTALLED_EXTRAS="$installed_extras" \
    QVOS_TEST_MISSING_PACKAGES="$missing_packages" \
    HOME="$test_home" \
    OMARCHY_PATH="$root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$cleanup_command" "$@"
}

set +e
unsafe_output=$(QVOS_TEST_BRANCH=master run_repair --yes 2>&1)
unsafe_status=$?
set -e
((unsafe_status == 1)) || fail "repair accepts a non-OS source branch"
grep -Fq "requires the live qvOS checkout on branch OS" <<<"$unsafe_output" ||
  fail "repair branch refusal"
[[ ! -s $action_log ]] || fail "branch refusal mutates the system"
pass "qvOS repair refuses an upstream source branch before mutation"

repair_output=$(run_repair --yes)
grep -Fqx $'add\talacritty' "$action_log" ||
  fail "missing qvOS base package repair"
grep -Fqx $'qvcore\trepair-enabled' "$action_log" ||
  fail "enabled qvCORE repair delegation"
grep -Fqx $'waybar\trefresh' "$action_log" ||
  fail "restored Waybar overlay activation"
grep -Fqx $'hyprland\treload' "$action_log" ||
  fail "restored Hyprland config reload"
[[ $(<"$test_home/.config/hypr/qv/bindings.conf") == "custom bindings" ]] ||
  fail "default repair overwrites customized qvOS config"
grep -Fq 'preserved 1 customized qvOS config file' <<<"$repair_output" ||
  fail "custom config preservation result"

for config_path in \
  hypr/qv/looknfeel.conf \
  hypr/qv/windows.conf \
  omarchy/hooks/post-update.d/qvos-qvcore \
  omarchy/hooks/post-update.d/qvos-waybar-overrides \
  waybar/qv/overrides.jsonc; do
  cmp -s \
    "$root/config/$config_path" \
    "$test_home/.config/$config_path" ||
    fail "missing qvOS config repair: $config_path"
done
[[ -x $test_home/.local/share/qvos/tmux/qvos-tmux ]] ||
  fail "qvOS runtime payload repair"
pass "qvOS repair restores only missing base state and enabled integrations"

: >"$action_log"
run_repair --restore-config --yes >/dev/null
cmp -s \
  "$root/config/hypr/qv/bindings.conf" \
  "$test_home/.config/hypr/qv/bindings.conf" ||
  fail "explicit qvOS config restore"
compgen -G "$test_home/.config/hypr/qv/bindings.conf.bak.*" >/dev/null ||
  fail "explicit qvOS config restore backup"
grep -Fqx $'hyprland\treload' "$action_log" ||
  fail "explicit qvOS config reload"
pass "explicit config restoration keeps a timestamped backup"

active_packages=$(
  sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' \
    "$root/install/omarchy-base.packages"
)
while IFS=$'\t' read -r category package description; do
  [[ -n $category && $category != "#"* ]] || continue
  [[ -n $description ]] || fail "inherited-extra catalog description"
  if grep -Fqx "$package" <<<"$active_packages"; then
    fail "active qvOS base package appears in inherited-extra catalog: $package"
  fi
done <"$catalog"
pass "inherited-extra catalog cannot target the active qvOS base"

touch "$installed_extras/1password-beta" "$installed_extras/claude-code"
: >"$action_log"
preview_output=$(run_cleanup --status)
grep -Fq 'Detected 2 reviewed candidate(s)' <<<"$preview_output" ||
  fail "inherited-extra preview count"
grep -Fq 'never changes bindings, config files, web apps, or TUI launchers' \
  <<<"$preview_output" || fail "inherited-extra scope statement"
[[ ! -s $action_log ]] || fail "inherited-extra preview mutates packages"
pass "inherited-extra cleanup is read-only by default"

QVOS_TEST_GUM_SELECTION=1password-beta run_cleanup --apply >/dev/null
grep -Fqx $'drop\t1password-beta' "$action_log" ||
  fail "selected inherited-extra removal"
[[ ! -e $installed_extras/1password-beta ]] ||
  fail "selected inherited extra remains"
[[ -e $installed_extras/claude-code ]] ||
  fail "unselected inherited extra was removed"
pass "inherited-extra cleanup removes only an explicitly selected package"

commands=$("$root/bin/omarchy" commands --json)
for binary in \
  omarchy-qvcore-disable \
  omarchy-qvos-cleanup-inherited \
  omarchy-qvos-repair; do
  jq -e --arg binary "$binary" \
    'any(.commands[]; .binary == $binary)' <<<"$commands" >/dev/null ||
    fail "$binary command discovery"
done
if jq -e \
  'any(.commands[]; .binary == "omarchy-qvcore-repair-enabled")' \
  <<<"$commands" >/dev/null; then
  fail "internal qvCORE repair route is publicly listed"
fi
pass "qvOS maintenance commands expose only user-facing routes"

grep -Fq '*Repair*) present_terminal omarchy-qvos-repair ;;' \
  "$root/bin/omarchy-menu" || fail "qvOS repair menu route"
grep -Fq '*Extras*) present_terminal "omarchy-qvos-cleanup-inherited --apply" ;;' \
  "$root/bin/omarchy-menu" || fail "inherited-extra menu route"
grep -Fq 'exec omarchy-qvos-repair' "$root/qv/tui/bin/qvos-repair" ||
  fail "qvOS TUI repair delegation"
pass "qvOS menus and TUI delegate to the maintenance owners"
