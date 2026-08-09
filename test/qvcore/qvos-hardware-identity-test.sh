#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/install/hardware/identity"
z13_source="$root/qvcore/install/hardware/asus/z13-touchpad.rules"
apple_source="$root/qvcore/install/hardware/apple/qvos-nvme-suspend-fix.service"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
event_log="$test_root/events.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/udevadm" <<'SCRIPT'
#!/bin/bash
printf 'udevadm|%s\n' "$*" >>"$QVOS_TEST_HARDWARE_LOG"
[[ ${QVOS_TEST_UDEVADM_FAIL:-0} != "1" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

printf 'systemctl|%s\n' "$*" >>"$QVOS_TEST_HARDWARE_LOG"
action=${1:-}
shift || true
case $action in
daemon-reload)
  [[ ${QVOS_TEST_SYSTEMCTL_FAIL_RELOAD:-0} != "1" ]]
  ;;
is-enabled)
  [[ ${1:-} != "--quiet" ]] || shift
  [[ -f $QVOS_TEST_SERVICE_STATE/${1:-missing} ]]
  ;;
enable)
  [[ ${1:-} != "--now" ]] || shift
  service=${1:-}
  if [[ ${QVOS_TEST_SYSTEMCTL_FAIL_ENABLE:-} == "$service" ]]; then
    exit 1
  fi
  touch "$QVOS_TEST_SERVICE_STATE/$service"
  ;;
disable)
  rm -f -- "$QVOS_TEST_SERVICE_STATE/${1:-missing}"
  ;;
