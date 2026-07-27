#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
repair="$root/qv/maintenance/qvos-repair"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
missing_packages="$test_root/missing-packages"
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
  "$missing_packages"
touch "$action_log" "$missing_packages/alacritty"
printf 'custom bindings\n' >"$test_home/.config/hypr/qv/bindings.conf"

install -m 0755 /dev/stdin "$test_bin/git" <<'SCRIPT'
#!/bin/bash
[[ $* == *"branch --show-current"* ]] || exit 2
printf '%s\n' "${QVOS_TEST_BRANCH:-OS}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
for package in "$@"; do
  [[ ! -f $QVOS_TEST_MISSING_PACKAGES/$package ]] || exit 1
done
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'add\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
for package in "$@"; do
  rm -f "$QVOS_TEST_MISSING_PACKAGES/$package"
done
SCRIPT

install -m 0755 /dev/stdin "$test_bin/localsend" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
reload) printf 'hyprland\treload\n' >>"$QVOS_TEST_ACTION_LOG" ;;
configerrors) ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-restart-waybar" <<'SCRIPT'
#!/bin/bash
printf 'waybar\trestart\n' >>"$QVOS_TEST_ACTION_LOG"
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
    QVOS_TEST_MISSING_PACKAGES="$missing_packages" \
    QVOS_TEST_BRANCH="${QVOS_TEST_BRANCH:-OS}" \
    QVOS_TEST_GUM_SELECTION="${QVOS_TEST_GUM_SELECTION:-}" \
    HOME="$test_home" \
    OMARCHY_PATH="$root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$repair" "$@"
}

run_health() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_MISSING_PACKAGES="$missing_packages" \
    QVOS_TEST_BRANCH="${QVOS_TEST_BRANCH:-OS}" \
    HOME="$test_home" \
    OMARCHY_PATH="$root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/omarchy-qvos-health" "$@"
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

inspection_output=$(run_repair --status)
grep -Fq 'Removed default packages:    1' <<<"$inspection_output" ||
  fail "qvOS inspection removed-default count"
grep -Fq 'qvOS-owned runtime:          Needs repair' <<<"$inspection_output" ||
  fail "qvOS inspection runtime status"
grep -Fq 'qvOS needs repair; no changes were made.' <<<"$inspection_output" ||
  fail "qvOS inspection result"
[[ -e $missing_packages/alacritty ]] ||
  fail "qvOS inspection reinstalls a removed default"
[[ ! -s $action_log ]] || fail "qvOS inspection mutates the system"
set +e
check_output=$(run_repair --status --check 2>&1)
check_status=$?
set -e
((check_status == 1)) || fail "unhealthy qvOS check status"
[[ $check_output == "$inspection_output" ]] ||
  fail "qvOS status and check inventory differ"
public_health_output=$(run_health)
[[ $public_health_output == "$inspection_output" ]] ||
  fail "public qvOS health inventory"
set +e
run_health --check >/dev/null 2>&1
public_check_status=$?
set -e
((public_check_status == 1)) || fail "public qvOS health check status"
if run_health unknown >/dev/null 2>&1; then
  fail "unknown public qvOS health argument succeeds"
fi
if run_health --check extra >/dev/null 2>&1; then
  fail "extra public qvOS health argument succeeds"
fi
pass "qvOS health reports drift successfully while check gates automation"

repair_output=$(
  QVOS_TEST_GUM_SELECTION="Safe repair — preserve removed packages and customized config" \
    run_repair
)
if grep -Fqx $'add\talacritty' "$action_log"; then
  fail "safe qvOS repair reinstalls a removed default package"
fi
[[ -e $missing_packages/alacritty ]] ||
  fail "safe qvOS repair changes removed-default state"
grep -Fq 'preserved 1 removed default package' <<<"$repair_output" ||
  fail "safe qvOS repair removed-default result"
if grep -Fq 'qvCORE Managed Setups' <<<"$repair_output"; then
  fail "qvOS repair invokes qvCORE setup health"
fi
jq -e '."custom/omarchy".format == "󱅾"' \
  "$test_home/.config/waybar/config.jsonc" >/dev/null ||
  fail "restored Waybar overlay activation"
grep -Fqx $'hyprland\treload' "$action_log" ||
  fail "restored Hyprland config reload"
[[ $(<"$test_home/.config/hypr/qv/bindings.conf") == "custom bindings" ]] ||
  fail "default repair overwrites customized qvOS config"
grep -Fq 'preserved 1 customized qvOS config file' <<<"$repair_output" ||
  fail "custom config preservation result"

