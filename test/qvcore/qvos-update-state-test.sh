#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
state_owner="$root/qvcore/update/state"
power_owner="$root/qvcore/power/system-power"
test_root="$(mktemp -d)"
home="$test_root/home"
runtime="$home/run"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_state() {
  HOME="$home" \
    XDG_RUNTIME_DIR="$runtime" \
    QVOS_PATH="$root" \
    "$state_owner" "$@"
}

install -d -m 0700 "$home" "$runtime"
run_state set reboot-required
run_state set restart-waybar-required
state_root="$home/.local/state/qvos/update"
[[ $(stat -c '%a' "$state_root") == "700" ]] ||
  fail "qvOS update-state directory mode"
for marker in reboot-required restart-waybar-required; do
  [[ -f $state_root/$marker && ! -s $state_root/$marker ]] ||
    fail "qvOS update marker missing: $marker"
  [[ $(stat -c '%a' "$state_root/$marker") == "600" ]] ||
    fail "qvOS update marker mode: $marker"
done
printf 'private update output\n' >"$state_root/update.log"
chmod 0600 "$state_root/update.log"
run_state set restart-waybar-required
grep -Fqx 'private update output' "$state_root/update.log" ||
  fail "private update log changed during marker validation"
chmod 0644 "$state_root/update.log"
if run_state set restart-waybar-required >/dev/null 2>&1; then
  fail "insecure update log mode was accepted"
fi
chmod 0600 "$state_root/update.log"
if run_state set arbitrary-setting >/dev/null 2>&1; then
  fail "generic persistent state was accepted"
fi
if run_state set ../reboot-required >/dev/null 2>&1; then
  fail "state traversal was accepted"
fi
run_state clear reboot-required
[[ ! -e $state_root/reboot-required ]] || fail "exact marker clear"
run_state clear 're*-required'
[[ -z $(find "$state_root" -maxdepth 1 -type f -name 're*-required' -print -quit) ]] ||
  fail "update-marker clear-all compatibility"
printf 'ok - update state accepts only reviewed markers and its private sibling log\n'

if run_state migrate >/dev/null 2>&1; then
  fail "retired update-state migration mode remains available"
fi
[[ ! -e $home/.local/state/omarchy ]] ||
  fail "native update state created an inherited state root"
printf 'ok - update state has no inherited migration surface\n'

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/nohup" <<'SCRIPT'
#!/bin/bash
printf 'schedule:%s\n' "$*" >>"$QVOS_TEST_POWER_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
clients)
  printf '[{"address":"0x1"}]\n'
  ;;
dispatch)
  case ${2:-} in
  closewindow) printf 'close-windows\n' >>"$QVOS_TEST_POWER_LOG" ;;
  workspace) printf 'workspace:%s\n' "${3:-}" >>"$QVOS_TEST_POWER_LOG" ;;
  *) exit 1 ;;
  esac
  ;;
*) exit 1 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sleep" <<'SCRIPT'
#!/bin/bash
printf 'grace:%s\n' "$*" >>"$QVOS_TEST_POWER_LOG"
SCRIPT

run_state set reboot-required
HOME="$home" \
  XDG_RUNTIME_DIR="$runtime" \
  QVOS_PATH="$root" \
  QVOS_TEST_POWER_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$power_owner" reboot
for ((attempt = 0; attempt < 100; attempt++)); do
  grep -q '^schedule:' "$action_log" 2>/dev/null && break
  sleep 0.01
done
grep -Fq 'qvos-power reboot' "$action_log" || fail "fixed reboot scheduling"
grep -Fqx 'close-windows' "$action_log" || fail "window-close delegation"
grep -Fqx 'workspace:1' "$action_log" || fail "post-close workspace"
grep -Fqx 'grace:1' "$action_log" || fail "application shutdown grace"
[[ ! -e $state_root/reboot-required ]] || fail "system power marker cleanup"

: >"$action_log"
HOME="$home" \
  XDG_RUNTIME_DIR="$runtime" \
  QVOS_PATH="$root" \
  QVOS_TEST_POWER_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/bin/qv-system-shutdown"
for ((attempt = 0; attempt < 100; attempt++)); do
  grep -q '^schedule:' "$action_log" 2>/dev/null && break
  sleep 0.01
done
grep -Fq 'qvos-power poweroff' "$action_log" || fail "fixed shutdown scheduling"
if HOME="$home" XDG_RUNTIME_DIR="$runtime" QVOS_PATH="$root" \
  QVOS_TEST_POWER_LOG="$action_log" PATH="$test_bin:/usr/bin" \
  "$power_owner" invalid >/dev/null 2>&1; then
  fail "invalid system-power action was accepted"
fi
printf 'ok - reboot and shutdown share one fixed native power owner\n'
