#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
component="$root/qv/core/warp.sh"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
state="$test_root/state"
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

install -d "$test_bin" "$state"
touch "$action_log"

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ $1 == "warp-cli" && -f $QVOS_TEST_WARP_STATE/package ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
case $1 in
is-enabled) [[ -f $QVOS_TEST_WARP_STATE/enabled ]] ;;
is-active) [[ -f $QVOS_TEST_WARP_STATE/active ]] ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/warp-cli" <<'SCRIPT'
#!/bin/bash
case $* in
"--json registration show")
  [[ -f $QVOS_TEST_WARP_STATE/registered ]]
  ;;
"--json status")
  if [[ -f $QVOS_TEST_WARP_STATE/connected ]]; then
    printf '{"status":"Connected","reason":"NetworkHealthy"}\n'
  else
    printf '{"status":"Disconnected","reason":"Manual"}\n'
  fi
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-qvos-setup-dns" <<'SCRIPT'
#!/bin/bash
printf 'setup\t%s\n' "$1" >>"$QVOS_TEST_WARP_ACTION_LOG"
case $1 in
WARP)
  touch \
    "$QVOS_TEST_WARP_STATE/package" \
    "$QVOS_TEST_WARP_STATE/enabled" \
    "$QVOS_TEST_WARP_STATE/active" \
    "$QVOS_TEST_WARP_STATE/registered" \
    "$QVOS_TEST_WARP_STATE/connected"
  install -D -m 0644 /dev/null "$HOME/.local/state/qvos/qvcore/warp"
  ;;
DHCP)
  rm -f "$QVOS_TEST_WARP_STATE/connected"
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

run_warp() {
  QVOS_TEST_WARP_ACTION_LOG="$action_log" \
    QVOS_TEST_WARP_STATE="$state" \
    HOME="$test_root" \
    PATH="$test_bin:/usr/bin" \
    "$component" "$@"
}

if run_warp --status >/dev/null 2>&1; then
  fail "missing WARP status succeeds"
fi
pass "WARP health rejects an absent optional setup without installing it"

install_output=$(run_warp)
grep -Fqx $'setup\tWARP' "$action_log" || fail "WARP owner delegation"
grep -Fq 'qvCORE WARP is ready: 5/5.' <<<"$install_output" ||
  fail "WARP install verification"
[[ -f $test_root/.local/state/qvos/qvcore/warp ]] ||
  fail "WARP maintenance state"
run_warp --status >/dev/null
pass "WARP installation delegates once and verifies the complete integration"

rm -f "$state/connected"
: >"$action_log"
if run_warp --integration-status >/dev/null 2>&1; then
  fail "disconnected WARP integration succeeds"
fi
repair_output=$(run_warp --repair)
grep -Fqx $'setup\tWARP' "$action_log" || fail "WARP repair delegation"
grep -Fq 'qvCORE WARP is ready: 5/5.' <<<"$repair_output" ||
  fail "WARP repair verification"
pass "enabled WARP repair restores real service and connection state"

: >"$action_log"
disable_output=$(run_warp --disable)
[[ ! -e $test_root/.local/state/qvos/qvcore/warp ]] ||
  fail "WARP disable maintenance state"
[[ -f $state/connected ]] || fail "WARP disable changes network state"
[[ ! -s $action_log ]] || fail "WARP disable invokes setup"
grep -Fq 'current network choice was not changed' <<<"$disable_output" ||
  fail "WARP disable preservation result"
pass "disabling WARP integration preserves the active network choice"

adopt_output=$(run_warp --adopt)
[[ -f $test_root/.local/state/qvos/qvcore/warp ]] ||
  fail "WARP adoption state"
grep -Fq 'qvCORE WARP is ready: 5/5.' <<<"$adopt_output" ||
  fail "WARP adoption verification"
pass "an existing healthy WARP setup can be adopted without reconfiguration"

: >"$action_log"
prepare_output=$(run_warp --prepare-remove)
grep -Fqx $'setup\tDHCP' "$action_log" ||
  fail "WARP pre-removal network handoff"
[[ ! -e $test_root/.local/state/qvos/qvcore/warp ]] ||
  fail "WARP pre-removal maintenance state"
grep -Fq 'ready for software removal' <<<"$prepare_output" ||
  fail "WARP pre-removal result"
pass "WARP hands networking back to DHCP before package removal"

if run_warp --adopt >/dev/null 2>&1; then
  fail "unhealthy WARP adoption succeeds"
fi
[[ ! -e $test_root/.local/state/qvos/qvcore/warp ]] ||
  fail "unhealthy WARP adoption state"
pass "WARP adoption refuses incomplete network state"
