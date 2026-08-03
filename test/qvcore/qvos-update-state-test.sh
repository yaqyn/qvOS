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
printf 'ok - update state is private and restricted to reviewed markers\n'

legacy_root="$home/.local/state/omarchy"
install -d "$legacy_root"
for legacy_marker in reboot-required first-run.mode; do
  install -m 0644 /dev/null "$legacy_root/$legacy_marker"
done
run_state migrate
[[ -f $state_root/reboot-required ]] || fail "legacy reboot marker migration"
[[ -f $legacy_root/first-run.mode ]] ||
  fail "unrelated first-run compatibility state was removed"
[[ ! -e $legacy_root/reboot-required ]] ||
  fail "legacy reboot marker remained"
run_state clear reboot-required
rm -- "$legacy_root/first-run.mode"
rmdir -- "$legacy_root"

outside="$test_root/outside"
install -d "$legacy_root" "$outside"
printf 'preserve\n' >"$outside/marker"
ln -s "$outside/marker" "$legacy_root/restart-waybar-required"
if run_state migrate >/dev/null 2>&1; then
  fail "symbolic-link legacy update marker was accepted"
fi
[[ $(<"$outside/marker") == "preserve" ]] ||
  fail "unsafe legacy marker changed external data"
rm -- "$legacy_root/restart-waybar-required"
rmdir -- "$legacy_root"
printf 'ok - exact legacy markers migrate without touching unrelated or unsafe state\n'

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/nohup" <<'SCRIPT'
#!/bin/bash
printf 'schedule:%s\n' "$*" >>"$QVOS_TEST_POWER_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hyprland-window-close-all" <<'SCRIPT'
#!/bin/bash
printf 'close-windows\n' >>"$QVOS_TEST_POWER_LOG"
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
