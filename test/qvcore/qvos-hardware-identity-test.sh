#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/install/hardware/identity"
z13_source="$root/qvcore/install/hardware/asus/z13-touchpad.rules"
apple_source="$root/qvcore/install/hardware/apple/qvos-nvme-suspend-fix.service"
intel_fred_source="$root/qvcore/install/hardware/intel/fred.conf"
intel_wifi_source="$root/qvcore/install/hardware/intel/iwlwifi-disable-eht.conf"
tuxedo_source="$root/qvcore/install/hardware/tuxedo/blacklist-clevo-xsm-wmi.conf"
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
install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ $# == 1 && $1 == "lspci" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/lspci" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_LSPCI:-}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'qv-pkg-add|%s\n' "$*" >>"$QVOS_TEST_HARDWARE_LOG"
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
  QVOS_HARDWARE_TESTING=1 \
  QVOS_HARDWARE_FIXTURE_ROOT="$fixture" \
  QVOS_TEST_LSPCI="${QVOS_TEST_LSPCI:-}" \
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
  QVOS_HARDWARE_TESTING=1 \
  QVOS_HARDWARE_FIXTURE_ROOT="$fixture" \
  QVOS_TEST_LSPCI="${QVOS_TEST_LSPCI:-}" \
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

intel_root="$test_root/intel"
prepare_root "$intel_root"
intel_inventory=$'00:02.0 VGA compatible controller: Intel Panther Lake Graphics [8086:1234]\n00:14.3 Network controller: Intel Corporation Device [8086:272b]'
QVOS_TEST_LSPCI="$intel_inventory" run_stage "$intel_root" \
  "$root/qvcore/install/config/hardware/intel/fred.sh"
QVOS_TEST_LSPCI="$intel_inventory" run_stage "$intel_root" \
  "$root/qvcore/install/config/hardware/intel/fix-wifi7-eht.sh"
intel_fred_target="$intel_root/etc/limine-entry-tool.d/intel-panther-lake-fred.conf"
intel_wifi_target="$intel_root/etc/modprobe.d/iwlwifi-disable-eht.conf"
cmp -s "$intel_fred_source" "$intel_fred_target" ||
  fail "native Intel FRED policy"
cmp -s "$intel_wifi_source" "$intel_wifi_target" ||
  fail "native Intel Wi-Fi EHT policy"
fred_inode=$(stat -c '%i' "$intel_fred_target")
wifi_inode=$(stat -c '%i' "$intel_wifi_target")
QVOS_TEST_LSPCI="$intel_inventory" run_stage "$intel_root" \
  "$root/qvcore/install/config/hardware/intel/fred.sh"
QVOS_TEST_LSPCI="$intel_inventory" run_stage "$intel_root" \
  "$root/qvcore/install/config/hardware/intel/fix-wifi7-eht.sh"
[[ $(stat -c '%i' "$intel_fred_target") == "$fred_inode" &&
  $(stat -c '%i' "$intel_wifi_target") == "$wifi_inode" ]] ||
  fail "idempotent native Intel hardware policy install"

unaffected_root="$test_root/unaffected"
prepare_root "$unaffected_root"
QVOS_TEST_LSPCI='00:02.0 VGA compatible controller: Intel Alder Lake Graphics' \
  run_stage "$unaffected_root" \
  "$root/qvcore/install/config/hardware/intel/fred.sh"
QVOS_TEST_LSPCI='00:14.3 Network controller: Realtek Device [10ec:b822]' \
  run_stage "$unaffected_root" \
  "$root/qvcore/install/config/hardware/intel/fix-wifi7-eht.sh"
[[ ! -e $unaffected_root/etc/limine-entry-tool.d/intel-panther-lake-fred.conf &&
  ! -e $unaffected_root/etc/modprobe.d/iwlwifi-disable-eht.conf ]] ||
  fail "Intel policy applied to unaffected hardware"

modified_intel_root="$test_root/modified-intel"
prepare_root "$modified_intel_root"
install -d "$modified_intel_root/etc/modprobe.d"
printf 'administrator policy\n' \
  >"$modified_intel_root/etc/modprobe.d/iwlwifi-disable-eht.conf"
