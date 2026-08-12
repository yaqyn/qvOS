#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/install/hardware/identity"
z13_source="$root/qvcore/install/hardware/asus/z13-touchpad.rules"
apple_source="$root/qvcore/install/hardware/apple/qvos-nvme-suspend-fix.service"
apple_spi_macbook8_source="$root/qvcore/install/hardware/apple/spi-macbook8.conf"
apple_spi_modern_source="$root/qvcore/install/hardware/apple/spi-modern.conf"
asus_b9406_display_source="$root/qvcore/install/hardware/asus/b9406-display.conf"
asus_b9406_touchpad_source="$root/qvcore/install/hardware/asus/b9406-touchpad.quirks"
asus_ptl_backlight_source="$root/qvcore/install/hardware/asus/ptl-backlight.conf"
hid_apple_source="$root/qvcore/install/hardware/input/hid-apple-fkeys.conf"
synaptics_source="$root/qvcore/install/hardware/input/psmouse-synaptics.conf"
intel_fred_source="$root/qvcore/install/hardware/intel/fred.conf"
intel_wifi_source="$root/qvcore/install/hardware/intel/iwlwifi-disable-eht.conf"
nvidia_modprobe_source="$root/qvcore/install/hardware/nvidia/modprobe.conf"
nvidia_mkinitcpio_source="$root/qvcore/install/hardware/nvidia/mkinitcpio.conf"
lenovo_yoga_source="$root/qvcore/install/hardware/lenovo/yoga-pro7-bass.conf"
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
run_stage "$fresh_root" "$root/qvcore/install/config/hardware/fix-fkeys.sh"
[[ -f $fresh_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules &&
  -f $fresh_root/etc/systemd/system/qvos-nvme-suspend-fix.service &&
  -f $fresh_root/etc/modprobe.d/qvos-hid-apple-fkeys.conf ]] ||
  fail "fresh hardware policy installation"
cmp -s "$z13_source" \
  "$fresh_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules" ||
  fail "native ASUS Z13 policy"
cmp -s "$apple_source" \
  "$fresh_root/etc/systemd/system/qvos-nvme-suspend-fix.service" ||
  fail "native Apple NVMe policy"
cmp -s "$hid_apple_source" \
  "$fresh_root/etc/modprobe.d/qvos-hid-apple-fkeys.conf" ||
  fail "native hid_apple function-key policy"
grep -Fqx 'systemctl|enable --now qvos-nvme-suspend-fix.service' "$event_log" ||
  fail "fresh Apple NVMe activation"

z13_inode=$(stat -c '%i' \
  "$fresh_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules")
apple_inode=$(stat -c '%i' \
  "$fresh_root/etc/systemd/system/qvos-nvme-suspend-fix.service")
hid_apple_inode=$(stat -c '%i' \
  "$fresh_root/etc/modprobe.d/qvos-hid-apple-fkeys.conf")
QVOS_TEST_Z13=1 run_stage "$fresh_root" \
  "$root/qvcore/install/hardware/asus/z13-touchpad"
run_stage "$fresh_root" "$root/qvcore/install/hardware/apple/nvme-suspend"
run_stage "$fresh_root" "$root/qvcore/install/config/hardware/fix-fkeys.sh"
[[ $(stat -c '%i' \
  "$fresh_root/etc/udev/rules.d/99-qvos-asus-z13-touchpad.rules") == \
  "$z13_inode" && $(stat -c '%i' \
  "$fresh_root/etc/systemd/system/qvos-nvme-suspend-fix.service") == \
  "$apple_inode" && \
  $(stat -c '%i' \
  "$fresh_root/etc/modprobe.d/qvos-hid-apple-fkeys.conf") == \
  "$hid_apple_inode" ]] || fail "idempotent native hardware policy install"
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
intel_fred_target="$intel_root/etc/limine-entry-tool.d/90-qvos-intel-fred.conf"
intel_wifi_target="$intel_root/etc/modprobe.d/qvos-intel-wifi7-eht.conf"
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
[[ ! -e $unaffected_root/etc/limine-entry-tool.d/90-qvos-intel-fred.conf &&
  ! -e $unaffected_root/etc/modprobe.d/qvos-intel-wifi7-eht.conf ]] ||
  fail "Intel policy applied to unaffected hardware"

