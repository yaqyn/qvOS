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
cp "$root/qv/core/catalog.tsv" "$fixture/qv/core/catalog.tsv"
install -m 0755 "$health" "$fixture/qv/core/health.sh"
touch "$lifecycle_log"

for component in warp share proton; do
  install -m 0755 /dev/stdin "$fixture/qv/core/$component.sh" <<'SCRIPT'
#!/bin/bash
component=$(basename "$0" .sh)
state_file="$HOME/.local/state/qvos/qvcore/$component"
case ${1:-} in
--integration-status)
  [[ -f $state_file && -f $QVOS_TEST_HEALTH_STATE/ready-$component ]]
  ;;
--repair)
  printf 'repair\t%s\n' "$component" >>"$QVOS_TEST_HEALTH_LIFECYCLE_LOG"
  if [[ ${QVOS_TEST_HEALTH_NO_REPAIR:-0} != "1" ]]; then
    install -m 0644 /dev/null "$QVOS_TEST_HEALTH_STATE/ready-$component"
  fi
  [[ -f $state_file ]]
  ;;
--adopt)
  printf 'adopt\t%s\n' "$component" >>"$QVOS_TEST_HEALTH_LIFECYCLE_LOG"
  install -D -m 0644 /dev/null "$state_file"
  install -m 0644 /dev/null "$QVOS_TEST_HEALTH_STATE/ready-$component"
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

install -m 0755 /dev/stdin "$fixture/qv/core/install" <<'SCRIPT'
#!/bin/bash
component=$1
printf 'install\t%s\n' "$component" >>"$QVOS_TEST_HEALTH_LIFECYCLE_LOG"
case $component in
warp) command_name=warp-cli ;;
share) command_name=localsend ;;
proton) command_name=proton-drive ;;
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
    QVOS_TEST_HEALTH_NO_REPAIR="${QVOS_TEST_HEALTH_NO_REPAIR:-0}" \
    QVOS_TEST_HEALTH_STATE="$state" \
    HOME="$test_root" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    "$health" "$@"
}

run_public_status() {
  QVOS_TEST_HEALTH_LIFECYCLE_LOG="$lifecycle_log" \
    QVOS_TEST_HEALTH_STATE="$state" \
    HOME="$test_root" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    "$root/bin/omarchy-qvcore-status" "$@"
}

enable_integrations() {
  local component command

  for component in warp share proton; do
    install -m 0644 /dev/null \
      "$test_root/.local/state/qvos/qvcore/$component"
    install -m 0644 /dev/null "$state/ready-$component"
  done
  for command in warp-cli localsend proton-drive; do
    install -m 0644 /dev/null "$state/commands/$command"
  done
}

empty_status=$(run_health status)
grep -Fq 'qvCORE apps are normal personal software and are not graded here.' \
  <<<"$empty_status" || fail "qvCORE application policy"
for component in WARP Share Proton; do
  grep -Eq "[[:space:]]${component}[[:space:]]+Missing" <<<"$empty_status" ||
    fail "unused managed setup status: $component"
done
for app in Brave Devel Codex Media; do
  if grep -Eq "^[[:space:]]+.*${app}[[:space:]]+(Ready|Partial|Disabled|Missing)" \
    <<<"$empty_status"; then
    fail "ordinary qvCORE app graded as a managed setup: $app"
  fi
done
pass "health grades only the three managed setups"

install -m 0644 /dev/null "$state/commands/localsend"
disabled_output=$(run_health status)
grep -Eq '[[:space:]]Share[[:space:]]+Disabled' <<<"$disabled_output" ||
  fail "installed but disabled Share status"
rm -f "$state/commands/localsend"
pass "health distinguishes installed software from an enabled setup"

install -m 0644 /dev/null "$state/commands/warp-cli"
: >"$lifecycle_log"
run_health repair warp >/dev/null
grep -Fqx $'adopt\twarp' "$lifecycle_log" ||
  fail "existing WARP adoption"
if grep -Fq $'install\twarp' "$lifecycle_log"; then
  fail "existing WARP is reinstalled"
fi
pass "WARP can adopt existing software without reinstalling it"

enable_integrations
rm -f "$state/ready-share"
partial_output=$(run_health status)
grep -Eq '[[:space:]]WARP[[:space:]]+Ready' <<<"$partial_output" ||
  fail "WARP ready status"
grep -Eq '[[:space:]]Share[[:space:]]+Partial' \
  <<<"$partial_output" || fail "Share partial status"
set +e
partial_check_output=$(run_health check 2>&1)
partial_check_status=$?
set -e
((partial_check_status == 1)) ||
  fail "partial managed setup check status"
[[ $partial_check_output == "$partial_output" ]] ||
  fail "status and check inventory differ"
public_status_output=$(run_public_status)
[[ $public_status_output == "$partial_output" ]] ||
  fail "public setup status inventory"
set +e
run_public_status --check >/dev/null 2>&1
public_check_status=$?
set -e
((public_check_status == 1)) || fail "public setup check status"
pass "status reports partial setups successfully while check gates automation"

rm -f "$state/ready-share"
: >"$lifecycle_log"
repair_output=$(run_health repair share)
grep -Fqx $'repair\tshare' "$lifecycle_log" ||
  fail "targeted Share repair"