if QVOS_TEST_LSPCI="$intel_inventory" run_stage "$modified_intel_root" \
  "$root/qvcore/install/config/hardware/intel/fix-wifi7-eht.sh" \
  >/dev/null 2>&1; then
  fail "modified Intel Wi-Fi policy was accepted"
fi
[[ $(<"$modified_intel_root/etc/modprobe.d/iwlwifi-disable-eht.conf") == \
  "administrator policy" ]] || fail "modified Intel Wi-Fi policy was changed"

tuxedo_root="$test_root/tuxedo"
prepare_root "$tuxedo_root"
install -d "$tuxedo_root/sys/class/dmi/id"
printf 'TUXEDO Computers GmbH\n' \
  >"$tuxedo_root/sys/class/dmi/id/sys_vendor"
: >"$event_log"
run_stage "$tuxedo_root" \
  "$root/qvcore/install/config/hardware/fix-tuxedo-backlight.sh"
tuxedo_target="$tuxedo_root/etc/modprobe.d/blacklist-clevo-xsm-wmi.conf"
cmp -s "$tuxedo_source" "$tuxedo_target" ||
  fail "native Tuxedo backlight policy"
grep -Fqx \
  'qv-pkg-add|linux-headers tuxedo-drivers-nocompatcheck-dkms' "$event_log" ||
  fail "Tuxedo driver package request"
tuxedo_inode=$(stat -c '%i' "$tuxedo_target")
run_stage "$tuxedo_root" \
  "$root/qvcore/install/config/hardware/fix-tuxedo-backlight.sh"
[[ $(stat -c '%i' "$tuxedo_target") == "$tuxedo_inode" ]] ||
  fail "idempotent native Tuxedo hardware policy install"

unaffected_tuxedo_root="$test_root/unaffected-tuxedo"
prepare_root "$unaffected_tuxedo_root"
install -d "$unaffected_tuxedo_root/sys/class/dmi/id"
printf 'Framework\n' \
  >"$unaffected_tuxedo_root/sys/class/dmi/id/sys_vendor"
: >"$event_log"
run_stage "$unaffected_tuxedo_root" \
  "$root/qvcore/install/config/hardware/fix-tuxedo-backlight.sh"
[[ ! -e $unaffected_tuxedo_root/etc/modprobe.d/blacklist-clevo-xsm-wmi.conf &&
  ! -s $event_log ]] || fail "Tuxedo policy applied to unrelated hardware"

modified_tuxedo_root="$test_root/modified-tuxedo"
prepare_root "$modified_tuxedo_root"
install -d "$modified_tuxedo_root/sys/class/dmi/id" \
  "$modified_tuxedo_root/etc/modprobe.d"
printf 'Slimbook\n' >"$modified_tuxedo_root/sys/class/dmi/id/sys_vendor"
printf 'administrator policy\n' \
  >"$modified_tuxedo_root/etc/modprobe.d/blacklist-clevo-xsm-wmi.conf"
if run_stage "$modified_tuxedo_root" \
  "$root/qvcore/install/config/hardware/fix-tuxedo-backlight.sh" \
  >/dev/null 2>&1; then
  fail "modified Tuxedo policy was accepted"
fi
[[ $(<"$modified_tuxedo_root/etc/modprobe.d/blacklist-clevo-xsm-wmi.conf") == \
  "administrator policy" ]] || fail "modified Tuxedo policy was changed"

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
if rg -n '/etc/default/limine|sudo[[:space:]]+tee' \
  "$root/qvcore/install/config/hardware/intel/fred.sh" \
  "$root/qvcore/install/config/hardware/intel/fix-wifi7-eht.sh"; then
  fail "Intel static policy bypasses the native root owner"
fi
if rg -n 'sudo[[:space:]]+tee|(/lib|/usr/lib)/modules/.+\.ko' \
  "$root/qvcore/install/config/hardware/fix-tuxedo-backlight.sh"; then
  fail "Tuxedo static policy bypasses the native root owner"
fi
if rg -n '(/lib|/usr/lib)/modules/.+\.ko|sudo[[:space:]]+rm.+\.ko' \
  "$root/qvcore/install/config/hardware"; then
  fail "fresh hardware setup deletes an unverified kernel module"
fi

"$root/qvcore/install/check" >/dev/null
"$root/qvcore/migrations/check" >/dev/null
printf 'ok - installed hardware policy is native, transactional, and preservation-safe\n'
