#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
health="$root/qv/core/health.sh"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
fixture="$test_root/omarchy"
state="$test_root/state"
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
  "$fixture/qv/core" \
  "$state/commands" \
  "$test_root/.config/omarchy/hooks/post-update.d" \
  "$test_root/.local/state/qvos/qvcore"
touch "$lifecycle_log"

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
done

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_HEALTH_STATE/commands/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
choose) printf '%s\n' "${QVOS_TEST_HEALTH_CHOICE:-all}" ;;
confirm) [[ ${QVOS_TEST_HEALTH_CONFIRM:-1} == "1" ]] ;;
*) exit 1 ;;
esac
SCRIPT

run_health() {
  QVOS_TEST_HEALTH_CHOICE="${QVOS_TEST_HEALTH_CHOICE:-all}" \
    QVOS_TEST_HEALTH_CONFIRM="${QVOS_TEST_HEALTH_CONFIRM:-1}" \
    QVOS_TEST_HEALTH_LIFECYCLE_LOG="$lifecycle_log" \
    QVOS_TEST_HEALTH_STATE="$state" \
    HOME="$test_root" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    "$health" "$@"
}

enable_all_setups() {
  local component

  for component in share dev codex proton; do
    install -m 0644 /dev/null \
      "$test_root/.local/state/qvos/qvcore/$component"
    install -m 0644 /dev/null "$state/ready-$component"
  done
  for command in localsend bun codex proton-drive; do
    install -m 0644 /dev/null "$state/commands/$command"
  done
}

install -m 0644 /dev/null "$state/commands/gimp"
install -m 0644 /dev/null "$state/commands/supabase"

empty_update=$(run_health update)
[[ -z $empty_update ]] ||
  fail "unused qvCORE update output"
[[ ! -s $lifecycle_log ]] ||
  fail "unused qvCORE update action"
[[ $(run_health enabled-count) == "0" ]] ||
  fail "unused qvCORE enabled count"
grep -Fq 'No qvCORE setups are enabled.' <<<"$(run_health status)" ||
  fail "unused qvCORE status"
pass "qvCORE stays silent during qvOS updates when no setup is enabled"

enable_all_setups
ready_output=$(run_health status)
grep -Fq 'Enabled qvCORE setups are ready.' <<<"$ready_output" ||
  fail "enabled qvCORE ready summary"
if grep -Eq 'WARP|Brave|Steam|Media|Share|Devel|Codex|Proton' \
  <<<"${ready_output//Enabled qvCORE setups/}"; then
  fail "healthy qvCORE status prints a catalog"
fi
[[ $(run_health enabled-count) == "4" ]] ||
  fail "enabled qvCORE count"
pass "qvCORE health summarizes only enabled persistent setups"

rm -f "$state/ready-share"
set +e
drift_output=$(run_health status 2>&1)
drift_status=$?
set -e
((drift_status == 1)) ||
  fail "qvCORE drift status succeeds"
grep -Fq 'Enabled qvCORE setups need attention:' <<<"$drift_output" ||
  fail "qvCORE drift heading"
grep -Fq 'Share — enabled setup integration drift' <<<"$drift_output" ||
  fail "qvCORE Share drift"
if grep -Eq 'Devel —|Codex —|Proton —|WARP|Brave|Steam|Media' \
  <<<"$drift_output"; then
  fail "qvCORE health prints healthy or unselected setups"
fi
pass "qvCORE health reports only actionable enabled setup drift"

: >"$lifecycle_log"
repair_output=$(run_health repair)
grep -Fqx $'repair\tshare' "$lifecycle_log" ||
  fail "qvCORE interactive Share repair"
[[ $(grep -c '^repair' "$lifecycle_log") == "1" ]] ||
  fail "qvCORE interactive repair touches healthy setups"
grep -Fq 'Enabled qvCORE setups are ready.' <<<"$repair_output" ||
  fail "qvCORE interactive repair completion"
pass "qvCORE repair fixes drift without installing catalog entries"