modified_intel_root="$test_root/modified-intel"
prepare_root "$modified_intel_root"
install -d "$modified_intel_root/etc/modprobe.d"
printf 'administrator policy\n' \
  >"$modified_intel_root/etc/modprobe.d/qvos-intel-wifi7-eht.conf"
if QVOS_TEST_LSPCI="$intel_inventory" run_stage "$modified_intel_root" \
  "$root/qvcore/install/config/hardware/intel/fix-wifi7-eht.sh" \
  >/dev/null 2>&1; then
  fail "modified Intel Wi-Fi policy was accepted"
fi
[[ $(<"$modified_intel_root/etc/modprobe.d/qvos-intel-wifi7-eht.conf") == \
  "administrator policy" ]] || fail "modified Intel Wi-Fi policy was changed"

asus_root="$test_root/asus"
prepare_root "$asus_root"
install -d "$asus_root/sys/class/dmi/id"
printf 'ASUSTeK COMPUTER INC.\n' >"$asus_root/sys/class/dmi/id/sys_vendor"
printf 'ExpertBook B9406\n' >"$asus_root/sys/class/dmi/id/product_name"
asus_inventory='00:02.0 VGA compatible controller: Intel Panther Lake Graphics [8086:1234]'
QVOS_TEST_LSPCI="$asus_inventory" run_stage "$asus_root" \
  "$root/qvcore/install/config/hardware/asus/fix-asus-ptl-b9406-display.sh"
QVOS_TEST_LSPCI="$asus_inventory" run_stage "$asus_root" \
  "$root/qvcore/install/config/hardware/asus/fix-asus-ptl-display-backlight.sh"
QVOS_TEST_LSPCI="$asus_inventory" run_stage "$asus_root" \
  "$root/qvcore/install/hardware/asus/b9406-touchpad"
cmp -s "$asus_b9406_display_source" \
  "$asus_root/etc/limine-entry-tool.d/90-qvos-asus-b9406-display.conf" ||
  fail "native ASUS B9406 display policy"
cmp -s "$asus_ptl_backlight_source" \
  "$asus_root/etc/limine-entry-tool.d/90-qvos-asus-ptl-backlight.conf" ||
  fail "native ASUS Panther Lake backlight policy"
cmp -s "$asus_b9406_touchpad_source" \
  "$asus_root/usr/share/libinput/99-qvos-asus-b9406-touchpad.quirks" ||
  fail "native ASUS B9406 touchpad policy"

apple_spi_root="$test_root/apple-spi"
prepare_root "$apple_spi_root"
install -d "$apple_spi_root/sys/class/dmi/id"
printf 'Apple Inc.\n' >"$apple_spi_root/sys/class/dmi/id/sys_vendor"
printf 'MacBookPro14,3\n' >"$apple_spi_root/sys/class/dmi/id/product_name"
: >"$event_log"
run_stage "$apple_spi_root" \
  "$root/qvcore/install/config/hardware/apple/fix-spi-keyboard.sh"
cmp -s "$apple_spi_modern_source" \
  "$apple_spi_root/etc/mkinitcpio.conf.d/qvos-apple-spi.conf" ||
  fail "native modern Apple SPI keyboard policy"
grep -Fqx 'qv-pkg-add|macbook12-spi-driver-dkms' "$event_log" ||
  fail "Apple SPI driver package request"

apple_spi_old_root="$test_root/apple-spi-old"
prepare_root "$apple_spi_old_root"
install -d "$apple_spi_old_root/sys/class/dmi/id"
printf 'Apple Inc.\n' >"$apple_spi_old_root/sys/class/dmi/id/sys_vendor"
printf 'MacBook8,1\n' >"$apple_spi_old_root/sys/class/dmi/id/product_name"
run_owner "$apple_spi_old_root" apple-spi-keyboard
cmp -s "$apple_spi_macbook8_source" \
  "$apple_spi_old_root/etc/mkinitcpio.conf.d/qvos-apple-spi.conf" ||
  fail "native MacBook8,1 SPI keyboard policy"

