#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
owner="$root/qvcore/hardware/detect"
test_root=$(mktemp -d)
fixture="$test_root/fixture"
test_bin="$test_root/bin"
mkdir -p \
  "$fixture/sys/class/dmi/id" \
  "$fixture/sys/class/drm" \
  "$fixture/sys/bus/i2c/devices" \
  "$fixture/proc" \
  "$fixture/usr/share/vulkan/icd.d" \
  "$test_bin"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'STUB'
#!/bin/bash
for command_name in "$@"; do
  case ",${QVOS_TEST_COMMANDS:-}," in
  *",$command_name,"*) ;;
  *) exit 1 ;;
  esac
done
STUB
install -m 0755 /dev/stdin "$test_bin/lspci" <<'STUB'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_LSPCI:-}"
STUB
install -m 0755 /dev/stdin "$test_bin/supergfxctl" <<'STUB'
#!/bin/bash
[[ ${1:-} == "-s" && $# == 1 ]] || exit 2
[[ ${QVOS_TEST_SUPERGFX_STATUS:-0} == "0" ]] || exit "$QVOS_TEST_SUPERGFX_STATUS"
printf '%s\n' "${QVOS_TEST_SUPERGFX:-}"
STUB
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'STUB'
#!/bin/bash
[[ ${1:-} == "devices" && ${2:-} == "-j" && $# == 2 ]] || exit 2
printf '%s\n' "${QVOS_TEST_HYPR_JSON:-}"
STUB

run_detect() {
  local hypr_json=${QVOS_TEST_HYPR_JSON:-}

  [[ -n $hypr_json ]] || hypr_json='{}'
  PATH="$test_bin:/usr/bin" \
  QVOS_HARDWARE_TESTING=1 \
  QVOS_HARDWARE_FIXTURE_ROOT="$fixture" \
  QVOS_TEST_COMMANDS="${QVOS_TEST_COMMANDS:-lspci,hyprctl,jq}" \
  QVOS_TEST_LSPCI="${QVOS_TEST_LSPCI:-}" \
  QVOS_TEST_SUPERGFX="${QVOS_TEST_SUPERGFX:-}" \
  QVOS_TEST_SUPERGFX_STATUS="${QVOS_TEST_SUPERGFX_STATUS:-0}" \
  QVOS_TEST_HYPR_JSON="$hypr_json" \
    "$owner" "$@"
}

if QVOS_HARDWARE_FIXTURE_ROOT="$fixture" "$owner" intel >/dev/null 2>&1; then
  fail "fixture override worked outside test mode"
fi
if QVOS_HARDWARE_TESTING=1 QVOS_HARDWARE_FIXTURE_ROOT="$fixture/missing" \
  "$owner" intel >/dev/null 2>&1; then
  fail "missing fixture root was accepted"
fi
if QVOS_HARDWARE_TESTING=1 QVOS_HARDWARE_FIXTURE_ROOT=/ \
  "$owner" intel >/dev/null 2>&1; then
  fail "live root was accepted as a hardware fixture"
fi
if run_detect match >/dev/null 2>&1 || run_detect match value extra >/dev/null 2>&1; then
  fail "DMI matcher accepted invalid arity"
fi

printf 'ASUSTeK COMPUTER INC.\n' >"$fixture/sys/class/dmi/id/sys_vendor"
printf 'ExpertBook B9406 Demo [Fixed]\n' >"$fixture/sys/class/dmi/id/product_name"
printf 'ROG Zephyrus\n' >"$fixture/sys/class/dmi/id/product_family"
QVOS_TEST_LSPCI='00:02.0 VGA compatible controller: Intel Panther Lake Graphics' \
  run_detect asus-expertbook-b9406 || fail "ASUS B9406 detector"
run_detect asus-rog || fail "ASUS ROG detector"
run_detect match '[Fixed]' || fail "fixed-string DMI match"
if run_detect match '[missing]*' >/dev/null 2>&1; then
  fail "DMI matcher treated caller input as a regular expression"
fi
printf 'Zenbook UX5406AA\n' >"$fixture/sys/class/dmi/id/product_name"
QVOS_TEST_LSPCI='00:02.0 Display controller: Intel Panther Lake Graphics' \
  run_detect asus-zenbook-ux5406aa || fail "ASUS UX5406AA detector"

printf 'Dell XPS 13\n' >"$fixture/sys/class/dmi/id/product_name"
mkdir -p "$fixture/sys/bus/i2c/devices/i2c-VEN_06CB:00"
run_detect dell-xps-haptic-touchpad || fail "Dell haptic touchpad detector"
mkdir -p "$fixture/sys/class/drm/card0-eDP-1"
printf '\0\0\0\0\0\0\0\0\x30\xe4' >"$fixture/sys/class/drm/card0-eDP-1/edid"
QVOS_TEST_LSPCI='00:02.0 VGA compatible controller: Intel Panther Lake Graphics' \
  run_detect dell-xps-oled || fail "Dell XPS OLED detector"

printf 'connected\n' >"$fixture/sys/class/drm/card0-eDP-1/status"
if run_detect external-monitors >/dev/null 2>&1; then
  fail "internal panel was reported as external"
fi
mkdir -p "$fixture/sys/class/drm/card0-HDMI-A-1"
printf 'disconnected\n' >"$fixture/sys/class/drm/card0-HDMI-A-1/status"
if run_detect external-monitors >/dev/null 2>&1; then
  fail "disconnected output was reported as external"
fi
printf 'connected\n' >"$fixture/sys/class/drm/card0-HDMI-A-1/status"
run_detect external-monitors || fail "connected external monitor detector"

printf 'Framework\n' >"$fixture/sys/class/dmi/id/sys_vendor"
printf 'Laptop 16 (AMD Ryzen 7040 Series)\n' >"$fixture/sys/class/dmi/id/product_name"
run_detect framework16 || fail "Framework 16 detector"
printf 'Microsoft Corporation\n' >"$fixture/sys/class/dmi/id/sys_vendor"
printf 'Surface Laptop\n' >"$fixture/sys/class/dmi/id/product_family"
run_detect surface || fail "Surface detector"

QVOS_TEST_COMMANDS='lspci,hyprctl,jq,supergfxctl' \
QVOS_TEST_SUPERGFX='[Integrated, Hybrid]' run_detect hybrid-gpu ||
  fail "supergfx hybrid detector"
if QVOS_TEST_COMMANDS='lspci,hyprctl,jq,supergfxctl' \
  QVOS_TEST_SUPERGFX='[Hybrid]' run_detect hybrid-gpu >/dev/null 2>&1; then
  fail "single-mode supergfx inventory reported Hybrid GPU support"
fi
QVOS_TEST_LSPCI=$'00:02.0 VGA compatible controller: Intel\n01:00.0 3D controller: NVIDIA' \
  run_detect hybrid-gpu || fail "PCI hybrid detector"
if QVOS_TEST_LSPCI=$'00:02.0 VGA compatible controller: Intel\n01:00.0 3D controller: AMD' \
  run_detect hybrid-gpu >/dev/null 2>&1; then
  fail "dual non-NVIDIA display controllers reported supergfx support"
fi
QVOS_TEST_COMMANDS='lspci,hyprctl,jq,supergfxctl' \
QVOS_TEST_SUPERGFX_STATUS=1 \
QVOS_TEST_LSPCI=$'00:02.0 VGA compatible controller: Intel\n01:00.0 3D controller: NVIDIA' \
  run_detect hybrid-gpu || fail "PCI fallback after unavailable supergfx daemon"

printf 'vendor_id : GenuineIntel\n' >"$fixture/proc/cpuinfo"
run_detect intel || fail "Intel CPU detector"
QVOS_TEST_LSPCI='00:1f.3 Multimedia audio controller: Intel Corporation Device' \
  run_detect intel-sof || fail "Intel SOF detector"
QVOS_TEST_LSPCI='01:00.0 VGA compatible controller: NVIDIA Corporation GeForce RTX 4060' \
  run_detect nvidia-gsp || fail "NVIDIA GSP detector"
QVOS_TEST_LSPCI='01:00.0 VGA compatible controller: NVIDIA Corporation GeForce GTX 1060' \
  run_detect nvidia-without-gsp || fail "NVIDIA pre-GSP detector"

device_json='{"mice":[{"name":"usb-mouse"},{"name":"elan-touchpad"}],"touch":[{"name":"goodix-touchscreen"}],"tablets":[]}'
touchpad=$(QVOS_TEST_HYPR_JSON="$device_json" run_detect touchpad)
[[ $touchpad == "elan-touchpad" ]] || fail "touchpad selector"
touchscreen=$(QVOS_TEST_HYPR_JSON="$device_json" run_detect touchscreen)
[[ $touchscreen == "goodix-touchscreen" ]] || fail "touchscreen selector"
empty_device_json='{"mice":[],"touch":[],"tablets":[]}'
set +e
QVOS_TEST_HYPR_JSON="$empty_device_json" run_detect touchscreen >/dev/null 2>&1
empty_touchscreen_status=$?
QVOS_TEST_HYPR_JSON='{"mice":[]}' run_detect touchscreen >/dev/null 2>&1
malformed_touchscreen_status=$?
set -e
((empty_touchscreen_status == 1)) || fail "absent touchscreen status"
((malformed_touchscreen_status == 2)) || fail "malformed device inventory status"

if run_detect vulkan >/dev/null 2>&1; then
  fail "empty Vulkan directory reported capability"
fi
printf '{}\n' >"$fixture/usr/share/vulkan/icd.d/test_icd.json"
run_detect vulkan || fail "Vulkan ICD detector"

PATH="$test_bin:/usr/bin" \
QVOS_PATH="$root" \
QVOS_HARDWARE_TESTING=1 \
QVOS_HARDWARE_FIXTURE_ROOT="$fixture" \
  "$root/bin/qv-hw-intel" || fail "native hardware adapter"
PATH="$test_bin:/usr/bin" \
QVOS_PATH="$root" \
QVOS_HARDWARE_TESTING=1 \
QVOS_HARDWARE_FIXTURE_ROOT="$fixture" \
  "$root/bin/omarchy-hw-intel" || fail "hardware compatibility adapter"

printf 'ok - hardware detection is bounded, fixture-safe, and read-only\n'
