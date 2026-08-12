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
cmp -s "$z13_source" \
  "$fresh_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules" ||
  fail "native ASUS Z13 policy"
cmp -s "$apple_source" \
  "$fresh_root/etc/systemd/system/qvos-nvme-suspend-fix.service" ||
  fail "native Apple NVMe policy"
grep -Fqx 'systemctl|enable --now qvos-nvme-suspend-fix.service' "$event_log" ||
  fail "fresh Apple NVMe activation"

z13_inode=$(stat -c '%i' \
  "$fresh_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules")
apple_inode=$(stat -c '%i' \
  "$fresh_root/etc/systemd/system/qvos-nvme-suspend-fix.service")
QVOS_TEST_Z13=1 run_stage "$fresh_root" \
  "$root/qvcore/install/hardware/asus/z13-touchpad"
run_stage "$fresh_root" "$root/qvcore/install/hardware/apple/nvme-suspend"
[[ $(stat -c '%i' \
  "$fresh_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules") == \
  "$z13_inode" && $(stat -c '%i' \
  "$fresh_root/etc/systemd/system/qvos-nvme-suspend-fix.service") == \
  "$apple_inode" ]] || fail "idempotent native hardware policy install"
if run_owner "$fresh_root" migrate >/dev/null 2>&1; then
  fail "retired hardware migration mode remains available"
fi

chroot_root="$test_root/chroot"
prepare_root "$chroot_root"
install -d "$chroot_root/sys/class/dmi/id" \
  "$chroot_root/sys/bus/pci/devices/0000:01:00.0"
printf 'MacBook9,1\n' >"$chroot_root/sys/class/dmi/id/product_name"
: >"$chroot_root/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed"
: >"$event_log"
QVOS_CHROOT_INSTALL=1 run_stage "$chroot_root" \
  "$root/qvcore/install/hardware/apple/nvme-suspend"
grep -Fqx 'systemctl|enable qvos-nvme-suspend-fix.service' "$event_log" ||
  fail "target-chroot Apple NVMe enable"
if grep -Fq 'enable --now' "$event_log"; then
  fail "target-chroot Apple NVMe service started during construction"
fi

preserve_root="$test_root/preserve"
prepare_root "$preserve_root"
printf 'custom Z13 rule\n' \
  >"$preserve_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules"
: >"$event_log"
if QVOS_TEST_Z13=1 run_stage "$preserve_root" \
  "$root/qvcore/install/hardware/asus/z13-touchpad" >/dev/null 2>&1; then
  fail "modified native hardware policy was accepted"
fi
[[ $(<"$preserve_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules") == \
  "custom Z13 rule" && ! -s $event_log ]] ||
  fail "modified native hardware policy was changed"

udev_rollback_root="$test_root/udev-rollback"
prepare_root "$udev_rollback_root"
if QVOS_TEST_UDEVADM_FAIL=1 \
  QVOS_TEST_Z13=1 run_stage "$udev_rollback_root" \
  "$root/qvcore/install/hardware/asus/z13-touchpad" >/dev/null 2>&1; then
  fail "udev activation failure was hidden"
fi
[[ ! -e $udev_rollback_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules ]] ||
  fail "udev activation failure did not roll back"

existing_root="$test_root/existing"
prepare_root "$existing_root"
install -m 0644 "$z13_source" \
  "$existing_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules"
if QVOS_TEST_UDEVADM_FAIL=1 \
  QVOS_TEST_Z13=1 run_stage "$existing_root" \
  "$root/qvcore/install/hardware/asus/z13-touchpad" >/dev/null 2>&1; then
  fail "existing-policy activation failure was hidden"
fi
cmp -s "$z13_source" \
  "$existing_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules" ||
  fail "existing native hardware policy was rolled back"

service_rollback_root="$test_root/service-rollback"
prepare_root "$service_rollback_root"
install -d "$service_rollback_root/sys/class/dmi/id" \
  "$service_rollback_root/sys/bus/pci/devices/0000:01:00.0"
printf 'MacBookPro13,1\n' \
  >"$service_rollback_root/sys/class/dmi/id/product_name"
: >"$service_rollback_root/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed"
if QVOS_TEST_SYSTEMCTL_FAIL_ENABLE=qvos-nvme-suspend-fix.service \
  run_stage "$service_rollback_root" \
  "$root/qvcore/install/hardware/apple/nvme-suspend" >/dev/null 2>&1; then
  fail "service activation failure was hidden"
fi
[[ ! -e $service_rollback_root/etc/systemd/system/qvos-nvme-suspend-fix.service &&
  ! -e $service_rollback_root/run/services/qvos-nvme-suspend-fix.service ]] ||
  fail "service activation failure did not roll back"

linked_root="$test_root/linked"
prepare_root "$linked_root"
outside="$test_root/outside-rule"
printf 'outside\n' >"$outside"
ln -s "$outside" \
  "$linked_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules"
if QVOS_TEST_Z13=1 run_stage "$linked_root" \
  "$root/qvcore/install/hardware/asus/z13-touchpad" >/dev/null 2>&1; then
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
  "$root/qvcore/install" --glob '!AGENTS.md' --glob '!check'; then
  fail "active installer hardware identity remains inherited"
fi

"$root/qvcore/install/check" >/dev/null
"$root/qvcore/migrations/check" >/dev/null
printf 'ok - installed hardware policy is native, transactional, and preservation-safe\n'