lenovo_root="$test_root/lenovo"
prepare_root "$lenovo_root"
install -d "$lenovo_root/sys/class/dmi/id"
printf 'LENOVO\n' >"$lenovo_root/sys/class/dmi/id/sys_vendor"
printf 'Yoga Pro 7 14IAH10\n' >"$lenovo_root/sys/class/dmi/id/product_name"
run_stage "$lenovo_root" \
  "$root/qvcore/install/config/hardware/lenovo/fix-yoga-pro7-bass-speakers.sh"
cmp -s "$lenovo_yoga_source" \
  "$lenovo_root/etc/modprobe.d/qvos-lenovo-yoga-pro7-bass.conf" ||
  fail "native Lenovo Yoga Pro 7 speaker policy"

foreign_model_root="$test_root/foreign-model"
prepare_root "$foreign_model_root"
install -d "$foreign_model_root/sys/class/dmi/id"
printf 'Other Vendor\n' >"$foreign_model_root/sys/class/dmi/id/sys_vendor"
printf 'Yoga Pro 7 14IAH10\n' >"$foreign_model_root/sys/class/dmi/id/product_name"
run_stage "$foreign_model_root" \
  "$root/qvcore/install/config/hardware/lenovo/fix-yoga-pro7-bass-speakers.sh"
[[ ! -e $foreign_model_root/etc/modprobe.d/qvos-lenovo-yoga-pro7-bass.conf ]] ||
  fail "Lenovo speaker policy applied by model substring alone"

nvidia_root="$test_root/nvidia"
prepare_root "$nvidia_root"
QVOS_TEST_LSPCI='01:00.0 VGA compatible controller: NVIDIA Corporation GeForce RTX 4060 [10de:2882]' \
  run_owner "$nvidia_root" nvidia-boot
nvidia_modprobe_target="$nvidia_root/etc/modprobe.d/qvos-nvidia.conf"
nvidia_mkinitcpio_target="$nvidia_root/etc/mkinitcpio.conf.d/qvos-nvidia.conf"
cmp -s "$nvidia_modprobe_source" "$nvidia_modprobe_target" ||
  fail "native NVIDIA modprobe policy"
cmp -s "$nvidia_mkinitcpio_source" "$nvidia_mkinitcpio_target" ||
  fail "native NVIDIA initramfs policy"
nvidia_modprobe_inode=$(stat -c '%i' "$nvidia_modprobe_target")
nvidia_mkinitcpio_inode=$(stat -c '%i' "$nvidia_mkinitcpio_target")
QVOS_TEST_LSPCI='01:00.0 VGA compatible controller: NVIDIA Corporation GeForce RTX 4060 [10de:2882]' \
  run_owner "$nvidia_root" nvidia-boot
[[ $(stat -c '%i' "$nvidia_modprobe_target") == "$nvidia_modprobe_inode" &&
  $(stat -c '%i' "$nvidia_mkinitcpio_target") == \
  "$nvidia_mkinitcpio_inode" ]] ||
  fail "idempotent native NVIDIA boot-policy install"

nvidia_rollback_root="$test_root/nvidia-rollback"
prepare_root "$nvidia_rollback_root"
install -d "$nvidia_rollback_root/etc/mkinitcpio.conf.d"
printf 'administrator policy\n' \
  >"$nvidia_rollback_root/etc/mkinitcpio.conf.d/qvos-nvidia.conf"
if QVOS_TEST_LSPCI='01:00.0 VGA compatible controller: NVIDIA Corporation GeForce GTX 1060 [10de:1c20]' \
  run_owner "$nvidia_rollback_root" nvidia-boot >/dev/null 2>&1; then
  fail "modified NVIDIA boot policy was accepted"
