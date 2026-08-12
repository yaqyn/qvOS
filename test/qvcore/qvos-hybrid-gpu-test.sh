#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
system_root="$test_root/system"
user_system_root="$test_root/user-system"
rollback_system_root="$test_root/rollback-system"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"
service_state="$test_root/service-state"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$system_root/test-bin" \
  "$user_system_root/test-bin" \
  "$rollback_system_root/test-bin" \
  "$test_bin"
printf 'disabled\n' >"$service_state"
: >"$action_log"

install -m 0755 /dev/stdin "$system_root/test-bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
if [[ ${QVOS_TEST_SYSTEMCTL_FAIL:-} == "$1" ]]; then
  exit 1
fi
case ${1:-} in
is-enabled)
  [[ $(<"$QVOS_TEST_SERVICE_STATE") == "enabled" ]]
  ;;
enable)
  printf 'enabled\n' >"$QVOS_TEST_SERVICE_STATE"
  ;;
disable)
  printf 'disabled\n' >"$QVOS_TEST_SERVICE_STATE"
  ;;
daemon-reload) ;;
*) exit 2 ;;
esac
STUB
install -m 0755 "$system_root/test-bin/systemctl" \
  "$user_system_root/test-bin/systemctl"
install -m 0755 "$system_root/test-bin/systemctl" \
  "$rollback_system_root/test-bin/systemctl"

run_install_root() {
  QVOS_HYBRID_GPU_TESTING=1 \
  QVOS_HYBRID_GPU_SYSTEM_ROOT="$1" \
    "$root/qvcore/gaming/hybrid-gpu-install-root"
}

run_root_owner() {
  local fixture_root=$1
  local fixture_systemctl="$fixture_root/test-bin/systemctl"
  shift

  QVOS_HYBRID_GPU_TESTING=1 \
  QVOS_HYBRID_GPU_SYSTEM_ROOT="$fixture_root" \
  QVOS_HYBRID_GPU_TEST_SYSTEMCTL="$fixture_systemctl" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  QVOS_TEST_SERVICE_STATE="$service_state" \
  QVOS_TEST_SYSTEMCTL_FAIL="${QVOS_TEST_SYSTEMCTL_FAIL:-}" \
    "$fixture_root/usr/lib/qvos/gaming/hybrid-gpu/apply" "$@"
}

if QVOS_HYBRID_GPU_SYSTEM_ROOT="$system_root" \
  "$root/qvcore/gaming/hybrid-gpu-install-root" >/dev/null 2>&1; then
  fail "Hybrid GPU fixture root worked outside test mode"
fi
if QVOS_HYBRID_GPU_TESTING=1 QVOS_HYBRID_GPU_SYSTEM_ROOT=/ \
  "$root/qvcore/gaming/hybrid-gpu-install-root" >/dev/null 2>&1; then
  fail "live root was accepted as a Hybrid GPU fixture"
fi

run_install_root "$system_root"
helper_dir="$system_root/usr/lib/qvos/gaming/hybrid-gpu"
for helper in apply force-igpu; do
  [[ $(stat -c '%a' -- "$helper_dir/$helper") == "755" ]] ||
    fail "Hybrid GPU executable payload mode: $helper"
done
for payload in default.json delay-start.conf; do
  [[ $(stat -c '%a' -- "$helper_dir/$payload") == "644" ]] ||
    fail "Hybrid GPU data payload mode: $payload"
done

install -D -m 0644 /dev/stdin "$system_root/etc/supergfxd.conf" <<'CONFIG'
{
  "mode": "Hybrid",
  "vfio_enable": false,
  "custom_qvos_test": 42
}
CONFIG
historical_sleep="$system_root/usr/lib/systemd/system-sleep/force-igpu"
historical_delay="$system_root/etc/systemd/system/supergfxd.service.d/delay-start.conf"
install -D -m 0755 /dev/stdin "$historical_sleep" <<'SCRIPT'
#!/bin/bash
printf 'foreign\n'
SCRIPT
install -D -m 0644 /dev/stdin "$historical_delay" <<'POLICY'
[Service]
ExecStartPre=/usr/bin/true
POLICY
historical_sleep_hash=$(sha256sum -- "$historical_sleep")
historical_delay_hash=$(sha256sum -- "$historical_delay")

run_root_owner "$system_root" integrated
config="$system_root/etc/supergfxd.conf"
sleep_policy="$system_root/usr/lib/systemd/system-sleep/qvos-hybrid-gpu"
delay_policy="$system_root/etc/systemd/system/supergfxd.service.d/80-qvos-integrated-delay.conf"
[[ $(jq -r '.mode' "$config") == "Integrated" ]] ||
  fail "Integrated mode publication"
