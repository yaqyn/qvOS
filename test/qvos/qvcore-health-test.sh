#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
health="$root/qv/core/health.sh"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
fixture="$test_root/omarchy"
state="$test_root/state"
repair_log="$test_root/repair.log"
lifecycle_log="$test_root/lifecycle.log"

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

install -d \
  "$test_bin" \
  "$fixture/qv/core/dev" \
  "$state/commands" \
  "$state/packages" \
  "$test_root/.config/hypr/qv" \
  "$test_root/.config/omarchy/hooks/post-update.d" \
  "$test_root/.local/state/qvos/qvcore"

for component in share dev codex proton; do
  install -m 0755 /dev/stdin "$fixture/qv/core/$component.sh" <<'SCRIPT'
#!/bin/bash
component=$(basename "$0" .sh)
state_file="$HOME/.local/state/qvos/qvcore/$component"
case ${1:-} in
--status | --integration-status)
  [[ -f $state_file && -f $QVOS_TEST_HEALTH_STATE/ready-$component ]]
  ;;
--repair)
  printf 'repair\t%s\n' "$component" >>"$QVOS_TEST_HEALTH_LIFECYCLE_LOG"
  install -m 0644 /dev/null "$QVOS_TEST_HEALTH_STATE/ready-$component"
  [[ -f $state_file ]]
  ;;
--update)
  printf 'update\t%s\n' "$component" >>"$QVOS_TEST_HEALTH_LIFECYCLE_LOG"
  [[ -f $state_file && -f $QVOS_TEST_HEALTH_STATE/ready-$component ]]
  ;;
--disable)
  printf 'disable\t%s\n' "$component" >>"$QVOS_TEST_HEALTH_LIFECYCLE_LOG"
  rm -f "$state_file"
  ;;
*)
  exit 2
  ;;
esac
SCRIPT
  install -m 0644 /dev/null "$state/ready-$component"
  install -m 0644 /dev/null \
    "$test_root/.local/state/qvos/qvcore/$component"
done

install -m 0755 /dev/stdin "$fixture/qv/core/media.sh" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "--status" ]] || exit 2
count=$(<"$QVOS_TEST_HEALTH_STATE/media-count")
printf 'qvCORE Media inventory: %s/7 ready\n' "$count"
((count > 0))
SCRIPT
printf '7\n' >"$state/media-count"

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_HEALTH_STATE/commands/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_HEALTH_STATE/packages/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-default-browser" <<'SCRIPT'
#!/bin/bash
printf 'brave-origin\n'
SCRIPT

install -m 0755 /dev/stdin "$test_bin/warp-cli" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_HEALTH_STATE/warp-registered ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
choose) printf '%s\n' "${QVOS_TEST_HEALTH_CHOICE:-share}" ;;
confirm) [[ ${QVOS_TEST_HEALTH_CONFIRM:-1} == "1" ]] ;;
*) exit 1 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-install-qvcore" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_HEALTH_REPAIR_LOG"
SCRIPT

for command in warp-cli localsend codex proton-drive bun supabase; do
  install -m 0644 /dev/null "$state/commands/$command"
done
for package in \
  brave-origin-beta-bin \
  steam \
  gimp \
  inkscape \
  krita \
  kdenlive \
  obs-studio \
  audacity \
  blender; do
  install -m 0644 /dev/null "$state/packages/$package"
done
install -m 0644 /dev/null "$state/warp-registered"

printf '%s\n' 'windowrule = workspace name:G silent, class:^(steam)$' \
  >"$test_root/.config/hypr/qv/windows.conf"
printf '%s\n' 'bindd = SUPER CTRL, grave, Steam, exec, steam' \
  >"$test_root/.config/hypr/qv/bindings.conf"

run_health() {
  QVOS_TEST_HEALTH_CHOICE="${QVOS_TEST_HEALTH_CHOICE:-share}" \
    QVOS_TEST_HEALTH_CONFIRM="${QVOS_TEST_HEALTH_CONFIRM:-1}" \
    QVOS_TEST_HEALTH_LIFECYCLE_LOG="$lifecycle_log" \
    QVOS_TEST_HEALTH_REPAIR_LOG="$repair_log" \
    QVOS_TEST_HEALTH_STATE="$state" \
    HOME="$test_root" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    "$health" "$@"
}

ready_output=$(run_health status)
grep -Fq 'Ready: 8  Partial: 0  Disabled: 0  Missing: 0' <<<"$ready_output" ||
  fail "all-ready qvCORE health summary"
pass "qvCORE health reports every complete component"

rm -f \
  "$state/ready-share" \
  "$state/ready-codex" \
  "$state/commands/codex" \
  "$state/warp-registered"
printf '6\n' >"$state/media-count"

drift_output=$(run_health status)
grep -Fq 'Ready: 5  Partial: 2  Disabled: 1  Missing: 0' <<<"$drift_output" ||
  fail "mixed qvCORE health summary"
grep -Fq 'Share          partial' <<<"$drift_output" ||
  fail "Share drift status"
grep -Fq 'Codex          disabled' <<<"$drift_output" ||
  fail "Codex removed status"