fi
[[ ! -e $nvidia_rollback_root/etc/modprobe.d/qvos-nvidia.conf &&
  $(<"$nvidia_rollback_root/etc/mkinitcpio.conf.d/qvos-nvidia.conf") == \
  "administrator policy" ]] ||
  fail "NVIDIA boot-policy failure did not roll back its new first file"

unsupported_nvidia_root="$test_root/unsupported-nvidia"
prepare_root "$unsupported_nvidia_root"
QVOS_TEST_LSPCI='01:00.0 VGA compatible controller: NVIDIA Corporation GeForce GTX 780 [10de:1004]' \
  run_owner "$unsupported_nvidia_root" nvidia-boot
[[ ! -e $unsupported_nvidia_root/etc/modprobe.d/qvos-nvidia.conf &&
  ! -e $unsupported_nvidia_root/etc/mkinitcpio.conf.d/qvos-nvidia.conf ]] ||
  fail "NVIDIA boot policy applied to an unsupported GPU"

surface_root="$test_root/surface"
prepare_root "$surface_root"
install -d "$surface_root/sys/class/dmi/id" "$surface_root/proc"
printf 'Microsoft Corporation\n' >"$surface_root/sys/class/dmi/id/sys_vendor"
printf 'Surface Laptop 3\n' >"$surface_root/sys/class/dmi/id/product_name"
printf 'pinctrl_icelake 16384 0 - Live 0x0000000000000000\n' \
  >"$surface_root/proc/modules"
run_stage "$surface_root" \
  "$root/qvcore/install/config/hardware/fix-surface-keyboard.sh"
surface_target="$surface_root/etc/mkinitcpio.conf.d/qvos-surface-keyboard.conf"
expected_surface_policy='MODULES=(pinctrl_icelake intel_lpss intel_lpss_pci 8250_dw surface_aggregator surface_aggregator_registry surface_aggregator_hub surface_hid_core surface_hid)'
[[ $(<"$surface_target") == "$expected_surface_policy" ]] ||
  fail "native Intel Surface keyboard policy"
surface_inode=$(stat -c '%i' "$surface_target")
run_stage "$surface_root" \
  "$root/qvcore/install/config/hardware/fix-surface-keyboard.sh"
[[ $(stat -c '%i' "$surface_target") == "$surface_inode" ]] ||
  fail "idempotent Surface keyboard policy install"

surface_amd_root="$test_root/surface-amd"
prepare_root "$surface_amd_root"
install -d "$surface_amd_root/sys/class/dmi/id" "$surface_amd_root/proc" \
  "$surface_amd_root/usr/lib/modules/test/build"
printf 'Microsoft Corporation\n' \
  >"$surface_amd_root/sys/class/dmi/id/sys_vendor"
printf 'Surface Laptop 3\n' \
  >"$surface_amd_root/sys/class/dmi/id/product_name"
printf 'vendor_id : AuthenticAMD\n' >"$surface_amd_root/proc/cpuinfo"
: >"$surface_amd_root/proc/modules"
printf 'CONFIG_PINCTRL_AMD=y\n' \
  >"$surface_amd_root/usr/lib/modules/test/build/.config"
run_owner "$surface_amd_root" surface-keyboard
[[ $(<"$surface_amd_root/etc/mkinitcpio.conf.d/qvos-surface-keyboard.conf") == \
  'MODULES=(8250_dw surface_aggregator surface_aggregator_registry surface_aggregator_hub surface_hid_core surface_hid)' ]] ||
  fail "native AMD Surface keyboard policy"

surface_old_root="$test_root/surface-old"
prepare_root "$surface_old_root"
install -d "$surface_old_root/sys/class/dmi/id" "$surface_old_root/proc"
printf 'Microsoft Corporation\n' \
  >"$surface_old_root/sys/class/dmi/id/sys_vendor"
printf 'Surface Laptop 2\n' \
  >"$surface_old_root/sys/class/dmi/id/product_name"
printf 'pinctrl_cannonlake 16384 0 - Live 0x0000000000000000\n' \
  >"$surface_old_root/proc/modules"
