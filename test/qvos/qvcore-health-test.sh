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
  "$test_root/.local/state/qvos/qvcore"
touch "$lifecycle_log"

for component in warp share dev codex proton; do
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
--adopt)
  printf 'adopt\t%s\n' "$component" >>"$QVOS_TEST_HEALTH_LIFECYCLE_LOG"
  install -D -m 0644 /dev/null "$state_file"
  install -m 0644 /dev/null "$QVOS_TEST_HEALTH_STATE/ready-$component"
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

for component in brave-origin steam media; do
  install -m 0755 /dev/stdin "$fixture/qv/core/$component.sh" <<'SCRIPT'
#!/bin/bash
component=$(basename "$0" .sh)
case ${1:-} in
--state)
  if [[ -f $QVOS_TEST_HEALTH_STATE/simple-$component ]]; then
    cat "$QVOS_TEST_HEALTH_STATE/simple-$component"
  else
    echo "not-installed"
  fi
  ;;
*)
  exit 2
  ;;
esac
SCRIPT
done

install -m 0755 /dev/stdin "$fixture/qv/core/install" <<'SCRIPT'
#!/bin/bash
component=$1
printf 'install\t%s\n' "$component" >>"$QVOS_TEST_HEALTH_LIFECYCLE_LOG"
case $component in
warp) command_name=warp-cli ;;
share) command_name=localsend ;;
dev) command_name=bun ;;
codex) command_name=codex ;;
proton) command_name=proton-drive ;;
brave-origin | steam | media)
  printf 'ready\n' >"$QVOS_TEST_HEALTH_STATE/simple-$component"
  exit
  ;;
*) exit 2 ;;
esac
install -m 0644 /dev/null "$QVOS_TEST_HEALTH_STATE/commands/$command_name"
install -D -m 0644 /dev/null "$HOME/.local/state/qvos/qvcore/$component"
install -m 0644 /dev/null "$QVOS_TEST_HEALTH_STATE/ready-$component"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_HEALTH_STATE/commands/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
choose) printf '%s\n' "${QVOS_TEST_HEALTH_CHOICE:-share}" ;;
confirm) [[ ${QVOS_TEST_HEALTH_CONFIRM:-1} == "1" ]] ;;
*) exit 1 ;;
esac
SCRIPT

run_health() {
  QVOS_TEST_HEALTH_CHOICE="${QVOS_TEST_HEALTH_CHOICE:-share}" \
    QVOS_TEST_HEALTH_CONFIRM="${QVOS_TEST_HEALTH_CONFIRM:-1}" \
    QVOS_TEST_HEALTH_LIFECYCLE_LOG="$lifecycle_log" \
    QVOS_TEST_HEALTH_STATE="$state" \
    HOME="$test_root" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    "$health" "$@"
}

enable_all_integrations() {
  local component

  for component in warp share dev codex proton; do
    install -m 0644 /dev/null \
      "$test_root/.local/state/qvos/qvcore/$component"
    install -m 0644 /dev/null "$state/ready-$component"
  done
  for command in warp-cli localsend bun codex proton-drive; do
    install -m 0644 /dev/null "$state/commands/$command"
  done
}

empty_update=$(run_health update)
[[ -z $empty_update ]] ||
  fail "unused qvCORE update output"
[[ ! -s $lifecycle_log ]] ||
  fail "unused qvCORE update action"
[[ $(run_health enabled-count) == "0" ]] ||
  fail "unused qvCORE enabled count"
empty_status=$(run_health status)
grep -Fq 'Optional software that is absent is not considered broken.' \
  <<<"$empty_status" || fail "unused qvCORE absence policy"
for component in WARP Brave Share Devel Codex Proton Steam Media; do
  grep -Eq "[[:space:]]${component}[[:space:]]+Not installed" <<<"$empty_status" ||
    fail "unused qvCORE $component status"
done
pass "qvCORE reports the complete optional catalog without treating absence as damage"

install -m 0644 /dev/null "$state/commands/warp-cli"
install -m 0644 /dev/null "$state/ready-warp"
: >"$lifecycle_log"
run_health repair warp >/dev/null
grep -Fqx $'adopt\twarp' "$lifecycle_log" ||
  fail "existing WARP adoption"
if grep -Fq $'install\twarp' "$lifecycle_log"; then
  fail "healthy existing WARP is reconfigured"
fi
pass "qvCORE adopts an existing healthy WARP setup without reconfiguration"

enable_all_integrations
printf 'ready\n' >"$state/simple-brave-origin"
printf 'partial\n' >"$state/simple-steam"
ready_output=$(run_health status)
grep -Eq '[[:space:]]WARP[[:space:]]+Ready' <<<"$ready_output" ||
  fail "qvCORE WARP ready status"
grep -Eq '[[:space:]]Steam[[:space:]]+Partial' <<<"$ready_output" ||
  fail "qvCORE Steam partial status"
grep -Eq '[[:space:]]Media[[:space:]]+Not installed' <<<"$ready_output" ||
  fail "qvCORE Media optional absence"
[[ $(run_health enabled-count) == "5" ]] ||
  fail "enabled qvCORE count"