[[ $(grep -c '^repair' "$lifecycle_log") == "1" ]] ||
  fail "targeted repair touches another setup"
grep -Eq '[[:space:]]Share[[:space:]]+Ready' <<<"$repair_output" ||
  fail "Share repair completion"
pass "repair changes exactly the selected broken setup"

rm -f "$state/ready-share"
: >"$lifecycle_log"
set +e
no_op_repair_output=$(
  QVOS_TEST_HEALTH_NO_REPAIR=1 run_health repair share 2>&1
)
no_op_repair_status=$?
set -e
((no_op_repair_status == 1)) ||
  fail "no-op setup owner reports successful repair"
grep -Fq 'Share did not reach its expected setup state.' \
  <<<"$no_op_repair_output" || fail "no-op repair verification result"
pass "interactive repair verifies the selected setup after its owner returns"

rm -f "$state/ready-share"
: >"$lifecycle_log"
QVOS_TEST_HEALTH_CHOICE=share run_health repair >/dev/null
grep -Fqx $'repair\tshare' "$lifecycle_log" ||
  fail "interactive setup choice"
pass "interactive repair chooses one managed setup"

rm -f \
  "$test_root/.local/state/qvos/qvcore/proton" \
  "$state/ready-proton" \
  "$state/commands/proton-drive"
: >"$lifecycle_log"
run_health repair proton >/dev/null
grep -Fqx $'install\tproton' "$lifecycle_log" ||
  fail "missing Proton setup install"
pass "an absent setup installs only after explicit selection"

for app in brave-origin dev codex media; do
  : >"$lifecycle_log"
  if run_health repair "$app" >/dev/null 2>&1; then
    fail "ordinary qvCORE app accepted by setup repair: $app"
  fi
  [[ ! -s $lifecycle_log ]] ||
    fail "ordinary qvCORE app repair performs a setup action: $app"
done
pass "ordinary apps cannot enter setup repair"

enable_integrations
: >"$lifecycle_log"
healthy_maintenance_output=$(run_health maintain)
[[ -z $healthy_maintenance_output ]] ||
  fail "healthy setup maintenance emits unnecessary output"
[[ ! -s $lifecycle_log ]] ||
  fail "healthy setup maintenance performs an action"
pass "healthy setup maintenance succeeds silently"

rm -f "$state/commands/localsend" "$state/ready-proton"
: >"$lifecycle_log"
maintain_output=$(run_health maintain)
grep -Fqx $'disable\tshare' "$lifecycle_log" ||
  fail "removed Share integration cleanup"
grep -Fqx $'repair\tproton' "$lifecycle_log" ||
  fail "Proton post-update repair"
[[ $(wc -l <"$lifecycle_log") == "2" ]] ||
  fail "post-update maintenance touches an app or disabled setup"
grep -Fq 'Enabled qvCORE setup maintenance is complete.' \
  <<<"$maintain_output" || fail "setup maintenance completion"
pass "post-update maintenance touches only enabled integration setups"

enable_integrations
rm -f "$state/ready-proton"
: >"$lifecycle_log"
set +e
no_op_maintenance_output=$(
  QVOS_TEST_HEALTH_NO_REPAIR=1 run_health maintain 2>&1
)
no_op_maintenance_status=$?
set -e
((no_op_maintenance_status == 1)) ||
  fail "no-op setup owner reports successful maintenance"
grep -Fq 'Proton maintenance did not finish.' \
  <<<"$no_op_maintenance_output" || fail "no-op maintenance verification result"
pass "post-update maintenance verifies owner results before reporting success"

enable_integrations
: >"$lifecycle_log"
disable_output=$(QVOS_TEST_HEALTH_CHOICE=all run_health disable)
[[ $(grep -c '^disable' "$lifecycle_log") == "3" ]] ||
  fail "disable-all setup count"
for component in warp share proton; do
  [[ ! -e $test_root/.local/state/qvos/qvcore/$component ]] ||
    fail "$component enabled state remains"
done
grep -Fq 'network choices, and personal data were preserved' <<<"$disable_output" ||
  fail "disable preservation result"
pass "disable clears setup ownership or integration and preserves software and data"

if run_health repair unknown >/dev/null 2>&1; then
  fail "unknown setup succeeds"
fi
if run_health unknown >/dev/null 2>&1; then
  fail "unknown health mode succeeds"
fi
if run_public_status unknown >/dev/null 2>&1; then
  fail "unknown public status argument succeeds"
fi
if run_public_status --check extra >/dev/null 2>&1; then
  fail "extra public status argument succeeds"
fi
pass "qvCORE health rejects unknown modes and setups without mutation"

mv "$fixture/qv/core/share.sh" "$fixture/qv/core/share.sh.missing"
set +e
missing_owner_output=$(run_health status 2>&1)
missing_owner_status=$?
set -e
((missing_owner_status == 1)) || fail "missing setup owner succeeds"
grep -Fq 'Missing managed qvCORE setup owner: share' \
  <<<"$missing_owner_output" || fail "missing setup owner result"
pass "managed setup health fails closed when a catalog owner is unavailable"