for config_path in \
  hypr/qv/looknfeel.conf \
  hypr/qv/windows.conf; do
  cmp -s \
    "$root/qv/config/files/$config_path" \
    "$test_home/.config/$config_path" ||
    fail "missing qvOS config repair: $config_path"
done
[[ ! -e $test_home/.config/refresh ]] ||
  fail "qvOS config helper was installed as user config"
[[ ! -e $test_home/.config/refresh-upstream ]] ||
  fail "upstream refresh helper was installed as user config"
cmp -s \
  "$root/qv/core/post-update-hook" \
  "$test_home/.config/omarchy/hooks/post-update.d/qvos-qvcore" ||
  fail "missing qvCORE post-update hook"
cmp -s \
  "$root/qv/waybar/post-update-hook" \
  "$test_home/.config/omarchy/hooks/post-update.d/qvos-waybar-overrides" ||
  fail "missing qvOS Waybar post-update hook"
[[ -x $test_home/.local/share/qvos/tmux/qvos-tmux ]] ||
  fail "qvOS runtime payload repair"
pass "safe qvOS repair restores owned state without reinstalling removed defaults"

: >"$action_log"
healthy_output=$(run_repair --status)
grep -Fq 'qvOS-owned runtime:          Ready' <<<"$healthy_output" ||
  fail "repaired qvOS runtime health"
grep -Fq 'qvOS is healthy; no changes were made.' <<<"$healthy_output" ||
  fail "healthy qvOS result"
[[ ! -s $action_log ]] || fail "healthy qvOS inspection mutates the system"
pass "qvOS repair produces a healthy base without grading qvCORE software"

mv "$test_bin/omarchy-pkg-add" "$test_bin/omarchy-pkg-add.repair-only"
health_output=$(run_health)
mv "$test_bin/omarchy-pkg-add.repair-only" "$test_bin/omarchy-pkg-add"
grep -Fq 'qvOS is healthy; no changes were made.' <<<"$health_output" ||
  fail "qvOS health public command"
pass "qvOS health delegates to inspection without requiring a mutation owner"

: >"$action_log"
run_repair --reset --yes >/dev/null
grep -Fqx $'add\talacritty' "$action_log" ||
  fail "explicit qvOS package restore"
[[ ! -e $missing_packages/alacritty ]] ||
  fail "explicit qvOS package restore verification"
cmp -s \
  "$root/qv/config/files/hypr/qv/bindings.conf" \
  "$test_home/.config/hypr/qv/bindings.conf" ||
  fail "explicit qvOS config restore"
compgen -G "$test_home/.config/hypr/qv/bindings.conf.bak.*" >/dev/null ||
  fail "explicit qvOS config restore backup"
grep -Fqx $'hyprland\treload' "$action_log" ||
  fail "explicit qvOS config reload"
pass "explicit qvOS defaults restore reinstalls packages and backs up config"

commands=$("$root/bin/omarchy" commands --json)
for binary in \
  omarchy-qvcore-disable \
  omarchy-qvos-health \
  omarchy-qvos-personal-software \
  omarchy-qvos-refresh-waybar \
  omarchy-qvos-repair \
  omarchy-qvos-setup-dns \
  omarchy-qvos-share \
  omarchy-qvos-update-available \
  omarchy-qvos-update; do
  jq -e --arg binary "$binary" \
    'any(.commands[]; .binary == $binary)' <<<"$commands" >/dev/null ||
    fail "$binary command discovery"
done
if jq -e 'any(.commands[]; .binary == "omarchy-qvcore-repair-enabled")' \
  <<<"$commands" >/dev/null; then
  fail "internal qvCORE repair route is publicly listed"
fi
pass "qvOS maintenance commands expose only user-facing routes"

grep -Fq '*Repair*) present_terminal omarchy-qvos-repair ;;' \
  "$root/qv/menu/extension.sh" || fail "qvOS repair menu route"
grep -Fq '*"Personal Software"*) present_terminal "omarchy-qvos-personal-software --remove" ;;' \
  "$root/qv/menu/extension.sh" || fail "personal-software menu route"
grep -Fq 'exec omarchy-qvos-repair --yes' "$root/qv/tui/bin/qvos-repair" ||
  fail "qvOS TUI repair delegation"
grep -Fq 'exec omarchy-qvos-update -y' "$root/qv/tui/bin/qvos-update" ||
  fail "qvOS TUI update delegation"
pass "qvOS menus and TUI delegate to the maintenance owners"