*) exit 2 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-hw-asus-rog" <<'SCRIPT'
#!/bin/bash
[[ ${QVOS_TEST_Z13:-0} == "1" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-hw-match" <<'SCRIPT'
#!/bin/bash
[[ ${QVOS_TEST_Z13:-0} == "1" && ${1:-} == "GZ302" ]]
SCRIPT

prepare_root() {
  local fixture=$1

  install -d \
    "$fixture/etc/udev/rules.d" \
    "$fixture/etc/systemd/system" \
    "$fixture/run/services"
}

write_legacy_apple() {
  local target=$1
  local product=${2:-qvOS}

  install -m 0644 /dev/stdin "$target" <<SERVICE
[Unit]
Description=$product NVMe Suspend Fix for MacBook

[Service]
ExecStart=/bin/bash -c 'echo 0 > /sys/bus/pci/devices/0000\:01\:00.0/d3cold_allowed'

[Install]
WantedBy=multi-user.target
SERVICE
}

run_owner() {
  local fixture=$1
  shift

  QVOS_PATH="$root" \
  QVOS_INSTALL_HARDWARE_TESTING=1 \
  QVOS_INSTALL_HARDWARE_SYSTEM_ROOT="$fixture" \
  QVOS_INSTALL_UDEVADM="$test_bin/udevadm" \
  QVOS_INSTALL_SYSTEMCTL="$test_bin/systemctl" \
  QVOS_TEST_HARDWARE_LOG="$event_log" \
  QVOS_TEST_SERVICE_STATE="$fixture/run/services" \
  PATH="$test_bin:/usr/bin" \
    "$owner" "$@"
}

run_stage() {
  local fixture=$1
  local stage=$2

  QVOS_PATH="$root" \
  QVOS_INSTALL_HARDWARE_TESTING=1 \
  QVOS_INSTALL_HARDWARE_SYSTEM_ROOT="$fixture" \
  QVOS_INSTALL_UDEVADM="$test_bin/udevadm" \
  QVOS_INSTALL_SYSTEMCTL="$test_bin/systemctl" \
  QVOS_TEST_HARDWARE_LOG="$event_log" \
  QVOS_TEST_SERVICE_STATE="$fixture/run/services" \
  PATH="$test_bin:/usr/bin" \
    bash -c 'source "$1"' _ "$stage"
}

exact_root="$test_root/exact"
prepare_root "$exact_root"
install -m 0644 "$z13_source" \
  "$exact_root/etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules"
write_legacy_apple \
  "$exact_root/etc/systemd/system/omarchy-nvme-suspend-fix.service"
touch "$exact_root/run/services/omarchy-nvme-suspend-fix.service"
: >"$event_log"
run_owner "$exact_root" migrate
cmp -s "$z13_source" \
  "$exact_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules" ||
  fail "native ASUS Z13 policy"
cmp -s "$apple_source" \
  "$exact_root/etc/systemd/system/qvos-nvme-suspend-fix.service" ||
  fail "native Apple NVMe policy"
for legacy in \
  etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules \
  etc/systemd/system/omarchy-nvme-suspend-fix.service; do
  [[ ! -e $exact_root/$legacy && ! -L $exact_root/$legacy ]] ||
    fail "exact legacy hardware policy remains: $legacy"
  [[ ! -e $exact_root/$legacy.qvos-identity-backup ]] ||
    fail "hardware identity transaction artifact remains: $legacy"
done
[[ -f $exact_root/run/services/qvos-nvme-suspend-fix.service &&
  ! -e $exact_root/run/services/omarchy-nvme-suspend-fix.service ]] ||
  fail "Apple NVMe service enable state migration"
grep -Fqx 'udevadm|control --reload-rules' "$event_log" ||
  fail "ASUS Z13 udev activation"
grep -Fqx 'systemctl|enable qvos-nvme-suspend-fix.service' "$event_log" ||
  fail "Apple NVMe native service enable"
grep -Fqx 'systemctl|disable omarchy-nvme-suspend-fix.service' "$event_log" ||
  fail "Apple NVMe legacy service disable"

state_before=$(find "$exact_root" -printf '%P|%y|%m|%i|%T@\n' | sort)
events_before=$(<"$event_log")
run_owner "$exact_root" migrate
[[ $(find "$exact_root" -printf '%P|%y|%m|%i|%T@\n' | sort) == \
  "$state_before" && $(<"$event_log") == "$events_before" ]] ||
  fail "idempotent hardware identity migration"

historical_root="$test_root/historical"
prepare_root "$historical_root"
write_legacy_apple \
  "$historical_root/etc/systemd/system/omarchy-nvme-suspend-fix.service" \
  Omarchy
: >"$event_log"
run_owner "$historical_root" migrate
[[ -f $historical_root/etc/systemd/system/qvos-nvme-suspend-fix.service &&
  ! -e $historical_root/etc/systemd/system/omarchy-nvme-suspend-fix.service &&
  ! -e $historical_root/run/services/qvos-nvme-suspend-fix.service ]] ||
  fail "exact historical Apple policy migration"

fresh_root="$test_root/fresh"
prepare_root "$fresh_root"
install -d "$fresh_root/sys/class/dmi/id" \
  "$fresh_root/sys/bus/pci/devices/0000:01:00.0"
printf 'MacBookPro14,3\n' >"$fresh_root/sys/class/dmi/id/product_name"
: >"$fresh_root/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed"
: >"$event_log"
QVOS_TEST_Z13=1 run_stage "$fresh_root" \
  "$root/qvcore/install/hardware/asus/z13-touchpad"
run_stage "$fresh_root" "$root/qvcore/install/hardware/apple/nvme-suspend"
[[ -f $fresh_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules &&
  -f $fresh_root/etc/systemd/system/qvos-nvme-suspend-fix.service ]] ||
  fail "fresh hardware policy installation"
grep -Fqx 'systemctl|enable --now qvos-nvme-suspend-fix.service' "$event_log" ||
  fail "fresh Apple NVMe activation"

chroot_root="$test_root/chroot"
prepare_root "$chroot_root"
install -d "$chroot_root/sys/class/dmi/id" \
  "$chroot_root/sys/bus/pci/devices/0000:01:00.0"
printf 'MacBook9,1\n' >"$chroot_root/sys/class/dmi/id/product_name"
: >"$chroot_root/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed"
: >"$event_log"
OMARCHY_CHROOT_INSTALL=1 run_stage "$chroot_root" \
  "$root/qvcore/install/hardware/apple/nvme-suspend"
grep -Fqx 'systemctl|enable qvos-nvme-suspend-fix.service' "$event_log" ||
  fail "target-chroot Apple NVMe enable"
if grep -Fq 'enable --now' "$event_log"; then
  fail "target-chroot Apple NVMe service started during construction"
fi

preserve_root="$test_root/preserve"
prepare_root "$preserve_root"
printf 'custom Z13 rule\n' \
  >"$preserve_root/etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules"
printf 'custom Apple unit\n' \
  >"$preserve_root/etc/systemd/system/omarchy-nvme-suspend-fix.service"
: >"$event_log"
run_owner "$preserve_root" migrate >/dev/null 2>&1
[[ ! -e $preserve_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules &&
  ! -e $preserve_root/etc/systemd/system/qvos-nvme-suspend-fix.service &&
  ! -s $event_log ]] ||
  fail "modified legacy hardware policy received a native competitor"

udev_rollback_root="$test_root/udev-rollback"
prepare_root "$udev_rollback_root"
install -m 0644 "$z13_source" \
  "$udev_rollback_root/etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules"
if QVOS_TEST_UDEVADM_FAIL=1 \
  run_owner "$udev_rollback_root" migrate >/dev/null 2>&1; then
  fail "udev activation failure was hidden"
fi
[[ -f $udev_rollback_root/etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules &&
  ! -e $udev_rollback_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules ]] ||
  fail "udev activation failure did not roll back"

service_rollback_root="$test_root/service-rollback"
prepare_root "$service_rollback_root"
write_legacy_apple \
  "$service_rollback_root/etc/systemd/system/omarchy-nvme-suspend-fix.service"
touch "$service_rollback_root/run/services/omarchy-nvme-suspend-fix.service"
if QVOS_TEST_SYSTEMCTL_FAIL_ENABLE=qvos-nvme-suspend-fix.service \
  run_owner "$service_rollback_root" migrate >/dev/null 2>&1; then
  fail "service activation failure was hidden"
fi
[[ -f $service_rollback_root/etc/systemd/system/omarchy-nvme-suspend-fix.service &&
  ! -e $service_rollback_root/etc/systemd/system/qvos-nvme-suspend-fix.service &&
  -f $service_rollback_root/run/services/omarchy-nvme-suspend-fix.service &&
  ! -e $service_rollback_root/run/services/qvos-nvme-suspend-fix.service ]] ||
  fail "service activation failure did not roll back"

linked_root="$test_root/linked"
prepare_root "$linked_root"
outside="$test_root/outside-rule"
printf 'outside\n' >"$outside"
install -m 0644 "$z13_source" \
  "$linked_root/etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules"
ln -s "$outside" \
  "$linked_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules"
if run_owner "$linked_root" migrate >/dev/null 2>&1; then
  fail "linked native hardware target was accepted"
fi
[[ $(<"$outside") == "outside" ]] ||
  fail "linked native hardware target was followed"

grep -Fqx 'NoNewPrivileges=yes' "$apple_source" ||
  fail "Apple NVMe service privilege hardening"
grep -Fqx 'ProtectSystem=strict' "$apple_source" ||
  fail "Apple NVMe service filesystem hardening"
grep -Fqx 'ReadWritePaths=/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed' \
  "$apple_source" || fail "Apple NVMe service bounded sysfs write"
if rg -n '99-omarchy-asus-z13-touchpad|omarchy-nvme-suspend-fix' \
  "$root/qvcore/install" --glob '!AGENTS.md' --glob '!check' \
  --glob '!identity'; then
  fail "active installer hardware identity remains inherited"
fi

"$root/qvcore/install/check" >/dev/null
"$root/qvcore/migrations/check" >/dev/null
printf 'ok - installed hardware policy is native, transactional, and preservation-safe\n'