jq -e '.vfio_enable == true and .custom_qvos_test == 42' "$config" >/dev/null ||
  fail "Hybrid GPU config preservation"
cmp -s "$helper_dir/force-igpu" "$sleep_policy" ||
  fail "Integrated sleep policy"
cmp -s "$helper_dir/delay-start.conf" "$delay_policy" ||
  fail "Integrated service delay"
[[ $(sha256sum -- "$historical_sleep") == "$historical_sleep_hash" &&
  $(sha256sum -- "$historical_delay") == "$historical_delay_hash" ]] ||
  fail "native Hybrid GPU policy mutated historical paths"
[[ $(<"$service_state") == "enabled" ]] ||
  fail "supergfxd service enablement"

set +e
run_root_owner "$system_root" integrated >/dev/null
idempotent_status=$?
set -e
((idempotent_status == 10)) || fail "Integrated idempotent status"

run_root_owner "$system_root" hybrid
[[ $(jq -r '.mode' "$config") == "Hybrid" ]] ||
  fail "Hybrid mode publication"
jq -e '.custom_qvos_test == 42' "$config" >/dev/null ||
  fail "Hybrid mode custom config preservation"
[[ ! -e $sleep_policy && ! -L $sleep_policy ]] ||
  fail "Hybrid mode sleep policy removal"
[[ ! -e $delay_policy && ! -L $delay_policy ]] ||
  fail "Hybrid mode service delay removal"
[[ $(sha256sum -- "$historical_sleep") == "$historical_sleep_hash" &&
  $(sha256sum -- "$historical_delay") == "$historical_delay_hash" ]] ||
  fail "Hybrid mode mutated historical policy paths"

run_root_owner "$system_root" integrated
printf 'foreign\n' >"$sleep_policy"
config_before=$(sha256sum -- "$config")
if run_root_owner "$system_root" hybrid >/dev/null 2>&1; then
  fail "modified Hybrid GPU policy was replaced"
fi
[[ $(sha256sum -- "$config") == "$config_before" &&
  $(<"$sleep_policy") == "foreign" ]] ||
  fail "modified-policy preflight preceded mutation"
install -m 0755 "$helper_dir/force-igpu" "$sleep_policy"

config_before=$(sha256sum -- "$config")
sleep_before=$(sha256sum -- "$sleep_policy")
QVOS_TEST_SYSTEMCTL_FAIL=daemon-reload
export QVOS_TEST_SYSTEMCTL_FAIL
if run_root_owner "$system_root" hybrid >/dev/null 2>&1; then
  fail "systemd reload failure was accepted"
fi
unset QVOS_TEST_SYSTEMCTL_FAIL
[[ $(sha256sum -- "$config") == "$config_before" &&
  $(sha256sum -- "$sleep_policy") == "$sleep_before" ]] ||
  fail "Hybrid GPU rollback after systemd failure"

external_config="$test_root/external-supergfxd.conf"
printf '{"mode":"External"}\n' >"$external_config"
rm -- "$config"
ln -s "$external_config" "$config"
if run_root_owner "$system_root" hybrid >/dev/null 2>&1; then
  fail "symbolic-link Hybrid GPU config was accepted"
fi
[[ $(<"$external_config") == '{"mode":"External"}' ]] ||
  fail "external Hybrid GPU config changed"

run_install_root "$rollback_system_root"
printf 'disabled\n' >"$service_state"
QVOS_TEST_SYSTEMCTL_FAIL=enable
export QVOS_TEST_SYSTEMCTL_FAIL
if run_root_owner "$rollback_system_root" integrated >/dev/null 2>&1; then
  fail "supergfxd enable failure was accepted"
fi
unset QVOS_TEST_SYSTEMCTL_FAIL
[[ ! -e $rollback_system_root/etc/supergfxd.conf &&
  ! -e $rollback_system_root/usr/lib/systemd/system-sleep/qvos-hybrid-gpu &&
  ! -e $rollback_system_root/etc/systemd/system/supergfxd.service.d/80-qvos-integrated-delay.conf &&
  $(<"$service_state") == "disabled" ]] ||
  fail "Hybrid GPU rollback after service enablement failure"