run_owner "$surface_old_root" surface-keyboard
grep -Fqw surface_kbd \
  "$surface_old_root/etc/mkinitcpio.conf.d/qvos-surface-keyboard.conf" ||
  fail "older Surface keyboard driver selection"
if grep -Fqw surface_hid \
  "$surface_old_root/etc/mkinitcpio.conf.d/qvos-surface-keyboard.conf"; then
  fail "older Surface keyboard policy includes the wrong input driver"
fi

unsupported_surface_root="$test_root/unsupported-surface"
prepare_root "$unsupported_surface_root"
install -d "$unsupported_surface_root/sys/class/dmi/id"
printf 'Microsoft Corporation\n' \
  >"$unsupported_surface_root/sys/class/dmi/id/sys_vendor"
printf 'Surface Pro 9\n' \
  >"$unsupported_surface_root/sys/class/dmi/id/product_name"
run_owner "$unsupported_surface_root" surface-keyboard
[[ ! -e $unsupported_surface_root/etc/mkinitcpio.conf.d/qvos-surface-keyboard.conf ]] ||
  fail "Surface keyboard policy applied to an unrelated model"

missing_surface_root="$test_root/missing-surface-pinctrl"
prepare_root "$missing_surface_root"
install -d "$missing_surface_root/sys/class/dmi/id" "$missing_surface_root/proc"
printf 'Microsoft Corporation\n' \
  >"$missing_surface_root/sys/class/dmi/id/sys_vendor"
printf 'Surface Laptop 4\n' \
  >"$missing_surface_root/sys/class/dmi/id/product_name"
: >"$missing_surface_root/proc/modules"
if run_owner "$missing_surface_root" surface-keyboard >/dev/null 2>&1; then
  fail "Surface keyboard policy accepted a missing pin-controller module"
fi
[[ ! -e $missing_surface_root/etc/mkinitcpio.conf.d/qvos-surface-keyboard.conf ]] ||
  fail "failed Surface detection left an initramfs policy"

ambiguous_surface_root="$test_root/ambiguous-surface-pinctrl"
prepare_root "$ambiguous_surface_root"
install -d "$ambiguous_surface_root/sys/class/dmi/id" \
  "$ambiguous_surface_root/proc"
printf 'Microsoft Corporation\n' \
  >"$ambiguous_surface_root/sys/class/dmi/id/sys_vendor"
printf 'Surface Laptop Studio\n' \
  >"$ambiguous_surface_root/sys/class/dmi/id/product_name"
printf '%s\n' \
  'pinctrl_icelake 16384 0 - Live 0x0000000000000000' \
  'pinctrl_tigerlake 16384 0 - Live 0x0000000000000000' \
  >"$ambiguous_surface_root/proc/modules"
if run_owner "$ambiguous_surface_root" surface-keyboard >/dev/null 2>&1; then
  fail "Surface keyboard policy accepted ambiguous pin-controller modules"
fi
[[ ! -e $ambiguous_surface_root/etc/mkinitcpio.conf.d/qvos-surface-keyboard.conf ]] ||
  fail "ambiguous Surface detection left an initramfs policy"

modified_surface_root="$test_root/modified-surface"
prepare_root "$modified_surface_root"
install -d "$modified_surface_root/sys/class/dmi/id" \
  "$modified_surface_root/proc" "$modified_surface_root/etc/mkinitcpio.conf.d"
printf 'Microsoft Corporation\n' \
  >"$modified_surface_root/sys/class/dmi/id/sys_vendor"
printf 'Surface Laptop 4\n' \
  >"$modified_surface_root/sys/class/dmi/id/product_name"
printf 'pinctrl_tigerlake 16384 0 - Live 0x0000000000000000\n' \
  >"$modified_surface_root/proc/modules"
printf 'administrator policy\n' \
  >"$modified_surface_root/etc/mkinitcpio.conf.d/qvos-surface-keyboard.conf"
if run_owner "$modified_surface_root" surface-keyboard >/dev/null 2>&1; then
  fail "modified Surface keyboard policy was accepted"
