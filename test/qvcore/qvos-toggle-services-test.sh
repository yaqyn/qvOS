#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
systemctl_log="$test_root/systemctl.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$test_home/.local/state/qvos/toggles/hypr"

HOME="$test_home" QVOS_PATH="$root" "$root/qvcore/config/toggle-state"
cmp -s "$root/qvcore/config/toggles/flags.lua" \
  "$test_home/.local/state/qvos/toggles/hypr/flags.lua" ||
  fail "native Lua toggle seed was not installed"
while IFS= read -r -d '' state_path; do
  if [[ -d $state_path ]]; then
    [[ $(stat -c '%a' "$state_path") == "700" ]] ||
      fail "toggle state directory is not private"
  else
    [[ $(stat -c '%a' "$state_path") == "600" ]] ||
      fail "toggle state file is not private"
  fi
done < <(find "$test_home/.local/state/qvos/toggles" -print0)

toggle_snapshot=$(find "$test_home/.local/state/qvos/toggles" \
  -printf '%P|%m|%i|%T@\n' | sort)
HOME="$test_home" QVOS_PATH="$root" "$root/qvcore/config/toggle-state"
[[ $(find "$test_home/.local/state/qvos/toggles" \
  -printf '%P|%m|%i|%T@\n' | sort) == "$toggle_snapshot" ]] ||
  fail "toggle-state initialization is not idempotent"

unsafe_state_home="$test_root/unsafe-state-home"
external_local="$test_root/external-local"
install -d "$unsafe_state_home" "$external_local"
ln -s "$external_local" "$unsafe_state_home/.local"
if HOME="$unsafe_state_home" QVOS_PATH="$root" \
  "$root/qvcore/config/toggle-state" >/dev/null 2>&1; then
  fail "toggle-state followed a linked .local root"
fi
[[ -z $(find "$external_local" -mindepth 1 -print -quit) ]] ||
  fail "toggle-state mutated through a linked .local root"

HOME="$test_home" QVOS_PATH="$root" \
  "$root/qvcore/config/toggle" nested/example
[[ -f $test_home/.local/state/qvos/toggles/nested/example ]] ||
  fail "native generic toggle did not enable"
HOME="$test_home" QVOS_PATH="$root" \
  "$root/qvcore/config/toggle" nested/example
[[ ! -e $test_home/.local/state/qvos/toggles/nested/example ]] ||
  fail "native generic toggle did not disable"
if HOME="$test_home" QVOS_PATH="$root" \
  "$root/qvcore/config/toggle" ../escape >/dev/null 2>&1; then
  fail "toggle accepted path traversal"
fi
[[ ! -e $test_home/.local/state/qvos/escape ]] ||
  fail "toggle path traversal escaped its owner"

install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
HOME="$test_home" QVOS_PATH="$root" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/toggle" \
  --enabled-notification "presentation failure" notification-failure
[[ -f $test_home/.local/state/qvos/toggles/notification-failure ]] ||
  fail "notification failure hid a successful toggle mutation"
HOME="$test_home" QVOS_PATH="$root" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/toggle" notification-failure

unsafe_toggle_home="$test_root/unsafe-toggle-home"
external_toggles="$test_root/external-toggles"
install -d "$unsafe_toggle_home/.local/state/qvos" "$external_toggles"
ln -s "$external_toggles" "$unsafe_toggle_home/.local/state/qvos/toggles"
if HOME="$unsafe_toggle_home" QVOS_PATH="$root" \
  "$root/qvcore/config/toggle" unsafe >/dev/null 2>&1; then
  fail "generic toggle accepted a linked state root"
fi
[[ -z $(find "$external_toggles" -mindepth 1 -print -quit) ]] ||
  fail "generic toggle followed a linked state root"

concurrent_home="$test_root/concurrent-toggle-home"
install -d "$concurrent_home"
for _ in {1..10}; do
  HOME="$concurrent_home" QVOS_PATH="$root" \
    "$root/qvcore/config/toggle" concurrent &
  first_toggle_pid=$!
  HOME="$concurrent_home" QVOS_PATH="$root" \
    "$root/qvcore/config/toggle" concurrent &
  second_toggle_pid=$!
  wait "$first_toggle_pid"
  wait "$second_toggle_pid"
  [[ ! -e $concurrent_home/.local/state/qvos/toggles/concurrent ]] ||
    fail "concurrent toggle mutations were not serialized"
done
[[ $(stat -c '%a' "$concurrent_home/.local/state/qvos/toggles/.lock") == "600" ]] ||
  fail "toggle transaction lock is not private"
printf 'ok - generic toggle mutations reject links, serialize, and outlive presentation failures\n'

hyprctl_log="$test_root/hyprctl.log"
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_HYPRCTL_LOG"
SCRIPT
: >"$hyprctl_log"
HOME="$test_home" \
  QVOS_PATH="$root" \
  QVOS_TEST_HYPRCTL_LOG="$hyprctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/hyprland-toggle" window-no-gaps
cmp -s \
  "$root/qvcore/config/toggles/window-no-gaps.lua" \
  "$test_home/.local/state/qvos/toggles/hypr/window-no-gaps.lua" ||
  fail "native Hyprland toggle template was not applied exactly"