install -m 0755 /dev/stdin "$test_bin/qv-hw-hybrid-gpu" <<'STUB'
#!/bin/bash
[[ ${QVOS_TEST_HARDWARE:-present} == "present" ]]
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-missing" <<'STUB'
#!/bin/bash
[[ ${QVOS_TEST_PACKAGE_MISSING:-0} == "1" ]]
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'STUB'
#!/bin/bash
printf 'package-add:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/gum" <<'STUB'
#!/bin/bash
[[ ${1:-} == "confirm" ]] || exit 2
printf 'confirm:%s\n' "${2:-}" >>"$QVOS_TEST_ACTION_LOG"
[[ ${QVOS_TEST_CONFIRM:-yes} == "yes" ]]
STUB
install -m 0755 /dev/stdin "$test_bin/supergfxctl" <<'STUB'
#!/bin/bash
case ${1:-} in
-P) printf '%s\n' "${QVOS_TEST_PENDING_MODE:-None}" ;;
-g) printf '%s\n' "${QVOS_TEST_GPU_MODE:-Hybrid}" ;;
*) exit 2 ;;
esac
STUB
install -m 0755 /dev/stdin "$test_bin/qv-system-reboot" <<'STUB'
#!/bin/bash
printf 'reboot\n' >>"$QVOS_TEST_ACTION_LOG"
STUB

run_toggle() {
  PATH="$test_bin:/usr/bin" \
  QVOS_PATH="$root" \
  QVOS_HYBRID_GPU_TESTING=1 \
  QVOS_HYBRID_GPU_SYSTEM_ROOT="$user_system_root" \
  QVOS_HYBRID_GPU_TEST_SYSTEMCTL="$user_system_root/test-bin/systemctl" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  QVOS_TEST_SERVICE_STATE="$service_state" \
  QVOS_TEST_HARDWARE="${QVOS_TEST_HARDWARE:-present}" \
  QVOS_TEST_PACKAGE_MISSING="${QVOS_TEST_PACKAGE_MISSING:-0}" \
  QVOS_TEST_CONFIRM="${QVOS_TEST_CONFIRM:-yes}" \
  QVOS_TEST_PENDING_MODE="${QVOS_TEST_PENDING_MODE:-None}" \
  QVOS_TEST_GPU_MODE="${QVOS_TEST_GPU_MODE:-Hybrid}" \
    "$@"
}

printf 'disabled\n' >"$service_state"
: >"$action_log"
QVOS_TEST_PACKAGE_MISSING=1 run_toggle \
  "$root/bin/qv-toggle-hybrid-gpu" >/dev/null
grep -Fqx 'package-add:supergfxctl' "$action_log" ||
  fail "on-demand supergfxctl install"
grep -Fqx 'reboot' "$action_log" || fail "initial Hybrid GPU reboot"
[[ $(jq -r '.mode' "$user_system_root/etc/supergfxd.conf") == "Hybrid" ]] ||
  fail "initial Hybrid GPU mode"

: >"$action_log"
QVOS_TEST_GPU_MODE=Hybrid run_toggle \
  "$root/bin/omarchy-toggle-hybrid-gpu" >/dev/null
[[ $(jq -r '.mode' "$user_system_root/etc/supergfxd.conf") == "Integrated" ]] ||
  fail "compatibility adapter integrated transition"
grep -Fqx 'reboot' "$action_log" || fail "integrated transition reboot"

config_before=$(sha256sum -- "$user_system_root/etc/supergfxd.conf")
: >"$action_log"
set +e
QVOS_TEST_CONFIRM=no QVOS_TEST_GPU_MODE=Integrated run_toggle \
  "$root/bin/qv-toggle-hybrid-gpu" >/dev/null 2>&1
cancel_status=$?
set -e
((cancel_status == 130)) || fail "Hybrid GPU cancellation status"
[[ $(sha256sum -- "$user_system_root/etc/supergfxd.conf") == "$config_before" &&
  -z $(sed -n '/^reboot$/p' "$action_log") ]] ||
  fail "Hybrid GPU cancellation mutated state"

if QVOS_TEST_PENDING_MODE=Hybrid run_toggle \
  "$root/bin/qv-toggle-hybrid-gpu" >/dev/null 2>&1; then
  fail "pending Hybrid GPU mode was replaced"
fi
if QVOS_TEST_GPU_MODE=Vfio run_toggle \
  "$root/bin/qv-toggle-hybrid-gpu" >/dev/null 2>&1; then
  fail "unsupported Hybrid GPU mode was replaced"
fi
if QVOS_TEST_HARDWARE=absent run_toggle \
  "$root/bin/qv-toggle-hybrid-gpu" >/dev/null 2>&1; then
  fail "unsupported hardware reached Hybrid GPU mutation"
fi

printf 'ok - optional Hybrid GPU policy is confirmed, atomic, and rollback-safe\n'