pass "qvCORE distinguishes healthy integrations from partial and absent software"

rm -f "$state/ready-share"
set +e
drift_output=$(run_health status 2>&1)
drift_status=$?
set -e
((drift_status == 1)) ||
  fail "qvCORE drift status succeeds"
grep -Eq '[[:space:]]Share[[:space:]]+Needs repair' <<<"$drift_output" ||
  fail "qvCORE Share drift"
pass "qvCORE status fails only for enabled integration drift"

: >"$lifecycle_log"
repair_output=$(run_health repair share)
grep -Fqx $'repair\tshare' "$lifecycle_log" ||
  fail "targeted qvCORE Share repair"
[[ $(grep -c '^repair' "$lifecycle_log") == "1" ]] ||
  fail "targeted qvCORE repair touches another component"
grep -Eq '[[:space:]]Share[[:space:]]+Ready' <<<"$repair_output" ||
  fail "targeted qvCORE repair completion"
pass "qvCORE repair changes exactly the selected broken integration"

rm -f "$state/ready-codex"
: >"$lifecycle_log"
QVOS_TEST_HEALTH_CHOICE=codex run_health repair >/dev/null
grep -Fqx $'repair\tcodex' "$lifecycle_log" ||
  fail "interactive qvCORE component choice"
[[ $(grep -c '^repair' "$lifecycle_log") == "1" ]] ||
  fail "interactive qvCORE repair touches another component"
pass "qvCORE interactive repair chooses one component"

rm -f \
  "$test_root/.local/state/qvos/qvcore/proton" \
  "$state/ready-proton" \
  "$state/commands/proton-drive"
: >"$lifecycle_log"
run_health repair proton >/dev/null
grep -Fqx $'install\tproton' "$lifecycle_log" ||
  fail "explicit missing qvCORE component install"
pass "qvCORE installs an absent component only after explicit selection"

printf 'not-installed\n' >"$state/simple-media"
: >"$lifecycle_log"
run_health repair media >/dev/null
grep -Fqx $'install\tmedia' "$lifecycle_log" ||
  fail "explicit Media install"
pass "simple application collections delegate to their installer"

rm -f "$state/commands/localsend"
: >"$lifecycle_log"
removed_output=$(
  QVOS_TEST_HEALTH_CHOICE="Keep it removed and clean qvOS integration state" \
    run_health repair share
)
[[ ! -e $test_root/.local/state/qvos/qvcore/share ]] ||
  fail "removed Share setup remains tracked"
grep -Fqx $'disable\tshare' "$lifecycle_log" ||
  fail "removed Share integration cleanup"
if grep -Fq $'install\tshare' "$lifecycle_log"; then
  fail "removed Share application is reinstalled"
fi
grep -Eq '[[:space:]]Share[[:space:]]+Not installed' <<<"$removed_output" ||
  fail "removed Share final status"
pass "application removal remains user intent during qvCORE repair"

install -m 0644 /dev/null "$state/commands/localsend"
install -m 0644 /dev/null "$test_root/.local/state/qvos/qvcore/share"
install -m 0644 /dev/null "$state/ready-share"
rm -f "$state/ready-proton"
: >"$lifecycle_log"
automatic_output=$(run_health repair-enabled)
grep -Fqx $'repair\tproton' "$lifecycle_log" ||
  fail "automatic qvCORE Proton repair"
[[ $(grep -c '^repair' "$lifecycle_log") == "1" ]] ||
  fail "automatic qvCORE repair touches healthy setups"
grep -Fq 'Enabled qvCORE setups are ready.' <<<"$automatic_output" ||
  fail "automatic qvCORE repair completion"
pass "qvOS repair preserves only affected enabled qvCORE integrations"

: >"$lifecycle_log"
rm -f "$state/commands/localsend"
update_output=$(run_health update)
[[ ! -e $test_root/.local/state/qvos/qvcore/share ]] ||
  fail "removed Share setup remains tracked after update"
grep -Fqx $'disable\tshare' "$lifecycle_log" ||
  fail "removed Share update retirement"
if grep -Fq 'need attention' <<<"$update_output"; then
  fail "removed Share application reports damage during update"
fi
pass "qvCORE update also treats application removal as user intent"

enable_all_integrations
: >"$lifecycle_log"
disable_output=$(QVOS_TEST_HEALTH_CHOICE=all run_health disable)
[[ $(grep -c '^disable' "$lifecycle_log") == "5" ]] ||
  fail "qvCORE disable-all count"
for component in warp share dev codex proton; do
  [[ ! -e $test_root/.local/state/qvos/qvcore/$component ]] ||
    fail "$component enabled state remains"
done
grep -Fq 'network choices, and personal data were preserved' <<<"$disable_output" ||
  fail "qvCORE disable preservation result"
pass "qvCORE disable includes WARP while preserving the active network choice"

if run_health repair unknown >/dev/null 2>&1; then
  fail "unknown qvCORE component succeeds"
fi
if run_health unknown >/dev/null 2>&1; then
  fail "unknown qvCORE health mode succeeds"
fi
pass "qvCORE health rejects unknown modes and components without mutation"