pass "qvCORE health distinguishes missing components from integration drift"

rm -f "$test_root/.local/state/qvos/qvcore/share"
disabled_output=$(run_health status)
grep -Fq 'Share          disabled' <<<"$disabled_output" ||
  fail "Share disabled status"
grep -Fq 'Ready: 5  Partial: 1  Disabled: 2  Missing: 0' <<<"$disabled_output" ||
  fail "disabled qvCORE health summary"
pass "qvCORE health distinguishes intentional disablement from drift"

for state_path in \
  "$test_root/.local/state/qvos/qvcore/share" \
  "$state/ready-share" \
  "$state/ready-codex" \
  "$state/warp-registered" \
  "$state/commands/codex"; do
  install -m 0644 /dev/null "$state_path"
done

for component in share dev codex proton; do
  install -m 0644 /dev/null \
    "$test_root/.config/omarchy/hooks/post-update.d/qvos-qvcore-$component"
done
rm -f "$state/ready-share"
: >"$lifecycle_log"
update_output=$(run_health update)
grep -Fq 'qvCORE needs attention:' <<<"$update_output" ||
  fail "update drift heading"
grep -Fq 'Share — enabled integration drift' <<<"$update_output" ||
  fail "update drift detail"
if grep -Eq 'WARP|Brave|Media|Steam|Codex —|Proton —|Devel —' \
  <<<"$update_output"; then
  fail "update prints healthy or untracked qvCORE components"
fi
grep -Fqx $'repair\tshare' "$lifecycle_log" ||
  fail "update Share repair"
grep -Fqx $'update\tdev' "$lifecycle_log" ||
  fail "update Devel refresh"
grep -Fq 'qvCORE is ready.' <<<"$update_output" ||
  fail "update ready summary"
for component in share dev codex proton; do
  [[ ! -e $test_root/.config/omarchy/hooks/post-update.d/qvos-qvcore-$component ]] ||
    fail "$component legacy hook cleanup"
done
pass "qvCORE update shows only actionable drift and repairs on confirmation"

rm -f "$state/ready-codex"
: >"$lifecycle_log"
declined_output=$(QVOS_TEST_HEALTH_CONFIRM=0 run_health update)
grep -Fq 'Codex — enabled integration drift' <<<"$declined_output" ||
  fail "declined update drift detail"
if grep -Fq $'repair\tcodex' "$lifecycle_log"; then
  fail "declined update repairs Codex"
fi
grep -Fq 'qvCORE repair skipped.' <<<"$declined_output" ||
  fail "declined update guidance"
install -m 0644 /dev/null "$state/ready-codex"
pass "qvCORE update leaves repair under explicit user control"

QVOS_TEST_HEALTH_CHOICE=share run_health repair >/dev/null
[[ $(<"$repair_log") == "share" ]] ||
  fail "qvCORE repair delegates to the existing component route"
pass "qvCORE repair reuses the independently rerunnable installer"

: >"$lifecycle_log"
run_health repair-enabled >/dev/null
[[ $(grep -c '^repair' "$lifecycle_log") == "4" ]] ||
  fail "enabled qvCORE repair count"
for component in share dev codex proton; do
  grep -Fqx $'repair\t'"$component" "$lifecycle_log" ||
    fail "$component enabled repair"
done
pass "qvCORE repairs only lifecycle-enabled integrations"

: >"$lifecycle_log"
QVOS_TEST_HEALTH_CHOICE=all run_health disable >/dev/null
[[ $(grep -c '^disable' "$lifecycle_log") == "4" ]] ||
  fail "qvCORE disable-all count"
for component in share dev codex proton; do
  [[ ! -e $test_root/.local/state/qvos/qvcore/$component ]] ||
    fail "$component enabled state remains"
done
pass "qvCORE disables every integration while preserving installed components"

install -m 0644 /dev/null \
  "$test_root/.local/state/qvos/qvcore/share"
install -m 0644 /dev/null "$state/ready-share"
rm -f "$state/commands/localsend"
: >"$lifecycle_log"
removed_output=$(run_health update)
[[ ! -e $test_root/.local/state/qvos/qvcore/share ]] ||
  fail "removed Share application remains enabled"
grep -Fqx $'disable\tshare' "$lifecycle_log" ||
  fail "removed Share integration retirement"
if grep -Fq 'qvCORE needs attention:' <<<"$removed_output"; then
  fail "removed Share application reports damage"
fi
grep -Fq 'qvCORE is ready.' <<<"$removed_output" ||
  fail "removed Share ready summary"
pass "qvCORE update treats application removal as user intent"

: >"$lifecycle_log"
subset_output=$(run_health update)
[[ ! -s $lifecycle_log ]] ||
  fail "untracked GIMP or Supabase triggers qvCORE maintenance"
grep -Fq 'qvCORE is ready.' <<<"$subset_output" ||
  fail "untracked subset ready summary"
pass "standalone GIMP and Supabase installs create no qvCORE update work"

if run_health unknown >/dev/null 2>&1; then
  fail "unknown qvCORE health mode succeeds"
fi
pass "qvCORE health rejects unknown modes without mutation"