fi
[[ $(<"$modified_surface_root/etc/mkinitcpio.conf.d/qvos-surface-keyboard.conf") == \
  "administrator policy" ]] ||
  fail "modified Surface keyboard policy was changed"

synaptics_root="$test_root/synaptics"
prepare_root "$synaptics_root"
install -D -m 0644 /dev/stdin \
  "$synaptics_root/proc/bus/input/devices" <<'EOF'
N: Name="SynPS/2 Synaptics TouchPad"
EOF
run_stage "$synaptics_root" \
  "$root/qvcore/install/config/hardware/fix-synaptic-touchpad.sh"
synaptics_target="$synaptics_root/etc/modprobe.d/qvos-psmouse-synaptics.conf"
cmp -s "$synaptics_source" "$synaptics_target" ||
  fail "native Synaptics PS/2 policy"
synaptics_inode=$(stat -c '%i' "$synaptics_target")
run_stage "$synaptics_root" \
  "$root/qvcore/install/config/hardware/fix-synaptic-touchpad.sh"
[[ $(stat -c '%i' "$synaptics_target") == "$synaptics_inode" ]] ||
  fail "idempotent native Synaptics PS/2 policy install"

i2c_touchpad_root="$test_root/i2c-touchpad"
prepare_root "$i2c_touchpad_root"
install -D -m 0644 /dev/stdin \
  "$i2c_touchpad_root/proc/bus/input/devices" <<'EOF'
N: Name="SYNA2B46:00 06CB:CD5F Touchpad"
EOF
run_stage "$i2c_touchpad_root" \
  "$root/qvcore/install/config/hardware/fix-synaptic-touchpad.sh"
[[ ! -e $i2c_touchpad_root/etc/modprobe.d/qvos-psmouse-synaptics.conf ]] ||
  fail "Synaptics PS/2 policy applied to an I2C touchpad"

tuxedo_root="$test_root/tuxedo"
prepare_root "$tuxedo_root"
install -d "$tuxedo_root/sys/class/dmi/id"
printf 'TUXEDO Computers GmbH\n' \
  >"$tuxedo_root/sys/class/dmi/id/sys_vendor"
: >"$event_log"
run_stage "$tuxedo_root" \
  "$root/qvcore/install/config/hardware/fix-tuxedo-backlight.sh"
tuxedo_target="$tuxedo_root/etc/modprobe.d/qvos-tuxedo-backlight.conf"
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
[[ ! -e $unaffected_tuxedo_root/etc/modprobe.d/qvos-tuxedo-backlight.conf &&
  ! -s $event_log ]] || fail "Tuxedo policy applied to unrelated hardware"

modified_tuxedo_root="$test_root/modified-tuxedo"
prepare_root "$modified_tuxedo_root"
install -d "$modified_tuxedo_root/sys/class/dmi/id" \
  "$modified_tuxedo_root/etc/modprobe.d"
printf 'Slimbook\n' >"$modified_tuxedo_root/sys/class/dmi/id/sys_vendor"
printf 'administrator policy\n' \
  >"$modified_tuxedo_root/etc/modprobe.d/qvos-tuxedo-backlight.conf"
if run_stage "$modified_tuxedo_root" \
  "$root/qvcore/install/config/hardware/fix-tuxedo-backlight.sh" \
  >/dev/null 2>&1; then
  fail "modified Tuxedo policy was accepted"
fi
[[ $(<"$modified_tuxedo_root/etc/modprobe.d/qvos-tuxedo-backlight.conf") == \
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
if rg -n '/etc/default/limine|sudo[[:space:]]+tee|modprobe[[:space:]]+psmouse' \
  "$root/qvcore/install/config/hardware/fix-fkeys.sh" \
  "$root/qvcore/install/config/hardware/fix-synaptic-touchpad.sh" \
  "$root/qvcore/install/config/hardware/intel/fred.sh" \
  "$root/qvcore/install/config/hardware/intel/fix-wifi7-eht.sh"; then
  fail "static hardware policy bypasses the native root owner"
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