rm -f "$state/ready-codex"
: >"$lifecycle_log"
set +e
declined_output=$(QVOS_TEST_HEALTH_CONFIRM=0 run_health repair 2>&1)
declined_status=$?
set -e
((declined_status == 130)) ||
  fail "declined qvCORE repair status"
[[ ! -s $lifecycle_log ]] ||
  fail "declined qvCORE repair action"
grep -Fq 'qvCORE repair canceled.' <<<"$declined_output" ||
  fail "declined qvCORE repair result"
install -m 0644 /dev/null "$state/ready-codex"
pass "qvCORE repair cancellation remains explicit and non-mutating"

rm -f "$state/ready-proton"
: >"$lifecycle_log"
automatic_output=$(run_health repair-enabled)
grep -Fqx $'repair\tproton' "$lifecycle_log" ||
  fail "automatic qvCORE Proton repair"
[[ $(grep -c '^repair' "$lifecycle_log") == "1" ]] ||
  fail "automatic qvCORE repair touches healthy setups"
grep -Fq 'Enabled qvCORE setups are ready.' <<<"$automatic_output" ||
  fail "automatic qvCORE repair completion"
pass "qvOS repair preserves only affected enabled qvCORE setups"

rm -f "$state/ready-share"
: >"$lifecycle_log"
update_output=$(run_health update)
grep -Fqx $'update\tdev' "$lifecycle_log" ||
  fail "qvCORE update Devel refresh"
grep -Fqx $'repair\tshare' "$lifecycle_log" ||
  fail "qvCORE update Share repair"
[[ $(grep -c '^repair' "$lifecycle_log") == "1" ]] ||
  fail "qvCORE update repairs healthy setups"
grep -Fq 'Share — enabled setup integration drift' <<<"$update_output" ||
  fail "qvCORE update drift detail"
grep -Fq 'Enabled qvCORE setups are ready.' <<<"$update_output" ||
  fail "qvCORE update ready summary"
pass "qvCORE update refreshes Devel and repairs only actionable drift"

rm -f "$state/commands/localsend"
: >"$lifecycle_log"
removed_output=$(run_health update)
[[ ! -e $test_root/.local/state/qvos/qvcore/share ]] ||
  fail "removed Share setup remains tracked"
grep -Fqx $'disable\tshare' "$lifecycle_log" ||
  fail "removed Share setup retirement"
if grep -Fq 'need attention' <<<"$removed_output"; then
  fail "removed Share application reports damage"
fi
grep -Fq 'Enabled qvCORE setups are ready.' <<<"$removed_output" ||
  fail "remaining enabled qvCORE ready summary"
pass "qvCORE update treats application removal as user intent"

for component in dev codex proton; do
  rm -f "$test_root/.local/state/qvos/qvcore/$component"
done
: >"$lifecycle_log"
subset_output=$(run_health update)
[[ -z $subset_output ]] ||
  fail "untracked optional application update output"
[[ ! -s $lifecycle_log ]] ||
  fail "untracked optional application update action"
pass "standalone GIMP and Supabase installs create no qvCORE update work"

enable_all_setups
: >"$lifecycle_log"
disable_output=$(QVOS_TEST_HEALTH_CHOICE=all run_health disable)
[[ $(grep -c '^disable' "$lifecycle_log") == "4" ]] ||
  fail "qvCORE disable-all count"
for component in share dev codex proton; do
  [[ ! -e $test_root/.local/state/qvos/qvcore/$component ]] ||
    fail "$component enabled state remains"
done
grep -Fq 'personal data were preserved' <<<"$disable_output" ||
  fail "qvCORE disable preservation result"
if grep -Fq 'qvCORE health' <<<"$disable_output"; then
  fail "qvCORE disable prints a health catalog"
fi
pass "qvCORE disable preserves applications without health inventory noise"

if run_health unknown >/dev/null 2>&1; then
  fail "unknown qvCORE health mode succeeds"
fi
pass "qvCORE health rejects unknown modes without mutation"