[[ $(stat -c '%a' "$test_home/.local/state/qvos/toggles/hypr/window-no-gaps.lua") == "600" ]] ||
  fail "native Hyprland toggle is not private"
HOME="$test_home" \
  QVOS_PATH="$root" \
  QVOS_TEST_HYPRCTL_LOG="$hyprctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/hyprland-toggle" window-no-gaps
[[ ! -e $test_home/.local/state/qvos/toggles/hypr/window-no-gaps.lua ]] ||
  fail "native Hyprland toggle template was not removed"
[[ $(<"$hyprctl_log") == $'reload\nreload' ]] ||
  fail "Hyprland toggle reload count"

printf 'ok - qvOS toggle state is native, private, idempotent, and traversal-safe\n'

service_home="$test_root/service-home"
unit_root="$service_home/.config/systemd/user"
install -d "$unit_root" "$test_bin"
: >"$systemctl_log"

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case "$*" in
"--user show-environment")
  [[ ${QVOS_TEST_MANAGER_UNAVAILABLE:-} != "1" ]] || exit 1
  printf 'HOME=%s\n' "${QVOS_TEST_MANAGER_HOME:-$HOME}"
  ;;
*)
  printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
  ;;
esac
SCRIPT

deferred_home="$test_root/deferred-service-home"
deferred_unit_root="$deferred_home/.config/systemd/user"
QVOS_TEST_MANAGER_UNAVAILABLE=1 \
  HOME="$deferred_home" \
  QVOS_PATH="$root" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/user-services"
for native_unit in \
  qvos-battery-monitor.service \
  qvos-battery-monitor.timer \
  qvos-recover-internal-monitor.service \
  qvos-swayosd-server.service; do
  cmp -s \
    "$root/qvcore/config/files/systemd/user/$native_unit" \
    "$deferred_unit_root/$native_unit" ||
    fail "deferred native user service deployment: $native_unit"
done
[[ ! -s $systemctl_log ]] ||
  fail "unavailable user manager received a mutation"
printf 'ok - fresh user units stage safely without a chroot user manager\n'

HOME="$service_home" \
  QVOS_PATH="$root" \
  QVOS_USER_SERVICES_TESTING=1 \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/user-services"
for native_unit in \
  qvos-battery-monitor.service \
  qvos-battery-monitor.timer \
  qvos-recover-internal-monitor.service \
  qvos-swayosd-server.service; do
  cmp -s "$root/qvcore/config/files/systemd/user/$native_unit" "$unit_root/$native_unit" ||
    fail "native user service was not deployed exactly: $native_unit"
done
[[ $(<"$systemctl_log") == '--user daemon-reload' ]] ||
  fail "changed user-service deployment reload"

service_snapshot=$(find "$service_home" -printf '%P|%m|%i|%T@\n' | sort)
systemctl_snapshot=$(<"$systemctl_log")
HOME="$service_home" \
  QVOS_PATH="$root" \
  QVOS_USER_SERVICES_TESTING=1 \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/user-services"
[[ $(find "$service_home" -printf '%P|%m|%i|%T@\n' | sort) == \
  "$service_snapshot" ]] || fail "user-service reconciliation is not idempotent"
[[ $(<"$systemctl_log") == "$systemctl_snapshot" ]] ||
  fail "idempotent user-service reconciliation touched systemd"

unsafe_service_home="$test_root/unsafe-service-home"
unsafe_unit_root="$unsafe_service_home/.config/systemd/user"
unsafe_target="$test_root/unsafe-service-target"
install -d "$unsafe_unit_root"
printf 'external service\n' >"$unsafe_target"
ln -s "$unsafe_target" "$unsafe_unit_root/qvos-battery-monitor.service"
if HOME="$unsafe_service_home" \
  QVOS_PATH="$root" \
  QVOS_USER_SERVICES_TESTING=1 \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/user-services" >/dev/null 2>&1; then
  fail "user-service deployment accepted a symbolic-link native unit"
fi
[[ $(<"$unsafe_target") == "external service" ]] ||
  fail "user-service deployment followed a symbolic link"
[[ ! -e $unsafe_unit_root/qvos-battery-monitor.timer ]] ||
  fail "user-service deployment mutated before completing preflight"

grep -Fq 'NoNewPrivileges=yes' \
  "$root/qvcore/config/files/systemd/user/qvos-battery-monitor.service" ||
  fail "battery monitor service hardening"
grep -Fq 'ConditionPathExists=%h/.local/state/qvos/toggles/' \
  "$root/qvcore/config/files/systemd/user/qvos-recover-internal-monitor.service" ||
  fail "monitor recovery native state condition"
grep -Fq 'ExecStart=/usr/bin/swayosd-server' \
  "$root/qvcore/config/files/systemd/user/qvos-swayosd-server.service" ||
  fail "SwayOSD native user-service owner"
[[ ! -e $root/qvcore/config/files/systemd/user/swayosd-server.service ]] ||
  fail "inherited SwayOSD user-service identity remains"
printf 'ok - qvOS user services deploy atomically with native identity\n'
