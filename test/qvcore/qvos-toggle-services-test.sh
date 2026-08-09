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
  "$test_home/.config/hypr" \
  "$test_home/.local/state/omarchy/toggles/hypr" \
  "$test_home/.local/state/qvos/toggles/hypr"
install -m 0644 /dev/stdin \
  "$test_home/.config/hypr/hyprland.conf" <<'CONFIG'
source = ~/.config/hypr/bindings.conf
source = ~/.local/state/omarchy/toggles/hypr/*.conf
# user content stays here
CONFIG
printf 'legacy-only\n' >"$test_home/.local/state/omarchy/toggles/suspend-off"
printf 'shared\n' >"$test_home/.local/state/omarchy/toggles/hypr/shared.conf"
printf 'shared\n' >"$test_home/.local/state/qvos/toggles/hypr/shared.conf"

HOME="$test_home" QVOS_PATH="$root" "$root/qvcore/config/toggle-state"
[[ ! -e $test_home/.local/state/omarchy/toggles ]] ||
  fail "legacy toggle root survived migration"
grep -Fqx 'legacy-only' "$test_home/.local/state/qvos/toggles/suspend-off" ||
  fail "legacy toggle state was not preserved"
grep -Fqx 'shared' "$test_home/.local/state/qvos/toggles/hypr/shared.conf" ||
  fail "identical toggle state was not deduplicated"
grep -Fqx 'source = ~/.local/state/qvos/toggles/hypr/*.conf' \
  "$test_home/.config/hypr/hyprland.conf" ||
  fail "active Hyprland toggle source was not migrated"
grep -Fqx '# user content stays here' "$test_home/.config/hypr/hyprland.conf" ||
  fail "custom Hyprland content was not preserved"
[[ $(find "$test_home/.config/hypr" -name 'hyprland.conf.bak.*' | wc -l) == "1" ]] ||
  fail "Hyprland toggle source backup count"
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
hypr_snapshot=$(find "$test_home/.config/hypr" -printf '%P|%m|%i|%T@\n' | sort)
HOME="$test_home" QVOS_PATH="$root" "$root/qvcore/config/toggle-state"
[[ $(find "$test_home/.local/state/qvos/toggles" \
  -printf '%P|%m|%i|%T@\n' | sort) == "$toggle_snapshot" ]] ||
  fail "toggle-state migration is not idempotent"
[[ $(find "$test_home/.config/hypr" -printf '%P|%m|%i|%T@\n' | sort) == \
  "$hypr_snapshot" ]] || fail "Hyprland source migration is not idempotent"

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
  "$root/qvcore/config/toggles/window-no-gaps.conf" \
  "$test_home/.local/state/qvos/toggles/hypr/window-no-gaps.conf" ||
  fail "native Hyprland toggle template was not applied exactly"
[[ $(stat -c '%a' "$test_home/.local/state/qvos/toggles/hypr/window-no-gaps.conf") == "600" ]] ||
  fail "native Hyprland toggle is not private"
HOME="$test_home" \
  QVOS_PATH="$root" \
  QVOS_TEST_HYPRCTL_LOG="$hyprctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/hyprland-toggle" window-no-gaps
[[ ! -e $test_home/.local/state/qvos/toggles/hypr/window-no-gaps.conf ]] ||
  fail "native Hyprland toggle template was not removed"
[[ $(<"$hyprctl_log") == $'reload\nreload' ]] ||
  fail "Hyprland toggle reload count"

unsafe_home="$test_root/unsafe-home"
external_state="$test_root/external-state"
install -d "$unsafe_home/.local/state/omarchy"
printf 'external\n' >"$external_state"
ln -s "$external_state" "$unsafe_home/.local/state/omarchy/toggles"
if HOME="$unsafe_home" QVOS_PATH="$root" \
  "$root/qvcore/config/toggle-state" >/dev/null 2>&1; then
  fail "toggle-state migration accepted a symbolic-link root"
fi
[[ $(<"$external_state") == "external" ]] ||
  fail "toggle-state migration followed a symbolic link"
[[ ! -e $unsafe_home/.local/state/qvos ]] ||
  fail "toggle-state migration mutated before completing preflight"

conflict_home="$test_root/conflict-home"
install -d \
  "$conflict_home/.local/state/omarchy/toggles/hypr" \
  "$conflict_home/.local/state/qvos/toggles/hypr"
printf 'old\n' >"$conflict_home/.local/state/omarchy/toggles/hypr/custom.conf"
printf 'new\n' >"$conflict_home/.local/state/qvos/toggles/hypr/custom.conf"
if HOME="$conflict_home" QVOS_PATH="$root" \
  "$root/qvcore/config/toggle-state" >/dev/null 2>&1; then
  fail "toggle-state migration accepted conflicting state"
fi
[[ $(<"$conflict_home/.local/state/omarchy/toggles/hypr/custom.conf") == "old" &&
  $(<"$conflict_home/.local/state/qvos/toggles/hypr/custom.conf") == "new" ]] ||
  fail "toggle-state conflict changed user data"
printf 'ok - qvOS toggle state is private, preserving, idempotent, and traversal-safe\n'

service_home="$test_root/service-home"
unit_root="$service_home/.config/systemd/user"
install -d "$unit_root" "$test_bin"
: >"$systemctl_log"
for legacy_unit in \
  omarchy-battery-monitor.service \
  omarchy-battery-monitor.timer \
  omarchy-recover-internal-monitor.service; do
  printf 'legacy %s\n' "$legacy_unit" >"$unit_root/$legacy_unit"
done
printf 'old service backup\n' >"$unit_root/omarchy-battery-monitor.service.bak.1"
printf 'old timer backup\n' >"$unit_root/omarchy-battery-monitor.timer.bak.1"

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

unit_root="$HOME/.config/systemd/user"
case "$*" in
"--user is-enabled omarchy-battery-monitor.timer")
  [[ -f $unit_root/omarchy-battery-monitor.timer ]] && printf 'enabled\n' || printf 'disabled\n'
  ;;
"--user is-enabled omarchy-recover-internal-monitor.service")
  [[ -f $unit_root/omarchy-recover-internal-monitor.service ]] && printf 'enabled\n' || printf 'disabled\n'
  ;;
"--user is-enabled "* | "--user is-active "*)
  if [[ $* == "--user is-active omarchy-battery-monitor.timer" &&
    -f $unit_root/omarchy-battery-monitor.timer ]]; then
    printf 'active\n'
  else
    printf 'inactive\n'
  fi
  ;;
*)
  printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
  ;;
esac
SCRIPT

HOME="$service_home" \
  QVOS_PATH="$root" \
  QVOS_USER_SERVICES_TESTING=1 \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/user-services"
for native_unit in \
  qvos-battery-monitor.service \
  qvos-battery-monitor.timer \
  qvos-recover-internal-monitor.service; do
  cmp -s "$root/qvcore/config/files/systemd/user/$native_unit" "$unit_root/$native_unit" ||
    fail "native user service was not deployed exactly: $native_unit"
done
if find "$unit_root" -maxdepth 1 -name 'omarchy-*' -print -quit | grep -q .; then
  fail "legacy user-service files remain active"
fi
backup_root="$service_home/.local/state/qvos/backups/pre-native-user-services"
[[ $(find "$backup_root" -maxdepth 1 -type f | wc -l) == "5" ]] ||
  fail "legacy user-service archive count"
while IFS= read -r -d '' backup; do
  [[ $(stat -c '%a' "$backup") == "600" ]] ||
    fail "legacy user-service archive is not private"
done < <(find "$backup_root" -maxdepth 1 -type f -print0)
expected_systemctl=$(printf '%s\n' \
  '--user daemon-reload' \
  '--user enable qvos-battery-monitor.timer' \
  '--user start qvos-battery-monitor.timer' \
  '--user enable qvos-recover-internal-monitor.service' \
  '--user disable --now omarchy-battery-monitor.timer' \
  '--user stop omarchy-battery-monitor.service' \
  '--user disable --now omarchy-recover-internal-monitor.service' \
  '--user daemon-reload')
[[ $(<"$systemctl_log") == "$expected_systemctl" ]] ||
  fail "user-service state migration order"

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
ln -s "$unsafe_target" "$unsafe_unit_root/omarchy-battery-monitor.service"
if HOME="$unsafe_service_home" \
  QVOS_PATH="$root" \
  QVOS_USER_SERVICES_TESTING=1 \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/config/user-services" >/dev/null 2>&1; then
  fail "user-service migration accepted a symbolic-link legacy unit"
fi
[[ $(<"$unsafe_target") == "external service" ]] ||
  fail "user-service migration followed a symbolic link"
[[ ! -e $unsafe_unit_root/qvos-battery-monitor.service ]] ||
  fail "user-service migration mutated before completing preflight"

grep -Fq 'NoNewPrivileges=yes' \
  "$root/qvcore/config/files/systemd/user/qvos-battery-monitor.service" ||
  fail "battery monitor service hardening"
grep -Fq 'ConditionPathExists=%h/.local/state/qvos/toggles/' \
  "$root/qvcore/config/files/systemd/user/qvos-recover-internal-monitor.service" ||
  fail "monitor recovery native state condition"
printf 'ok - qvOS user services migrate atomically with native identity and preserved state\n'
